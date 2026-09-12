import os
import logging
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from sqlalchemy import text, event
from backend.config import settings

logger = logging.getLogger(__name__)

DATABASE_URL = f"sqlite+aiosqlite:///{settings.DB_PATH}"

# Configurazione ottimizzata engine con timeout esteso e concurrency WAL per SQLite
engine = create_async_engine(
    DATABASE_URL,
    echo=(settings.LOG_LEVEL == "DEBUG"),
    connect_args={"timeout": 30},
    pool_pre_ping=True
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

event.listen(engine.sync_engine, "connect", _set_sqlite_pragmas)

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
    """
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

