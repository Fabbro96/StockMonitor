import base64
import hashlib
import logging
from sqlalchemy import Column, Integer, Float, String, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from backend.database import Base

logger = logging.getLogger(__name__)


def _gemini_fernet():
    """Fernet derivata da SECRET_KEY (mai custom-crypto: solo Fernet).

    Import lazy di settings per evitare cicli a import-time
    (models.settings è importato da database a sua volta).
    """
    from cryptography.fernet import Fernet
    from backend.config import settings as app_settings

    secret = (app_settings.SECRET_KEY or "").encode("utf-8")
    digest = hashlib.sha256(secret).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def encrypt_gemini_key(plain: str) -> str:
    """Cifra la chiave Gemini in forma opaca (stringa utf-8)."""
    f = _gemini_fernet()
    return f.encrypt(plain.encode("utf-8")).decode("utf-8")


def decrypt_gemini_key(enc: str | None) -> str | None:
    """Decifra la chiave o ritorna None (chiave ruotata/SECRET_KEY cambiata).

    Mai loggare il valore: solo warning senza contenuto.
    """
    if not enc:
        return None
    try:
        f = _gemini_fernet()
        return f.decrypt(enc.encode("utf-8")).decode("utf-8")
    except Exception:
        logger.warning("Impossibile decifrare la chiave Gemini salvata (SECRET_KEY ruotata?).")
        return None


def mask_gemini_key(plain: str | None) -> str | None:
    """Maschera la chiave per la GET (solo `••••abcd`, mai intera)."""
    if not plain:
        return None
    s = plain.strip()
    if not s:
        return None
    tail = s[-4:] if len(s) >= 4 else "••••"
    return f"••••{tail}"

class UserSettings(Base):
    __tablename__ = "user_settings"
    # Una sola riga di impostazioni per utente: garanzia DB della race
    # get-or-create di /api/settings (per i DB preesistenti l'indice equivalente
    # è creato da init_db dopo la migrazione di dedup).
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_user_settings_user"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    strategy = Column(String, default='mixed') # 'long_term', 'short_term', 'mixed'
    markets = Column(String, default='IT,US,EU')
    advice_times = Column(String, default='09:00,18:00')
    advice_frequency = Column(Integer, default=2)
    total_budget = Column(Float, default=10000.0)
    # Chiave Gemini per-utente cifrata con Fernet (derivata da SECRET_KEY).
    # Precedenza su env GEMINI_API_KEY; mai esposta intera in GET (solo masked).
    gemini_api_key_encrypted = Column(String, nullable=True, default=None)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

class AlertRule(Base):
    __tablename__ = "alert_rules"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    stock_id = Column(Integer, ForeignKey("stocks.id"), nullable=False)
    threshold_percent = Column(Float, default=5.0)
    direction = Column(String, default='BOTH') # 'UP', 'DOWN', 'BOTH'
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    # Relationships
    stock = relationship("Stock", back_populates="alerts")
