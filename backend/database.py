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
    cursor.execute("PRAGMA busy_timeout=20000;")
    cursor.execute("PRAGMA synchronous=NORMAL;")
    cursor.close()

event.listen(engine.sync_engine, "connect", _set_sqlite_pragmas)

async_session_maker = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

Base = declarative_base()

async def init_db() -> None:
    """
    Crea tutte le tabelle nel database e abilita modalità WAL ad alta concorrenza.
    """
    async with engine.begin() as conn:
        # Ottimizzazioni performance SQLite per NAS & SSD
        await conn.execute(text("PRAGMA journal_mode=WAL;"))
        await conn.execute(text("PRAGMA synchronous=NORMAL;"))
        await conn.execute(text("PRAGMA busy_timeout=20000;"))
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

