import logging
import math
from sqlalchemy import func
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from backend.models.stock import Stock, PriceHistory
from backend.models.portfolio import Holding
from backend.services.market_data import MarketDataService
from backend.utils.helpers import calculate_pnl

logger = logging.getLogger(__name__)


def _is_valid_float(v) -> bool:
    if v is None:
        return False
    try:
        f = float(v)
        return not (math.isnan(f) or math.isinf(f)) and f > 0
    except (ValueError, TypeError):
        return False


async def build_portfolio_rows(db: AsyncSession, user_id: int | None = None, usd_to_eur: float | None = None) -> list[dict]:
    """
    Costruisce le righe complete del portafoglio (holdings + prezzi live/DB) filtrate per utente.
    Usa selectinload per eliminare query N+1 ed esegue conversione valuta FX.
    `usd_to_eur` opzionale permette di riusare un tasso già calcolato nella stessa richiesta.
    """
    query = (
        select(Holding)
        .join(Stock)
        .where(Stock.is_active == True)
        .options(selectinload(Holding.stock))
    )
    if user_id is not None:
        query = query.where(Holding.user_id == user_id)

    result = await db.execute(query)
    holdings = result.scalars().all()
    if not holdings:
        return []

    if usd_to_eur is None:
        usd_to_eur = await MarketDataService.get_fx_rate("USD", "EUR")

    # 1. Recupera SOLO le ultime 2 righe PriceHistory per stock (window function),
    #    senza caricare l'intero storico di ogni titolo.
    stock_ids = [h.stock_id for h in holdings]
    ranked_prices = (
        select(
            PriceHistory,
            func.row_number().over(
                partition_by=PriceHistory.stock_id,
                order_by=PriceHistory.timestamp.desc()
            ).label("rn")
        )
        .where(PriceHistory.stock_id.in_(stock_ids))
        .subquery()
    )
    ph_result = await db.execute(
        select(PriceHistory)
        .join(ranked_prices, PriceHistory.id == ranked_prices.c.id)
        .where(ranked_prices.c.rn <= 2)
        .order_by(PriceHistory.stock_id, PriceHistory.timestamp.desc())
    )
    db_prices: dict[int, list[PriceHistory]] = {}
    for ph in ph_result.scalars().all():
        db_prices.setdefault(ph.stock_id, []).append(ph)

    # 2. Per i titoli senza prezzo valido nel DB, scarica i prezzi live in un'unica chiamata BATCH
    missing_live_tickers = []
    for h in holdings:
        ph_list = db_prices.get(h.stock_id, [])
        if not (ph_list and _is_valid_float(ph_list[0].close)):
            missing_live_tickers.append(h.stock.ticker)

    batch_prices = {}
    if missing_live_tickers:
        batch_prices = await MarketDataService.fetch_batch_prices(missing_live_tickers)

    portfolio = []
    for h in holdings:
        stock = h.stock
        ph_list = db_prices.get(h.stock_id, [])

        if ph_list and _is_valid_float(ph_list[0].close):
            raw_p = float(ph_list[0].close)
            prev_close = float(ph_list[1].close) if (len(ph_list) > 1 and _is_valid_float(ph_list[1].close)) else None
            is_stale = False
        else:
            pdata = batch_prices.get(stock.ticker) or {}
            raw_p = pdata.get("close")
            prev_close = float(pdata["previous_close"]) if _is_valid_float(pdata.get("previous_close")) else None
            is_stale = bool(pdata.get("stale", False))

        current_price = float(raw_p) if _is_valid_float(raw_p) else (float(h.avg_purchase_price) if _is_valid_float(h.avg_purchase_price) else 0.0)
        pnl = calculate_pnl(current_price, h.avg_purchase_price, h.quantity)

        daily_pnl = None
        if prev_close:
            daily_pnl = round((current_price - prev_close) * h.quantity, 2)

        _fallback_market, _fallback_currency = MarketDataService.detect_market_currency(stock.ticker)
        currency = stock.currency or _fallback_currency
        market = stock.market or _fallback_market
        fx_rate = usd_to_eur if currency == "USD" else 1.0

        portfolio.append({
            "id": h.id,
            "stock_id": h.stock_id,
            "ticker": stock.ticker,
            "name": stock.name or stock.ticker,
            "market": market,
            "currency": currency,
            "quantity": h.quantity,
            "avg_purchase_price": h.avg_purchase_price,
            "current_price": current_price,
            "previous_close": prev_close,
            "price_stale": is_stale,
            "total_value": round(h.quantity * current_price, 2),
            "total_invested": round(h.quantity * h.avg_purchase_price, 2),
            "total_value_eur": round(h.quantity * current_price * fx_rate, 2),
            "total_invested_eur": round(h.quantity * h.avg_purchase_price * fx_rate, 2),
            "fx_rate_to_eur": fx_rate,
            "pnl_absolute": pnl["pnl_absolute"],
            "pnl_percent": pnl["pnl_percent"],
            "daily_pnl": daily_pnl,
            "purchase_date": str(h.purchase_date) if h.purchase_date else None,
            "notes": h.notes or ""
        })

    return portfolio


async def build_portfolio_summary(db: AsyncSession, user_id: int | None = None) -> dict:
    """Riepilogo aggregato del portafoglio in valuta base EUR filtrato per utente."""
    # Calcola il tasso FX UNA sola volta e lo passa a build_portfolio_rows
    usd_to_eur = await MarketDataService.get_fx_rate("USD", "EUR")
    portfolio = await build_portfolio_rows(db, user_id=user_id, usd_to_eur=usd_to_eur)

    total_invested = sum(h.get("total_invested_eur", h["total_invested"]) for h in portfolio)
    total_value = sum(h.get("total_value_eur", h["total_value"]) for h in portfolio)
    total_pnl = total_value - total_invested
    total_pnl_percent = (total_pnl / total_invested * 100) if total_invested > 0 else 0.0

    # P&L Giornaliero in EUR
    daily_pnl = 0.0
    prev_value_base = 0.0
    has_daily = False
    for h in portfolio:
        if h.get("previous_close"):
            fx = h.get("fx_rate_to_eur", 1.0)
            delta = (h["current_price"] - h["previous_close"]) * h["quantity"] * fx
            daily_pnl += delta
            prev_value_base += h["previous_close"] * h["quantity"] * fx
            has_daily = True
    daily_pnl_percent = (daily_pnl / prev_value_base * 100) if prev_value_base > 0 else 0.0

    # Top Gainer & Top Loser
    sorted_by_pnl = sorted(portfolio, key=lambda x: x["pnl_percent"], reverse=True)
    top_gainer = sorted_by_pnl[0] if sorted_by_pnl and sorted_by_pnl[0]["pnl_percent"] > 0 else None
    top_loser = sorted_by_pnl[-1] if sorted_by_pnl and sorted_by_pnl[-1]["pnl_percent"] < 0 else None

    # Market Allocation Breakdown in EUR
    market_allocation = {"IT": 0.0, "US": 0.0, "EU": 0.0}
    for h in portfolio:
        m = (h.get("market") or "US").upper()
        eur_val = h.get("total_value_eur", h["total_value"])
        if m in market_allocation:
            market_allocation[m] += eur_val
        else:
            market_allocation["US"] += eur_val

    # Stima dividendi annui in EUR
    estimated_annual_dividends = 0.0
    for h in portfolio:
        dy = MarketDataService.get_stock_dividend_yield(h["ticker"])
        if dy > 0:
            eur_val = h.get("total_value_eur", h["total_value"])
            estimated_annual_dividends += (eur_val * (dy / 100.0))

    estimated_dividend_yield = (estimated_annual_dividends / total_value * 100) if total_value > 0 else 0.0

    return {
        "total_value": round(total_value, 2),
        "total_invested": round(total_invested, 2),
        "total_pnl": round(total_pnl, 2),
        "total_pnl_percent": round(total_pnl_percent, 2),
        "daily_pnl": round(daily_pnl, 2) if has_daily else 0.0,
        "daily_pnl_percent": round(daily_pnl_percent, 2) if has_daily else 0.0,
        "holdings_count": len(portfolio),
        "top_gainer": top_gainer,
        "top_loser": top_loser,
        "market_allocation": {k: round(v, 2) for k, v in market_allocation.items()},
        "estimated_annual_dividends": round(estimated_annual_dividends, 2),
        "estimated_dividend_yield": round(estimated_dividend_yield, 2),
        "fx_usd_eur": round(usd_to_eur, 4)
    }
