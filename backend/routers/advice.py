import json
import time
from collections import defaultdict
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload
from sqlalchemy import func, or_
from typing import Optional
from datetime import datetime, timedelta, timezone

from backend.database import get_db
from backend.models.advice import Advice
from backend.models.user import User
from backend.services.advisor import AdvisorService
from backend.services.auth import get_current_user
from backend.services.market_data import MarketDataService

# Rate limiter in-memory per proteggere le quote API Gemini
_CALL_TIMESTAMPS = defaultdict(list)
RATE_LIMIT_MAX_CALLS = 12  # Max 12 richieste al minuto
RATE_LIMIT_WINDOW_SECONDS = 60

def _prune_rate_limiter(now: float | None = None) -> None:
    """Rimuove le chiavi inattive per mantenere bounded la memoria del rate limiter."""
    now = now if now is not None else time.time()
    stale = [
        key for key, timestamps in _CALL_TIMESTAMPS.items()
        if not timestamps or (now - timestamps[-1]) >= RATE_LIMIT_WINDOW_SECONDS
    ]
    for key in stale:
        _CALL_TIMESTAMPS.pop(key, None)

def _check_rate_limit(client_id: str = "global"):
    now = time.time()
    _prune_rate_limiter(now)
    timestamps = _CALL_TIMESTAMPS[client_id]
    _CALL_TIMESTAMPS[client_id] = [t for t in timestamps if now - t < RATE_LIMIT_WINDOW_SECONDS]
    if len(_CALL_TIMESTAMPS[client_id]) >= RATE_LIMIT_MAX_CALLS:
        raise HTTPException(
            status_code=429,
            detail="Troppe richieste di analisi AI inviate in breve tempo. Riprova tra 60 secondi."
        )
    _CALL_TIMESTAMPS[client_id].append(now)

def user_advice_filter(current_user: User):
    """Visibility filter: propri advice + (per gli admin) advice legacy senza user_id."""
    if current_user.is_admin:
        return or_(Advice.user_id == current_user.id, Advice.user_id.is_(None))
    return Advice.user_id == current_user.id

def serialize_advice(a: Advice, include_stock: bool = True, short_titles: bool = False) -> dict:
    """Serializzazione unica degli Advice (shape API invariata)."""
    try:
        stocks_analysis = json.loads(a.stocks_json) if a.stocks_json else []
    except Exception:
        stocks_analysis = []

    if short_titles:
        default_title = "Borsa Italiana" if a.market == "IT" else "Wall Street"
    else:
        default_title = (
            "Borsa Italiana (Piazza Affari)" if a.market == "IT"
            else ("Borsa Americana (Wall Street)" if a.market == "US" else "Analisi di Mercato")
        )

    payload = {
        "id": a.id,
        "market": a.market or "ALL",
        "title": a.title or default_title,
        "action": a.action,
        "overview": a.overview,
        "strategy": a.reasoning,
        "stocks_analysis": stocks_analysis,
        "risks": a.risks,
        "confidence": a.confidence,
        "timeframe": a.timeframe,
        "targetPrice": a.target_price,
        "suggestedQuantity": a.suggested_quantity,
        "followed": bool(a.followed),
        "timestamp": str(a.timestamp) if a.timestamp else str(a.created_at)
    }
    if include_stock:
        payload["ticker"] = a.stock.ticker if a.stock else None
        payload["name"] = a.stock.name if a.stock else None
    return payload

router = APIRouter(prefix="/api/advice", tags=["advice"])

@router.get("/")
async def list_advices(
    market: Optional[str] = None,
    action: Optional[str] = None,
    date: Optional[str] = None,
    days: int = Query(7),
    skip: int = 0,
    limit: int = 20,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    query = select(Advice).options(selectinload(Advice.stock)).where(user_advice_filter(current_user))
    
    if market:
        query = query.where(Advice.market == market.upper())
    if action:
        query = query.where(Advice.action.ilike(f"%{action}%"))
        
    if date:
        try:
            target_date = datetime.strptime(date, "%Y-%m-%d").date()
            query = query.where(func.date(Advice.timestamp) == target_date)
        except ValueError:
            pass
    else:
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)
        query = query.where(Advice.timestamp >= cutoff)
        
    query = query.order_by(Advice.timestamp.desc()).offset(skip).limit(limit)
    
    result = await db.execute(query)
    advices = result.scalars().all()
    return [serialize_advice(a, include_stock=True) for a in advices]

@router.get("/latest")
async def get_latest(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    result = await db.execute(
        select(Advice)
        .where(Advice.timestamp >= cutoff, user_advice_filter(current_user))
        .order_by(Advice.timestamp.desc())
        .limit(4)
    )
    advices = result.scalars().all()
    return [serialize_advice(a, include_stock=False) for a in advices]

@router.post("/stock/{ticker}")
async def analyze_stock_on_demand(
    ticker: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Richiede un'analisi istantanea approfondita a Google Gemini 3.7 Flash per un singolo titolo.
    """
    _check_rate_limit(f"stock_{ticker.upper()}")
    advisor = AdvisorService()
    analysis = await advisor.analyze_single_stock(ticker, db, user_id=current_user.id)
    return analysis

@router.post("/{advice_id}/toggle-follow")
@router.post("/{advice_id}/follow")
async def toggle_follow_advice(
    advice_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    advice = await db.get(Advice, advice_id)
    if not advice or not _can_access_advice(advice, current_user):
        raise HTTPException(status_code=404, detail="Analisi non trovata")
        
    advice.followed = not bool(advice.followed)
    await db.commit()
    return {"status": "success", "followed": advice.followed}

def _can_access_advice(advice: Advice, current_user: User) -> bool:
    if advice.user_id is None:
        return bool(current_user.is_admin)
    return advice.user_id == current_user.id

@router.post("/generate")
async def generate_advice(
    force: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    _check_rate_limit(f"generate_{current_user.id}")
    if not force and not MarketDataService.are_any_markets_open():
        raise HTTPException(
            status_code=400,
            detail="Tutti i mercati finanziari sono attualmente chiusi (Milano 09:00-17:30, Wall Street 15:30-22:00 ora italiana). Puoi comunque forzare la generazione manuale."
        )
    advisor = AdvisorService()
    advices = await advisor.generate_advice(db, force=force, user_id=current_user.id)
    return {"status": "success", "generated_count": len(advices), "advices": advices}
