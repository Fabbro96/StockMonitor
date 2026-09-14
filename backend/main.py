import os
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Request
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse, RedirectResponse
from sqlalchemy.future import select
import uvicorn

from backend.config import settings
from backend.database import init_db, async_session_maker, DbEncryptionError
from backend.services.scheduler import init_scheduler, shutdown_scheduler
from backend.models.settings import UserSettings
from backend.models.user import User
from backend.services.auth import get_current_user, hash_password_async, shutdown_bcrypt_executor
from backend.services.telegram_bot import InteractiveTelegramBot
from backend.routers import (
    stocks_router,
    portfolio_router,
    dashboard_router,
    advice_router,
    settings_router,
    auth_router,
    watchlist_router
)

# Configura il logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# Istanza singleton del bot interattivo (gestita dal lifespan)
telegram_bot = InteractiveTelegramBot()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Starting up Stock Monitor...")
    
    # Ensure data directory exists (deriva dalla path del DB per robustezza)
    os.makedirs("data", exist_ok=True)
    db_dir = os.path.dirname(os.path.abspath(settings.DB_PATH))
    if db_dir:
        os.makedirs(db_dir, exist_ok=True)
    
    # Initialize DB (la cifratura at-rest è garantita come primo passo di init_db)
    try:
        await init_db()
    except DbEncryptionError as e:
        logger.critical(
            "FATALE cifratura database: %s (niente è stato sovrascritto; "
            "verifica DB_KEY — mancante o errata — e riavvia). Startup interrotto.",
            e,
        )
        raise
    
    # Create default settings and initial admin user if none exist
    async with async_session_maker() as session:
        # UserSettings
        result = await session.execute(select(UserSettings).limit(1))
        if not result.scalars().first():
            logger.info("Creating default UserSettings")
            session.add(UserSettings())
            await session.commit()
            
        # Admin User
        user_result = await session.execute(select(User).where(User.username == settings.ADMIN_USERNAME))
        admin = user_result.scalars().first()
        if not admin:
            admin_user = settings.ADMIN_USERNAME
            admin_pass = settings.ADMIN_PASSWORD
            logger.info(f"Creating default admin user: '{admin_user}'")
            hashed = await hash_password_async(admin_pass)
            session.add(User(username=admin_user, hashed_password=hashed, is_admin=True))
            await session.commit()
            logger.info(f"Admin user '{admin_user}' created successfully.")
        elif not admin.is_admin:
            admin.is_admin = True
            await session.commit()
            logger.info(f"Admin status updated for '{admin.username}'")

    
    # Initialize Scheduler
    init_scheduler()

    # Avvia bot Telegram interattivo bidirezionale (se configurato)
    await telegram_bot.start()
    
    yield
    
    # Shutdown
    logger.info("Shutting down Stock Monitor...")
    await telegram_bot.stop()
    # Ordine M8: shutdown_scheduler blocca prima il nuovo lavoro yfinance,
    # ferma lo scheduler e attende (best-effort) i job in corso; SOLO DOPO
    # viene chiuso il client HTTP condiviso.
    await shutdown_scheduler()
    shutdown_bcrypt_executor()

    # Chiusura best-effort del client HTTP condiviso (esposto dal layer sentiment)
    try:
        from backend.services.sentiment import close_shared_http_client
        await close_shared_http_client()
    except Exception as e:
        logger.debug(f"Chiusura client HTTP condiviso non riuscita: {e}")

app = FastAPI(title="Stock Monitor", version="4.0.0", lifespan=lifespan)

# CORS middleware (secure origin regex for local, docker and lan access with credentials)
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|0\.0\.0\.0)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# GZip compression middleware (riduce i payload JSON pesanti fino al 75-80%).
# compresslevel=5 (default 9): con 1 worker sul NAS il livello 9 brucia CPU su
# asset web multi-MB per un guadagno di size marginale; 5 è il compromesso.
app.add_middleware(GZipMiddleware, minimum_size=1000, compresslevel=5)

# La build Flutter web è servita a root `/` con hash routing (nessun fallback SPA).
# TUTTO l'output web è `no-cache, must-revalidate`: gli asset Flutter non sono
# content-hashed e il service worker è uno stub deprecato. ETag/Last-Modified
# restano disponibili per la rivalidazione condizionale. Gli header di API e
# /health non vengono toccati.
_WEB_EXEMPT_PREFIXES = ("/api", "/health", "/docs", "/redoc", "/openapi.json")

@app.middleware("http")
async def add_cache_headers(request, call_next):
    response = await call_next(request)
    if response.status_code < 400 and not request.url.path.startswith(_WEB_EXEMPT_PREFIXES):
        response.headers["Cache-Control"] = "no-cache, must-revalidate"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    return response

@app.get("/health", tags=["system"])
async def health():
    """
    Health check pubblico (non protetto) per Docker/Kubernetes.
    Verifica anche la raggiungibilità del database.
    """
    db_ok = True
    try:
        async with async_session_maker() as session:
            from sqlalchemy import text
            await session.execute(text("SELECT 1"))
    except Exception as e:
        logger.error(f"Health check DB fallito: {e}")
        db_ok = False
    return {
        "status": "ok" if db_ok else "degraded",
        "database": "ok" if db_ok else "error",
        "telegram_bot_active": telegram_bot.application is not None,
        "version": app.version,
    }

# Public Auth router
app.include_router(auth_router)

# Protected API routers (require valid login)
app.include_router(stocks_router, dependencies=[Depends(get_current_user)])
app.include_router(portfolio_router, dependencies=[Depends(get_current_user)])
app.include_router(dashboard_router, dependencies=[Depends(get_current_user)])
app.include_router(advice_router, dependencies=[Depends(get_current_user)])
app.include_router(settings_router, dependencies=[Depends(get_current_user)])
app.include_router(watchlist_router, dependencies=[Depends(get_current_user)])

# ---------------------------------------------------------------------------
# Serving della build Flutter web (P4)
# ---------------------------------------------------------------------------
def _resolve_web_dir() -> str | None:
    """Risolve la web dir: settings.WEB_DIR, poi fallback dev <repo>/app/build/web."""
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    candidates = [settings.WEB_DIR, os.path.join(repo_root, "app", "build", "web")]
    for candidate in candidates:
        if candidate and os.path.isdir(candidate):
            return os.path.abspath(candidate)
    return None


# Redirect legacy (302) dal vecchio frontend statico alle route hash della app.
# F5: la query string originale viene propagata nel target (nel fragment per le
# route hash), così i prefill del vecchio frontend (?add=, ?redirect=, ...) non
# vanno persi.
def _legacy_redirect(target: str, request: Request) -> RedirectResponse:
    if request.url.query:
        separator = "&" if "?" in target else "?"
        target = f"{target}{separator}{request.url.query}"
    return RedirectResponse(url=target, status_code=302)


@app.get("/static", include_in_schema=False)
async def legacy_static_root(request: Request):
    return _legacy_redirect("/", request)

@app.get("/static/index.html", include_in_schema=False)
async def legacy_static_index(request: Request):
    return _legacy_redirect("/", request)

@app.get("/static/login.html", include_in_schema=False)
async def legacy_static_login(request: Request):
    return _legacy_redirect("/#/login", request)

@app.get("/static/watchlist.html", include_in_schema=False)
async def legacy_static_watchlist(request: Request):
    return _legacy_redirect("/#/watchlist", request)

@app.get("/static/portfolio.html", include_in_schema=False)
async def legacy_static_portfolio(request: Request):
    return _legacy_redirect("/#/portfolio", request)

@app.get("/static/advice.html", include_in_schema=False)
async def legacy_static_advice(request: Request):
    return _legacy_redirect("/#/advice", request)

@app.get("/static/settings.html", include_in_schema=False)
async def legacy_static_settings(request: Request):
    return _legacy_redirect("/#/settings", request)

web_dir = _resolve_web_dir()
if web_dir:
    logger.info(f"Serving Flutter web build from {web_dir}")
    # Mount a root DOPO router e /health: l'ordine di registrazione garantisce
    # che /api/* e /health abbiano precedenza sul mount.
    app.mount("/", StaticFiles(directory=web_dir, html=True), name="web")
else:
    logger.warning(
        f"Build web non trovata (WEB_DIR={settings.WEB_DIR!r} e nessun fallback "
        "app/build/web). GET / risponderà 503."
    )

    @app.get("/", include_in_schema=False)
    async def root_no_web():
        return JSONResponse(
            status_code=503,
            content={"detail": "Build web non trovata. Esegui 'flutter build web' o imposta WEB_DIR."},
        )

if __name__ == "__main__":
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
