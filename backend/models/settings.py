from sqlalchemy import Column, Integer, Float, String, Boolean, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from backend.database import Base

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
