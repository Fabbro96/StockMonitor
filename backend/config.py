import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    """
    Impostazioni dell'applicazione caricate da variabili d'ambiente o dal file .env
    """
    TELEGRAM_BOT_TOKEN: str | None = None
    TELEGRAM_CHAT_ID: str | None = None
    TELEGRAM_BOT_ENABLED: bool = True
    GEMINI_API_KEY: str | None = None
    GEMINI_MODEL: str = "gemini-3.7-flash"
    REDDIT_CLIENT_ID: str | None = None
    REDDIT_CLIENT_SECRET: str | None = None
    DB_PATH: str = "data/stock_monitor.db"
    ALERT_CHECK_INTERVAL_MINUTES: int = 15
    LOG_LEVEL: str = "INFO"

    # Retention dati storici (evita crescita illimitata del DB sul NAS).
    # 400gg copre le finestre analytics: 365gg performance, 180gg risk.
    PRICE_HISTORY_RETENTION_DAYS: int = 400
    SENTIMENT_RETENTION_DAYS: int = 30
    CLEANUP_BATCH_SIZE: int = 500

    # Analytics & Risk Metrics
    RISK_FREE_RATE: float = 0.02  # Tasso risk-free annuo per Sharpe Ratio

    # Sicurezza & Autenticazione
    SECRET_KEY: str = "stock-monitor-super-secret-key-change-in-env-2026"
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str = "admin123"
    ACCESS_TOKEN_EXPIRE_DAYS: int = 7

    model_config = {
        "env_file": ".env"
    }

settings = Settings()

