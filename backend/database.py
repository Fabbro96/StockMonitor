import os
import glob
import hashlib
import sqlite3
import logging
from datetime import datetime
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy import text, event
from backend.config import settings

logger = logging.getLogger(__name__)

DATABASE_URL = f"sqlite+aiosqlite:///{settings.DB_PATH}"

# ---------------------------------------------------------------------------
# Cifratura at-rest (SQLCipher)
# ---------------------------------------------------------------------------
# Stato rilevato dai primi 16 byte del file: magic SQLite = plaintext,
# qualsiasi altro contenuto = cifrato (fail-closed: un file illeggibile o
# troncato viene trattato come cifrato, mai sovrascritto).
SQLITE_MAGIC = b"SQLite format 3\x00"
ENCRYPTED_TMP_SUFFIX = ".encrypted-tmp"
PLAINTEXT_BACKUP_PREFIX = ".plaintext-bak-"
_SIDECAR_SUFFIXES = ("-wal", "-shm", "-journal")


class DbEncryptionError(Exception):
    """Errore fatale di cifratura: lo startup deve bloccarsi, niente è stato sovrascritto."""


def _escape_sqlite_literal(value: str) -> str:
    """Escape per letterali stringa SQL (apici singoli raddoppiati)."""
    return value.replace("'", "''")


def _quote_ident(name: str) -> str:
    """Quota un identificatore SQL (nomi tabella da sqlite_master)."""
    return '"' + name.replace('"', '""') + '"'


def detect_db_state(path: str) -> str:
    """Rileva lo stato di un file DB: 'missing' | 'empty' | 'plaintext' | 'encrypted'.

    Puro (solo path esplicito, nessuna I/O in scrittura), quindi unit-testabile.
    Qualunque contenuto non vuoto diverso dal magic SQLite è 'encrypted'
    (fail-closed: mai aperto/scritto senza chiave).
    """
    if not os.path.exists(path):
        return "missing"
    try:
        if os.path.getsize(path) == 0:
            return "empty"
    except OSError:
        return "missing"
    try:
        with open(path, "rb") as fh:
            header = fh.read(16)
    except OSError:
        return "encrypted"
    if header == SQLITE_MAGIC:
        return "plaintext"
    return "encrypted"


def _utc_stamp() -> str:
    """Timestamp univoco (microsecondi + PID) per nomi tmp/backup senza collisioni."""
    return datetime.now().strftime("%Y%m%d-%H%M%S-%f") + f"-{os.getpid()}"


def _ensure_parent_dir(path: str) -> None:
    """Crea la parent dir; OSError wrappato in DbEncryptionError (fail-closed)."""
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        try:
            os.makedirs(parent, exist_ok=True)
        except OSError as e:
            raise DbEncryptionError(f"Creazione directory {parent} fallita: {e}") from e


def _find_orphans(db_path: str) -> list:
    """Residui di migrazione interrotta (`<db>.encrypted-tmp*`, `<db>.plaintext-bak-*`)."""
    base = glob.escape(db_path)
    found = []
    for pattern in (base + ENCRYPTED_TMP_SUFFIX + "*", base + PLAINTEXT_BACKUP_PREFIX + "*"):
        found.extend(glob.glob(pattern))
    return sorted(found)


def _remove_best_effort(path: str, notes: list) -> None:
    """Rimozione tmp: gli OSError vengono annotati (non mascherano l'errore primario)."""
    try:
        if os.path.exists(path):
            os.remove(path)
    except OSError as e:
        notes.append(f"{path}: {e}")


def _fsync_file(path: str) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _fsync_dir(path: str) -> None:
    fd = os.open(os.path.dirname(os.path.abspath(path)) or ".", os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _table_row_counts(conn) -> dict:
    """Mappa {tabella: n_righe} per le tabelle utente (esclude sqlite_%)."""
    tables = [
        row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).fetchall()
    ]
    return {
        table: conn.execute(f"SELECT count(*) FROM {_quote_ident(table)}").fetchone()[0]
        for table in tables
    }


def _table_content_hash(conn, table: str) -> str:
    """Checksum sha256 del contenuto ordinato di una tabella (dati, non solo conteggi)."""
    info = conn.execute(f"PRAGMA table_info({_quote_ident(table)})").fetchall()
    sql_row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", (table,)
    ).fetchone()
    without_rowid = bool(sql_row and sql_row[0] and "WITHOUT ROWID" in sql_row[0].upper())
    if without_rowid:
        pk_cols = [r[1] for r in info if len(r) > 5 and r[5]]
        order_cols = pk_cols or [r[1] for r in info]
        order_by = "ORDER BY " + ", ".join(_quote_ident(c) for c in order_cols) if order_cols else ""
    else:
        order_by = "ORDER BY rowid"
    h = hashlib.sha256()
    h.update(f"{table}\0".encode("utf-8"))
    cur = conn.execute(f"SELECT * FROM {_quote_ident(table)} {order_by}")
    for row in cur:
        h.update(repr(tuple(row)).encode("utf-8") + b"\0")
    return h.hexdigest()


def _db_snapshot(conn) -> dict:
    """Snapshot di verifica: conteggi + dump sqlite_master + hash contenuti per tabella."""
    counts = _table_row_counts(conn)
    schema = [
        tuple(row) for row in conn.execute(
            "SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY name"
        ).fetchall()
    ]
    return {
        "counts": counts,
        "schema": schema,
        "hashes": {table: _table_content_hash(conn, table) for table in counts},
    }


def _open_encrypted(path: str, key: str, timeout: float = 30.0):
    """Apre un DB cifrato con fail-fast: chiave errata -> DatabaseError immediato."""
    import sqlcipher3
    conn = sqlcipher3.connect(path, timeout=timeout, check_same_thread=False, isolation_level=None)
    try:
        conn.execute(f"PRAGMA key='{_escape_sqlite_literal(key)}'")
        conn.execute("SELECT count(*) FROM sqlite_master").fetchone()
    except Exception:
        conn.close()
        raise
    return conn


def migrate_plaintext_to_encrypted(db_path: str, db_key: str) -> str:
    """Migra un DB plaintext in cifrato senza perdita dati. Ritorna il path del backup.

    Procedura sotto lock esclusivo (flock, single-writer): checkpoint WAL sul
    plaintext, export su file temporaneo `<db>.encrypted-tmp-<ts>-<pid>` via
    ATTACH + sqlcipher_export(), reimpostazione di user_version e
    journal_mode=WAL (l'export non li copia), verifica snapshot completo
    (dump sqlite_master + conteggi + hash contenuti per tabella), fsync di file
    e directory, spostamento degli originali in `<db>.plaintext-bak-<ts>-<pid>`
    e commit con un SINGOLO `os.replace` atomico. chmod 0600 ovunque.
    Qualunque fallimento lascia gli originali intatti e solleva DbEncryptionError
    (mai OSError grezzo); i tmp orfani non vengono mai cancellati qui, ma
    bloccano il resume in ensure_db_encryption (fail-closed).
    """
    import fcntl
    import sqlcipher3

    if not db_key:
        raise DbEncryptionError("Migrazione annullata: DB_KEY assente.")
    _ensure_parent_dir(db_path)
    stamp = _utc_stamp()
    tmp_path = f"{db_path}{ENCRYPTED_TMP_SUFFIX}-{stamp}"
    if os.path.exists(tmp_path):
        raise DbEncryptionError(f"Migrazione annullata: tmp {tmp_path} già esistente.")

    logger.info(f"Migrazione cifratura: checkpoint WAL + export di {db_path}")
    try:
        lock_fd = os.open(db_path, os.O_RDONLY)
    except OSError as e:
        raise DbEncryptionError(f"Migrazione annullata: apertura {db_path} per lock fallita: {e}") from e
    try:
        try:
            # Lock esclusivo per tutta export+swap: single-writer durante la migrazione.
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
        except OSError as e:
            raise DbEncryptionError(f"Migrazione annullata: lock esclusivo su {db_path} fallito: {e}") from e

        # Re-check dentro il lock: un migratore concorrente potrebbe aver già vinto.
        if detect_db_state(db_path) != "plaintext":
            raise DbEncryptionError(
                f"Migrazione annullata: {db_path} non è plaintext (già migrato in concorrenza?)."
            )

        # L'export DEVE girare su connessione SQLCipher (sqlcipher_export non esiste
        # in sqlite3 stdlib); SQLCipher apre il plaintext senza chiave.
        src = sqlcipher3.connect(db_path, timeout=30.0, check_same_thread=False, isolation_level=None)
        try:
            src.execute("PRAGMA busy_timeout=30000")
            src.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            user_version = src.execute("PRAGMA user_version").fetchone()[0]
            snapshot_before = _db_snapshot(src)
            src.execute(
                f"ATTACH DATABASE '{_escape_sqlite_literal(tmp_path)}' AS encrypted "
                f"KEY '{_escape_sqlite_literal(db_key)}'"
            )
            try:
                src.execute("SELECT sqlcipher_export('encrypted')")
            finally:
                src.execute("DETACH DATABASE encrypted")
        except Exception as e:
            notes: list = []
            _remove_best_effort(tmp_path, notes)
            logger.error(f"Migrazione cifratura fallita in export (originali intatti): {e} {notes}")
            raise DbEncryptionError(f"Export cifrato fallito, originali intatti: {e} {notes}") from e
        finally:
            src.close()

        try:
            dst = _open_encrypted(tmp_path, db_key)
            try:
                # L'export non copia user_version né journal_mode: vanno reimpostati.
                dst.execute(f"PRAGMA user_version={int(user_version)}")
                dst.execute("PRAGMA journal_mode=WAL")
                snapshot_after = _db_snapshot(dst)
                dst.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            finally:
                dst.close()
        except Exception as e:
            notes = []
            for stale in (tmp_path,) + tuple(tmp_path + s for s in _SIDECAR_SUFFIXES):
                _remove_best_effort(stale, notes)
            logger.error(f"Migrazione cifratura fallita in verifica (originali intatti): {e} {notes}")
            raise DbEncryptionError(f"Verifica export fallita, originali intatti: {e} {notes}") from e

        if snapshot_after != snapshot_before:
            notes = []
            for stale in (tmp_path,) + tuple(tmp_path + s for s in _SIDECAR_SUFFIXES):
                _remove_best_effort(stale, notes)
            logger.error(
                "Migrazione cifratura: snapshot divergente pre/post export "
                "(originali intatti, tmp rimosso)."
            )
            raise DbEncryptionError(
                f"Verifica export fallita: schema/conteggi/contenuti divergenti, originali intatti. {notes}"
            )

        # Durabilità PRIMA di toccare gli originali: chmod + fsync file e dir.
        # Dopo TRUNCATE+close non devono restare sidecar del tmp: lo swap resta
        # un singolo os.replace atomico (niente rename in sequenza sul commit).
        os.chmod(tmp_path, 0o600)
        try:
            _fsync_file(tmp_path)
            _fsync_dir(tmp_path)
        except OSError as e:
            notes = []
            _remove_best_effort(tmp_path, notes)
            raise DbEncryptionError(f"fsync tmp fallita, originali intatti: {e} {notes}") from e
        for suffix in _SIDECAR_SUFFIXES:
            leftover = tmp_path + suffix
            if os.path.exists(leftover):
                logger.warning(f"Sidecar tmp residuo post-checkpoint, rimosso: {leftover}")
                try:
                    os.remove(leftover)
                except OSError as e:
                    raise DbEncryptionError(
                        f"Rimozione sidecar tmp {leftover} fallita, originali intatti: {e}"
                    ) from e

        backup_base = f"{db_path}{PLAINTEXT_BACKUP_PREFIX}{stamp}"
        try:
            for suffix in ("",) + _SIDECAR_SUFFIXES:
                orig = db_path + suffix
                if os.path.exists(orig):
                    os.replace(orig, backup_base + suffix)
            # Commit atomico singolo + fsync della directory.
            os.replace(tmp_path, db_path)
            _fsync_dir(db_path)
        except OSError as e:
            logger.error(f"Migrazione cifratura fallita nello swap: {e}")
            raise DbEncryptionError(
                f"Swap file fallito: {e}. Se {db_path} manca, ripristina "
                f"{backup_base}* sui nomi originali prima di riavviare."
            ) from e

        os.chmod(db_path, 0o600)
        for suffix in ("",) + _SIDECAR_SUFFIXES:
            if os.path.exists(backup_base + suffix):
                os.chmod(backup_base + suffix, 0o600)
        logger.warning(
            f"Migrazione cifratura completata: {db_path} ora cifrato, "
            f"originali plaintext in {backup_base}* (verificare e poi archiviare/cancellare)."
        )
        return backup_base
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)


async def ensure_db_encryption(db_path: str | None = None, db_key: str | None = None) -> None:
    """Garantisce lo stato di cifratura atteso PRIMA di qualunque uso dell'engine.

    - file assente/vuoto -> niente da fare (verrà creato cifrato se DB_KEY c'è),
      MA se esistono residui `<db>.encrypted-tmp*` o `<db>.plaintext-bak-*`
      (migrazione interrotta: MAI creare un DB fresco sopra i dati) -> fail-closed.
    - plaintext + DB_KEY -> migrazione sicura con backup (converge se un
      migratore concorrente ha già vinto la corsa).
    - cifrato + DB_KEY -> niente da fare (fail-fast alla prima connessione se errata).
    - cifrato senza DB_KEY -> DbEncryptionError, startup bloccato (MAI aprire o
      scrivere un cifrato senza chiave: corrompe l'header).
    - plaintext senza DB_KEY -> niente da fare.
    """
    path = db_path or settings.DB_PATH
    key = db_key if db_key is not None else settings.DB_KEY
    _ensure_parent_dir(path)
    state = detect_db_state(path)
    if state in ("missing", "empty"):
        orphans = _find_orphans(path)
        if orphans:
            shown = ", ".join(orphans[:5]) + ("..." if len(orphans) > 5 else "")
            raise DbEncryptionError(
                f"Residui di migrazione interrotta rilevati ({shown}): avvio bloccato "
                f"per non creare un DB vuoto sopra i dati. Ripristina "
                f"{path}{PLAINTEXT_BACKUP_PREFIX}* sui nomi originali, rimuovi i "
                f"residui {path}{ENCRYPTED_TMP_SUFFIX}* e riavvia."
            )
        return
    if state == "plaintext":
        if key:
            logger.warning(f"Database plaintext rilevato con DB_KEY impostata: avvio migrazione ({path}).")
            try:
                migrate_plaintext_to_encrypted(path, key)
            except DbEncryptionError as e:
                if "non è plaintext" in str(e) and key and detect_db_state(path) == "encrypted":
                    logger.warning("Migrazione già completata da un processo concorrente; proseguo.")
                    return
                raise
        return
    if not key:
        raise DbEncryptionError(
            f"Il database {path} è cifrato ma DB_KEY non è impostata: avvio bloccato "
            "(aprire un cifrato senza chiave ne corrompe l'header). Imposta DB_KEY e riavvia."
        )


def _set_sqlite_pragmas(dbapi_connection, connection_record):
    """Assicura che foreign keys, busy timeout e synchronous siano impostati su ogni connessione SQLite."""
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON;")
    # Allineato a connect_args timeout=30 (secondi) dell'engine: stesso limite
    # di attesa sul lock SQLite a livello driver e a livello PRAGMA.
    cursor.execute("PRAGMA busy_timeout=30000;")
    cursor.execute("PRAGMA synchronous=NORMAL;")
    cursor.close()


def create_db_engine(db_path: str | None = None, db_key: str | None = None, echo: bool | None = None):
    """Factory engine: plaintext invariato senza DB_KEY, SQLCipher via async_creator con DB_KEY.

    Con async_creator il pool non apre più connessioni DBAPI standard, quindi il
    listener 'connect' riceverebbe il wrapper adattato (verificato): in modalità
    cifrata NON viene registrato e gli stessi PRAGMA sono applicati nel connector.
    Mai la chiave nell'URL. Timeout passato dentro sqlcipher3.connect
    (connect_args viene ignorato con async_creator).
    """
    import aiosqlite

    path = db_path or settings.DB_PATH
    key = db_key if db_key is not None else settings.DB_KEY
    url = f"sqlite+aiosqlite:///{path}"
    resolved_echo = (settings.LOG_LEVEL == "DEBUG") if echo is None else echo

    if not key:
        eng = create_async_engine(
            url,
            echo=resolved_echo,
            connect_args={"timeout": 30},
            pool_pre_ping=True
        )
        event.listen(eng.sync_engine, "connect", _set_sqlite_pragmas)
        return eng

    def _connector():
        import sqlcipher3
        raw = sqlcipher3.connect(path, timeout=30.0, check_same_thread=False, isolation_level=None)
        try:
            raw.execute(f"PRAGMA key='{_escape_sqlite_literal(key)}'")
            # Fail-fast: chiave errata -> errore immediato, mai oltre.
            raw.execute("SELECT count(*) FROM sqlite_master").fetchone()
            raw.execute("PRAGMA foreign_keys=ON;")
            raw.execute("PRAGMA busy_timeout=30000;")
            raw.execute("PRAGMA synchronous=NORMAL;")
        except Exception:
            raw.close()
            raise
        # Fresh cifrati a 0600 (main + sidecar quando compaiono), best-effort:
        # il connector gira a ogni nuova connessione del pool.
        for candidate in (path, path + "-wal", path + "-shm"):
            try:
                if os.path.exists(candidate):
                    os.chmod(candidate, 0o600)
            except OSError:
                pass
        return raw

    def _async_creator():
        conn = aiosqlite.Connection(_connector, iter_chunk_size=64)
        conn.daemon = True
        return conn

    return create_async_engine(
        url,
        async_creator=_async_creator,
        echo=resolved_echo,
        pool_pre_ping=True
    )


# Configurazione ottimizzata engine con timeout esteso e concurrency WAL per SQLite
engine = create_db_engine()

async_session_maker = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

Base = declarative_base()


async def _ensure_holdings_unique_constraint(conn) -> None:
    """
    Migrazione idempotente del vincolo UNIQUE(user_id, stock_id) su holdings.

    - Se un indice UNIQUE copre già (user_id, stock_id) (DB freschi creati da
      create_all / re-run) non fa nulla.
    - Altrimenti fonda gli eventuali duplicati storici per (user_id, stock_id):
      somma delle quantità, prezzo medio ponderato, riga più vecchia conservata
      e le altre eliminate; notes/purchase_date della riga conservata sono
      preservati, con fallback al primo valore non nullo dei duplicati. Poi
      crea l'indice unico.

    Dedup e creazione indice girano in un SAVEPOINT: se qualcosa fallisce a
    metà, nessun merge parziale resta committato (all-or-nothing reale) e
    l'eccezione viene propagata al chiamante. Al prossimo init_db la migrazione
    è ri-eseguibile perché non è stato persistito nulla.
    """
    idx_rows = (await conn.execute(text("PRAGMA index_list(holdings)"))).fetchall()
    for idx_row in idx_rows:
        # idx_row: (seq, name, unique, origin, partial)
        if not idx_row[2]:
            continue
        cols = {
            info_row[2]
            for info_row in (await conn.execute(text(f"PRAGMA index_info('{idx_row[1]}')"))).fetchall()
        }
        if cols == {"user_id", "stock_id"}:
            return

    async with conn.begin_nested():
        dup_groups = (await conn.execute(text(
            "SELECT user_id, stock_id FROM holdings "
            "WHERE user_id IS NOT NULL "
            "GROUP BY user_id, stock_id HAVING COUNT(*) > 1"
        ))).fetchall()

        for user_id, stock_id in dup_groups:
            rows = (await conn.execute(text(
                "SELECT id, quantity, avg_purchase_price, notes, purchase_date FROM holdings "
                "WHERE user_id = :uid AND stock_id = :sid ORDER BY id"
            ), {"uid": user_id, "sid": stock_id})).fetchall()
            if len(rows) < 2:
                continue

            keep_id = rows[0][0]
            total_qty = sum(float(r[1] or 0.0) for r in rows)
            total_cost = sum(float(r[1] or 0.0) * float(r[2] or 0.0) for r in rows)
            # Se la somma quantità non è positiva (dati incoerenti legacy) si
            # conserva il prezzo medio della riga più vecchia.
            merged_avg = (total_cost / total_qty) if total_qty > 0 else float(rows[0][2] or 0.0)
            # Campi opzionali: vince il valore della riga conservata, altrimenti
            # il primo non nullo tra i duplicati assorbiti.
            keep_notes = rows[0][3] or next((r[3] for r in rows[1:] if r[3]), None)
            keep_purchase_date = rows[0][4] or next((r[4] for r in rows[1:] if r[4]), None)

            await conn.execute(text(
                "UPDATE holdings SET quantity = :qty, avg_purchase_price = :avg, "
                "notes = :notes, purchase_date = :pdate WHERE id = :id"
            ), {
                "qty": total_qty,
                "avg": round(merged_avg, 4),
                "notes": keep_notes,
                "pdate": keep_purchase_date,
                "id": keep_id,
            })
            for other in rows[1:]:
                await conn.execute(text("DELETE FROM holdings WHERE id = :id"), {"id": other[0]})

            logger.warning(
                f"Migrazione holdings: fusi {len(rows) - 1} duplicati per "
                f"user_id={user_id}, stock_id={stock_id} (riga conservata id={keep_id})"
            )

        await conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_holdings_user_stock ON holdings(user_id, stock_id)"
        ))


async def _ensure_user_settings_unique_constraint(conn) -> None:
    """
    Migrazione idempotente del vincolo UNIQUE(user_id) su user_settings.

    - Se un indice UNIQUE copre user_id (DB freschi / re-run) non fa nulla.
    - Altrimenti conserva la riga più vecchia per user_id ed elimina i
      duplicati, poi crea l'indice unico.

    Dedup e indice girano in un SAVEPOINT (all-or-nothing, errore propagato).
    Caveat SQLite: NULL è distinto da NULL, quindi il vincolo non copre righe
    legacy con user_id NULL; il backfill `user_settings.user_id -> 1` di
    init_db gira prima di questa migrazione, quindi il gap residuo riguarda
    solo DB in cui quel backfill non è applicabile.
    """
    idx_rows = (await conn.execute(text("PRAGMA index_list(user_settings)"))).fetchall()
    for idx_row in idx_rows:
        if not idx_row[2]:
            continue
        cols = {
            info_row[2]
            for info_row in (await conn.execute(text(f"PRAGMA index_info('{idx_row[1]}')"))).fetchall()
        }
        if cols == {"user_id"}:
            return

    async with conn.begin_nested():
        dup_users = (await conn.execute(text(
            "SELECT user_id FROM user_settings "
            "WHERE user_id IS NOT NULL "
            "GROUP BY user_id HAVING COUNT(*) > 1"
        ))).fetchall()

        for (user_id,) in dup_users:
            ids = [
                row[0] for row in (await conn.execute(text(
                    "SELECT id FROM user_settings WHERE user_id = :uid ORDER BY id"
                ), {"uid": user_id})).fetchall()
            ]
            for other_id in ids[1:]:
                await conn.execute(text("DELETE FROM user_settings WHERE id = :id"), {"id": other_id})
            logger.warning(
                f"Migrazione user_settings: rimossi {len(ids) - 1} duplicati per "
                f"user_id={user_id} (riga conservata id={ids[0]})"
            )

        await conn.execute(text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_user_settings_user ON user_settings(user_id)"
        ))

async def init_db() -> None:
    """
    Crea tutte le tabelle nel database e abilita modalità WAL ad alta concorrenza.
    Come PRIMO passo garantisce lo stato di cifratura (migrazione o blocco startup).
    """
    await ensure_db_encryption()
    if settings.DB_KEY:
        # Pre-flight isolato: se il file è cifrato e la chiave è errata, fallisce
        # qui con messaggio esplicito invece che in una migrazione ambigua.
        try:
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        except Exception as e:
            raise DbEncryptionError(
                "Impossibile aprire il database cifrato: DB_KEY errata o file "
                "danneggiato? Niente è stato sovrascritto: verifica DB_KEY e riavvia."
            ) from e
    async with engine.begin() as conn:
        # Ottimizzazioni performance SQLite per NAS & SSD
        await conn.execute(text("PRAGMA journal_mode=WAL;"))
        await conn.execute(text("PRAGMA synchronous=NORMAL;"))
        await conn.execute(text("PRAGMA busy_timeout=30000;"))
        await conn.execute(text("PRAGMA foreign_keys=ON;"))
        
        await conn.run_sync(Base.metadata.create_all)
        
        # Migrazione sicura per colonna is_admin
        try:
            await conn.execute(text("ALTER TABLE users ADD COLUMN is_admin BOOLEAN DEFAULT 0"))
        except Exception:
            pass

        # Migrazioni sicure per colonne advices
        for col_sql in [
            "ALTER TABLE advices ADD COLUMN market VARCHAR DEFAULT 'ALL'",
            "ALTER TABLE advices ADD COLUMN title VARCHAR",
            "ALTER TABLE advices ADD COLUMN overview TEXT",
            "ALTER TABLE advices ADD COLUMN stocks_json TEXT",
            "ALTER TABLE advices ADD COLUMN risks TEXT"
        ]:
            try:
                await conn.execute(text(col_sql))
            except Exception:
                pass

        # Migrazioni sicure per colonne watchlist alerts
        for wl_col in [
            "ALTER TABLE watchlist_items ADD COLUMN alert_above FLOAT",
            "ALTER TABLE watchlist_items ADD COLUMN alert_below FLOAT",
            "ALTER TABLE watchlist_items ADD COLUMN alert_triggered BOOLEAN DEFAULT 0"
        ]:
            try:
                await conn.execute(text(wl_col))
            except Exception:
                pass

        # Migrazione sicura per multi-utente (user_id per isolamento portfolio e watchlist)
        for user_col in [
            "ALTER TABLE holdings ADD COLUMN user_id INTEGER REFERENCES users(id)",
            "ALTER TABLE transactions ADD COLUMN user_id INTEGER REFERENCES users(id)",
            "ALTER TABLE watchlist_items ADD COLUMN user_id INTEGER REFERENCES users(id)",
            "ALTER TABLE user_settings ADD COLUMN user_id INTEGER REFERENCES users(id)",
            "ALTER TABLE alert_rules ADD COLUMN user_id INTEGER REFERENCES users(id)"
        ]:
            try:
                await conn.execute(text(user_col))
            except Exception:
                pass

        # Migrazione Advice.user_id: ignora SOLO l'errore di colonna già esistente,
        # qualunque altro errore viene propagato (DB non corrotto silenziosamente).
        try:
            await conn.execute(text("ALTER TABLE advices ADD COLUMN user_id INTEGER REFERENCES users(id)"))
        except Exception as e:
            if "duplicate column name" not in str(e).lower():
                logger.error(f"Migrazione advices.user_id fallita: {e}")
                raise

        # Migrazione TargetAllocation.user_id (rebalancer per-utente):
        # stessa regola, ignora SOLO la colonna già esistente.
        try:
            await conn.execute(text("ALTER TABLE target_allocations ADD COLUMN user_id INTEGER REFERENCES users(id)"))
        except Exception as e:
            if "duplicate column name" not in str(e).lower():
                logger.error(f"Migrazione target_allocations.user_id fallita: {e}")
                raise

        # Backfill advice storici orfani all'admin configurato (fallback: id minimo)
        try:
            admin_id = (await conn.execute(
                text("SELECT id FROM users WHERE username = :username ORDER BY id LIMIT 1"),
                {"username": settings.ADMIN_USERNAME}
            )).scalar()
            if admin_id is None:
                admin_id = (await conn.execute(text("SELECT MIN(id) FROM users"))).scalar()
            if admin_id is not None:
                await conn.execute(
                    text("UPDATE advices SET user_id = :admin_id WHERE user_id IS NULL"),
                    {"admin_id": admin_id}
                )
        except Exception as e:
            logger.warning(f"Backfill advices.user_id non riuscito: {e}")

        # Assegna eventuali dati storici orfani (senza user_id) all'admin id=1
        try:
            await conn.execute(text("UPDATE holdings SET user_id = 1 WHERE user_id IS NULL"))
            await conn.execute(text("UPDATE transactions SET user_id = 1 WHERE user_id IS NULL"))
            await conn.execute(text("UPDATE watchlist_items SET user_id = 1 WHERE user_id IS NULL"))
            await conn.execute(text("UPDATE user_settings SET user_id = 1 WHERE user_id IS NULL"))
            await conn.execute(text("UPDATE alert_rules SET user_id = 1 WHERE user_id IS NULL"))
        except Exception:
            pass

        # Backfill target allocation storici all'admin configurato (fallback: id minimo)
        try:
            admin_id = (await conn.execute(
                text("SELECT id FROM users WHERE username = :username ORDER BY id LIMIT 1"),
                {"username": settings.ADMIN_USERNAME}
            )).scalar()
            if admin_id is None:
                admin_id = (await conn.execute(text("SELECT MIN(id) FROM users"))).scalar()
            if admin_id is not None:
                await conn.execute(
                    text("UPDATE target_allocations SET user_id = :admin_id WHERE user_id IS NULL"),
                    {"admin_id": admin_id}
                )
        except Exception as e:
            logger.warning(f"Backfill target_allocations.user_id non riuscito: {e}")

        # UNIQUE(user_id, stock_id) su holdings e UNIQUE(user_id) su user_settings:
        # dedup idempotente dei duplicati storici + indice unico (i modelli li
        # dichiarano per i DB freschi). Un errore qui non blocca lo startup, ma
        # il log dichiara esplicitamente che il vincolo DB NON è garantito.
        try:
            await _ensure_holdings_unique_constraint(conn)
        except Exception as e:
            logger.error(
                f"Migrazione UNIQUE holdings(user_id, stock_id) fallita: {e}. "
                "Vincolo DB non garantito (le scritture restano serializzate dal lock applicativo)."
            )

        try:
            await _ensure_user_settings_unique_constraint(conn)
        except Exception as e:
            logger.error(
                f"Migrazione UNIQUE user_settings(user_id) fallita: {e}. "
                "Vincolo DB non garantito."
            )

        # Indici ad alte prestazioni per query multi-utente e serie storiche.
        # UNICA definizione dell'indice composito price_history(stock_id, timestamp):
        # definirlo qui (invece che nel model) copre anche i DB preesistenti.
        for idx_sql in [
            "CREATE INDEX IF NOT EXISTS ix_holdings_user_stock ON holdings(user_id, stock_id)",
            "CREATE INDEX IF NOT EXISTS ix_transactions_user_txdate ON transactions(user_id, transaction_date)",
            "CREATE INDEX IF NOT EXISTS ix_watchlist_user_stock ON watchlist_items(user_id, stock_id)",
            "CREATE INDEX IF NOT EXISTS ix_alert_rules_user ON alert_rules(user_id)",
            "CREATE INDEX IF NOT EXISTS ix_alert_rules_is_active ON alert_rules(is_active)",
            "CREATE INDEX IF NOT EXISTS idx_stock_id_timestamp ON price_history(stock_id, timestamp)",
            "CREATE INDEX IF NOT EXISTS ix_advices_timestamp ON advices(timestamp)",
            "CREATE INDEX IF NOT EXISTS ix_advices_user_id ON advices(user_id)",
            "CREATE INDEX IF NOT EXISTS ix_sentiments_stock_ts ON sentiments(stock_id, timestamp)",
            "CREATE INDEX IF NOT EXISTS ix_target_allocations_user ON target_allocations(user_id)",
            "DROP INDEX IF EXISTS ix_price_history_stock_ts"
        ]:
            try:
                await conn.execute(text(idx_sql))
            except Exception:
                pass



from contextlib import asynccontextmanager

@asynccontextmanager
async def session_scope():
    """
    Context manager asincrono per sessioni DB isolate (es. per scheduler, telegram bot e background tasks).
    """
    async with async_session_maker() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()

async def get_db():
    """
    Dependency FastAPI per sessione DB asincrona sicura
    """
    async with async_session_maker() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()

