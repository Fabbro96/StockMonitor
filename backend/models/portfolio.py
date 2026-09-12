from sqlalchemy import Column, Integer, Float, String, Date, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from backend.database import Base

class Holding(Base):
    __tablename__ = "holdings"
    # Una sola posizione per (utente, titolo): l'upsert applicativo è protetto
    # dal lock per-utente, questo vincolo è la garanzia a livello DB (anche per
    # DB preesistenti, dove l'indice equivalente è creato da init_db dopo la
    # migrazione di dedup).
    __table_args__ = (
        UniqueConstraint("user_id", "stock_id", name="uq_holdings_user_stock"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    stock_id = Column(Integer, ForeignKey("stocks.id"), nullable=False)
    quantity = Column(Float, nullable=False)  # Float per supportare frazioni (ETF, rebalancer)
    avg_purchase_price = Column(Float, nullable=False)
    purchase_date = Column(Date, nullable=True)
    notes = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    # Relationships
    stock = relationship("Stock", back_populates="holdings")


class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    stock_id = Column(Integer, ForeignKey("stocks.id"), nullable=False)
    type = Column(String, nullable=False)  # BUY, SELL, DIVIDEND
    quantity = Column(Float, nullable=False, default=0.0)
    price = Column(Float, nullable=False, default=0.0)
    fee = Column(Float, nullable=False, default=0.0)
    realized_pnl = Column(Float, nullable=True)  # Calcolato su vendita: (price - avg_buy_price) * qty - fee
    currency = Column(String, nullable=True, default="EUR")
    transaction_date = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    notes = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    # Relationships
    stock = relationship("Stock", back_populates="transactions")
