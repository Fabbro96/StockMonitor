import asyncio
import functools
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from backend.database import async_session_maker
from backend.models.advice import Advice
from backend.models.stock import PriceHistory
from backend.models.sentiment import Sentiment
from backend.services.market_data import (
    MarketDataService,
    BATCH_FETCH_TIMEOUT_BACKGROUND,
    request_yf_shutdown,
    shutdown_yf_executor,
)
from backend.services.sentiment import SentimentService
from backend.services.advisor import AdvisorService
from backend.services.alerting import AlertingService
from backend.config import settings

logger = logging.getLogger(__name__)

# Timezone esplicita: senza di essa AsyncIOScheduler usa quella di sistema,
# rendendo imprevedibili gli orari cron tra host/NAS con TZ diverse.
SCHEDULER_TIMEZONE = "Europe/Rome"
SHUTDOWN_JOBS_WAIT_SECONDS = 5.0

scheduler = AsyncIOScheduler(timezone=SCHEDULER_TIMEZONE)

# Task dei job correntemente in esecuzione: permettono allo shutdown di
# attendere (best-effort, con timeout) i job in corso prima di chiudere le
# risorse condivise (executor yfinance, client HTTP).
_running_job_tasks: set[asyncio.Task] = set()


def _track_running_job(func):
    """Registra il task del job in esecuzione per lo shutdown best-effort."""
    @functools.wraps(func)
    async def wrapper(*args, **kwargs):
        task = asyncio.current_task()
        if task is not None:
            _running_job_tasks.add(task)
        try:
            return await func(*args, **kwargs)
        finally:
            _running_job_tasks.discard(task)
    return wrapper


@_track_running_job
async def collect_prices_job():
    # Mantiene la cadenza oraria ma evita fetch inutili a mercati chiusi (NAS 24/7)
    if not MarketDataService.are_any_markets_open():
        logger.info("Borse chiuse: aggiornamento prezzi periodico saltato.")
        return

    logger.info("Avvio job periodico: aggiornamento prezzi di mercato")
    try:
        async with async_session_maker() as session:
            saved = await MarketDataService.fetch_all_prices(
                session, batch_timeout=BATCH_FETCH_TIMEOUT_BACKGROUND
            )
            logger.info(f"Aggiornati con successo i prezzi per {len(saved)} titoli.")
    except Exception as e:
        logger.error(f"Errore durante collect_prices_job: {e}")

@_track_running_job
async def check_alerts_job():
    if not MarketDataService.are_any_markets_open():
        logger.debug("Borse chiuse: controllo alert saltato.")
        return
    try:
        async with async_session_maker() as session:
            alert_service = AlertingService()
            await alert_service.check_alerts(session)
    except Exception as e:
        logger.error(f"Errore durante check_alerts_job: {e}")

@_track_running_job
async def analyze_sentiment_job():
    logger.info("Avvio job periodico: raccolta notizie e sentiment multi-fonte")
    try:
        async with async_session_maker() as session:
            sentiment_service = SentimentService()
            await sentiment_service.analyze_all_stocks(session)
            logger.info("Aggiornamento notizie e sentiment completato.")
    except Exception as e:
        logger.error(f"Errore durante analyze_sentiment_job: {e}")

@_track_running_job
async def generate_advice_job():
    if not MarketDataService.are_any_markets_open():
        logger.info("Borse chiuse: job periodico generazione consigli saltato.")
        return

    logger.info("Avvio job periodico: generazione 5 consigli AI con Gemini 3.7 Flash")
    try:
        async with async_session_maker() as session:
            advisor_service = AdvisorService()
            advices = await advisor_service.generate_advice(session)
            logger.info(f"Generati con successo {len(advices)} nuovi consigli finanziari.")
    except Exception as e:
        logger.error(f"Errore durante generate_advice_job: {e}")


async def _delete_older_than_batch(session, model, cutoff, batch_size: int) -> int:
    """
    Cancella a batch (LIMIT + commit per batch) le righe di `model` più vecchie di `cutoff`.
    Ritorna il numero totale di righe eliminate.
    """
    total = 0
    while True:
        ids_subq = select(model.id).where(model.timestamp < cutoff).limit(batch_size)
        result = await session.execute(delete(model).where(model.id.in_(ids_subq)))
        await session.commit()
        deleted = result.rowcount if result.rowcount and result.rowcount > 0 else 0
        total += deleted
        if deleted < batch_size:
            break
    return total


@_track_running_job
async def cleanup_old_data_job():
    logger.info("Avvio job pulizia dati storici (advice, price_history, sentiments)")
    try:
        async with async_session_maker() as session:
            now = datetime.now(timezone.utc)

            advice_cutoff = now - timedelta(days=7)
            advice_result = await session.execute(delete(Advice).where(Advice.timestamp < advice_cutoff))
            await session.commit()
            advices_deleted = advice_result.rowcount if advice_result.rowcount and advice_result.rowcount > 0 else 0

            prices_deleted = await _delete_older_than_batch(
                session,
                PriceHistory,
                now - timedelta(days=settings.PRICE_HISTORY_RETENTION_DAYS),
                settings.CLEANUP_BATCH_SIZE
            )

            sentiments_deleted = await _delete_older_than_batch(
                session,
                Sentiment,
                now - timedelta(days=settings.SENTIMENT_RETENTION_DAYS),
                settings.CLEANUP_BATCH_SIZE
            )

            logger.info(
                f"Pulizia completata: {advices_deleted} advice (>7gg), "
                f"{prices_deleted} price_history (>{settings.PRICE_HISTORY_RETENTION_DAYS}gg), "
                f"{sentiments_deleted} sentiments (>{settings.SENTIMENT_RETENTION_DAYS}gg) eliminati."
            )
    except Exception as e:
        logger.error(f"Errore durante cleanup_old_data_job: {e}")


def init_scheduler():
    # Esegui ogni ora durante l'orario di borsa
    scheduler.add_job(
        collect_prices_job,
        'cron',
        minute=0,
        id='collect_prices_job',
        replace_existing=True,
        max_instances=1,
        coalesce=True,
        misfire_grace_time=300
    )
    # Controllo alert
    scheduler.add_job(
        check_alerts_job,
        'interval',
        minutes=settings.ALERT_CHECK_INTERVAL_MINUTES,
        id='check_alerts_job',
        replace_existing=True,
        max_instances=1,
        coalesce=True
    )
    # Raccogli news due volte al giorno (12:00 e 20:00)
    scheduler.add_job(
        analyze_sentiment_job,
        'cron',
        hour='12,20',
        minute=0,
        id='analyze_sentiment_job',
        replace_existing=True,
        max_instances=1,
        coalesce=True
    )
    # Generazione consigli 2 volte al giorno (09:00 e 18:00)
    scheduler.add_job(
        generate_advice_job,
        'cron',
        hour='9,18',
        minute=0,
        id='generate_advice_job',
        replace_existing=True,
        max_instances=1,
        coalesce=True
    )
    # Pulizia automatica analisi vecchie (> 7 giorni) ogni notte alle 03:00
    scheduler.add_job(
        cleanup_old_data_job,
        'cron',
        hour=3,
        minute=0,
        id='cleanup_old_data_job',
        replace_existing=True,
        max_instances=1,
        coalesce=True
    )
    
    scheduler.start()

    logger.info("Scheduler APScheduler avviato con successo.")


async def shutdown_scheduler():
    """Shutdown ordinato: prima blocca il nuovo lavoro yfinance, poi smonta.

    L'ordine è essenziale (M8): il flag viene impostato PRIMA di fermare lo
    scheduler e chiudere l'executor, così un job ancora in corsa che chiama
    run_blocking_yf riceve MarketDataShutdownError invece di ricreare un pool
    di thread già chiuso. I job in corso vengono attesi best-effort con timeout.
    """
    # 1. Nessun nuovo lavoro yfinance da qui in avanti.
    request_yf_shutdown()

    # 2. Ferma lo scheduler (wait=False: APScheduler cancella i task coroutine
    #    pendenti; i thread yfinance già avviati terminano entro l'HTTP timeout).
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler terminato correttamente.")

    # 3. Attesa best-effort dei job in corso (max SHUTDOWN_JOBS_WAIT_SECONDS):
    #    evita di chiudere il client HTTP condiviso sotto i piedi a un job.
    pending = [t for t in list(_running_job_tasks) if not t.done()]
    if pending:
        try:
            await asyncio.wait(pending, timeout=SHUTDOWN_JOBS_WAIT_SECONDS)
        except Exception as e:
            logger.debug(f"Attesa job in corso interrotta: {e}")

    # 4. Cleanup best-effort del pool dedicato alle chiamate yfinance.
    shutdown_yf_executor()
