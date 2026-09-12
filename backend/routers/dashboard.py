from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload

from backend.database import get_db
from backend.models.stock import Stock
from backend.models.settings import AlertRule
from backend.models.advice import Advice

from backend.services.market_data import MarketDataService
from backend.utils.helpers import detect_market_currency
from backend.services.portfolio_service import build_portfolio_summary, build_portfolio_rows
from backend.services.analytics import build_portfolio_daily_series

from backend.models.user import User
from backend.services.auth import get_current_user
from backend.routers.advice import serialize_advice, user_advice_filter

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])

@router.get("/")
async def get_dashboard(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # 1. Portfolio summary for logged-in user
    portfolio_summary = await build_portfolio_summary(db, user_id=current_user.id)
    
    # 2. Recent advices (solo dell'utente; gli admin vedono anche i legacy senza user_id)
    advices_result = await db.execute(
        select(Advice)
        .options(selectinload(Advice.stock))
        .where(user_advice_filter(current_user))
        .order_by(Advice.timestamp.desc())
        .limit(4)
    )
    recent_advices = [serialize_advice(a, include_stock=True, short_titles=True) for a in advices_result.scalars().all()]
    
    # 3. Active alerts count (solo le regole dell'utente corrente)
    alerts_result = await db.execute(
        select(AlertRule).where(
            AlertRule.is_active == True,
            AlertRule.user_id == current_user.id,
        )
    )
    active_alerts_count = len(alerts_result.scalars().all())
    
    # 4. Market status strutturato con orari italiani
    it_open = MarketDataService.is_market_open('IT')
    us_open = MarketDataService.is_market_open('US')
    eu_open = MarketDataService.is_market_open('EU')
    any_open = it_open or us_open or eu_open

    market_status = {
        "IT": "OPEN" if it_open else "CLOSED",
        "US": "OPEN" if us_open else "CLOSED",
        "EU": "OPEN" if eu_open else "CLOSED",
        "ANY_OPEN": "OPEN" if any_open else "CLOSED",
        "details": {
            "IT": {
                "name": "Borsa Italiana (Milano)",
                "flag": "🇮🇹",
                "status": "OPEN" if it_open else "CLOSED",
                "hours": "09:00 - 17:30"
            },
            "US": {
                "name": "Wall Street (New York)",
                "flag": "🇺🇸",
                "status": "OPEN" if us_open else "CLOSED",
                "hours": "15:30 - 22:00"
            }
        }
    }
    
    return {
        "portfolio_summary": portfolio_summary,
        "recent_advices": recent_advices,
        "active_alerts_count": active_alerts_count,
        "market_status": market_status
    }

@router.get("/indices")
async def get_indices():
    """
    Ritorna le quotazioni in tempo reale degli indici e commodity globali per la barra scorrevole.
    """
    indices = await MarketDataService.fetch_market_indices()
    return indices

@router.get("/heatmap")
async def get_market_heatmap(db: AsyncSession = Depends(get_db)):
    """
    Ritorna la panoramica di tutti i titoli monitorati e in portafoglio con
    variazione % odierna per la Heatmap. Fetch prezzi in parallelo (gather),
    ogni chiamata è thread-isolata con retry e fallback stale.
    """
    result = await db.execute(select(Stock).where(Stock.is_active == True))
    stocks = result.scalars().all()
    if not stocks:
        return []

    tickers = [stock.ticker for stock in stocks]
    prices_map = await MarketDataService.fetch_batch_prices(tickers)

    heatmap_items = []
    for stock in stocks:
        price_data = prices_map.get(stock.ticker) or MarketDataService._generate_fallback_price(stock.ticker)
        suffix_market, suffix_currency = detect_market_currency(stock.ticker)
        heatmap_items.append({
            "ticker": stock.ticker,
            "name": stock.name or stock.ticker,
            "market": stock.market or suffix_market,
            "currency": stock.currency or suffix_currency,
            "current_price": price_data.get("close", 0.0),
            "change_percent": price_data.get("change_percent", 0.0),
            "change_abs": price_data.get("change_abs", 0.0),
            "day_high": price_data.get("high", 0.0),
            "day_low": price_data.get("low", 0.0),
            "volume": price_data.get("volume", 0),
            "stale": bool(price_data.get("stale", False))
        })

    heatmap_items.sort(key=lambda x: abs(x["change_percent"]), reverse=True)
    return heatmap_items

@router.get("/performance")
async def get_performance(
    days: int = Query(30, ge=1, le=3650),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Ritorna l'andamento calcolato del valore complessivo del portafoglio dell'utente giorno
    per giorno (PriceHistory + backfill Yahoo).
    """
    portfolio = await build_portfolio_rows(db, user_id=current_user.id)
    series = await build_portfolio_daily_series(
        db, days=days, user_id=current_user.id, portfolio_rows=portfolio
    )
    if series:
        return {"data": series, "source": "real", "points": len(series)}

    # Portfolio vuoto: fallback tramite MarketDataService (serie piatta/zero)
    performance = await MarketDataService.calculate_portfolio_history(portfolio, days=days)
    return {"data": performance, "source": "fallback", "points": len(performance)}
