import asyncio
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select
from pydantic import BaseModel
from typing import Optional

from backend.database import get_db
from backend.models.watchlist import WatchlistItem
from backend.models.stock import Stock
from backend.models.portfolio import Holding
from backend.models.user import User
from backend.services.auth import get_current_user
from backend.services.market_data import MarketDataService

router = APIRouter(prefix="/api/watchlist", tags=["watchlist"])

class WatchlistAddRequest(BaseModel):
    ticker: str
    notes: Optional[str] = None
    alert_above: Optional[float] = None
    alert_below: Optional[float] = None

class WatchlistAlertUpdateRequest(BaseModel):
    alert_above: Optional[float] = None
    alert_below: Optional[float] = None

def _can_access_watchlist_item(item: WatchlistItem, current_user: User) -> bool:
    """
    Ownership STRICT: solo il proprietario può modificare/eliminare l'elemento.

    Righe legacy con user_id NULL (pre multi-utente): accesso riservato
    all'admin, stesso precedente di `_can_access_advice` in advice.py.
    """
    if item.user_id is None:
        return bool(current_user.is_admin)
    return item.user_id == current_user.id

@router.get("/")
async def get_watchlist(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(WatchlistItem)
        .join(Stock)
        .where(WatchlistItem.user_id == current_user.id)
    )
    items = result.scalars().all()

    if not items:
        return []

    stock_ids = [item.stock_id for item in items]
    stocks_result = await db.execute(select(Stock).where(Stock.id.in_(stock_ids)))
    stocks_map = {s.id: s for s in stocks_result.scalars().all()}

    holdings_result = await db.execute(
        select(Holding.stock_id)
        .where(Holding.stock_id.in_(stock_ids), Holding.user_id == current_user.id)
    )
    in_portfolio_ids = {row[0] for row in holdings_result.all()}

    # H4: chiude la transazione di lettura PRIMA delle chiamate di rete
    # (deep-dive). Con expire_on_commit=False gli oggetti ORM restano utilizzabili.
    await db.commit()

    # M2: mappa {stock_id: deep_result} costruita sulla STESSA lista filtrata
    # usata poi nel loop: niente più disallineamento degli iteratori quando
    # uno stock è assente (ogni item riceve il proprio deep-dive, non quello
    # dell'item precedente).
    deep_stocks = {
        item.stock_id: stocks_map[item.stock_id]
        for item in items if item.stock_id in stocks_map
    }
    deep_tasks = [
        MarketDataService.fetch_stock_deep_dive(stock.ticker)
        for stock in deep_stocks.values()
    ]
    deep_results = await asyncio.gather(*deep_tasks, return_exceptions=True)
    deep_by_stock_id: dict[int, dict] = {}
    for stock_id, deep in zip(deep_stocks.keys(), deep_results):
        deep_by_stock_id[stock_id] = deep if isinstance(deep, dict) else {}

    watchlist = []
    for item in items:
        stock = stocks_map.get(item.stock_id)
        if not stock:
            continue

        deep = deep_by_stock_id.get(item.stock_id, {})
        if not isinstance(deep, dict):
            deep = {}

        cur_price = deep.get("current_price", 0.0)
        is_triggered = False
        if item.alert_above and cur_price >= item.alert_above:
            is_triggered = True
        elif item.alert_below and cur_price <= item.alert_below:
            is_triggered = True

        watchlist.append({
            "id": item.id,
            "stock_id": stock.id,
            "ticker": stock.ticker,
            "name": stock.name or deep.get("name", stock.ticker),
            "market": stock.market or deep.get("market", "US"),
            "currency": stock.currency or deep.get("currency", "USD"),
            "current_price": cur_price,
            "change_abs": deep.get("change_abs", 0.0),
            "change_percent": deep.get("change_percent", 0.0),
            "day_high": deep.get("day_high", 0.0),
            "day_low": deep.get("day_low", 0.0),
            "fifty_two_week_high": deep.get("fifty_two_week_high", 0.0),
            "fifty_two_week_low": deep.get("fifty_two_week_low", 0.0),
            "fifty_two_week_pct": deep.get("fifty_two_week_pct", 50.0),
            "pe_ratio": deep.get("pe_ratio"),
            "dividend_yield": deep.get("dividend_yield"),
            "rsi": deep.get("technical", {}).get("rsi_14", 50.0),
            "rsi_status": deep.get("technical", {}).get("rsi_status", "Neutro"),
            "rsi_badge": deep.get("technical", {}).get("rsi_badge", "badge-hold"),
            "notes": item.notes or "",
            "alert_above": item.alert_above,
            "alert_below": item.alert_below,
            "alert_triggered": is_triggered,
            "is_in_portfolio": stock.id in in_portfolio_ids,
            "added_at": str(item.added_at) if item.added_at else None
        })

    return watchlist

@router.post("/")
async def add_to_watchlist(
    data: WatchlistAddRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    ticker = data.ticker.strip().upper()
    if not ticker:
        raise HTTPException(status_code=400, detail="Ticker non valido.")

    result = await db.execute(select(Stock).where(Stock.ticker == ticker))
    stock = result.scalars().first()
    if not stock:
        # Il suffisso è autoritario: il deep dive arricchisce solo il nome,
        # mai declassato a US (classify_new_stock logga l'eventuale mismatch).
        deep = await MarketDataService.fetch_stock_deep_dive(ticker)
        name = deep.get("name") or ticker
        market, currency = MarketDataService.classify_new_stock(ticker, deep)
        stock = Stock(ticker=ticker, name=name, market=market, currency=currency)
        db.add(stock)
        try:
            await db.commit()
            await db.refresh(stock)
        except IntegrityError:
            # Race su UNIQUE stocks.ticker: un'altra sessione l'ha creato nel frattempo.
            await db.rollback()
            result = await db.execute(select(Stock).where(Stock.ticker == ticker))
            stock = result.scalars().first()
            if not stock:
                raise HTTPException(status_code=409, detail=f"Conflitto concorrente sulla creazione di {ticker}.")

    w_res = await db.execute(
        select(WatchlistItem)
        .where(WatchlistItem.stock_id == stock.id, WatchlistItem.user_id == current_user.id)
    )
    existing = w_res.scalars().first()
    if existing:
        if data.notes:
            existing.notes = data.notes
        if data.alert_above is not None:
            existing.alert_above = data.alert_above
        if data.alert_below is not None:
            existing.alert_below = data.alert_below
        await db.commit()
        return {"status": "exists", "message": f"{ticker} è già nella Watchlist (aggiornato)", "id": existing.id}

    item = WatchlistItem(
        user_id=current_user.id,
        stock_id=stock.id,
        notes=data.notes,
        alert_above=data.alert_above,
        alert_below=data.alert_below
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return {"status": "success", "message": f"{ticker} aggiunto alla Watchlist", "id": item.id}

@router.put("/{item_id}/alert")
async def update_watchlist_alert(
    item_id: int,
    data: WatchlistAlertUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    item = await db.get(WatchlistItem, item_id)
    if not item or not _can_access_watchlist_item(item, current_user):
        raise HTTPException(status_code=404, detail="Elemento Watchlist non trovato.")
    
    item.alert_above = data.alert_above
    item.alert_below = data.alert_below
    await db.commit()
    return {"status": "success", "message": "Alert aggiornato con successo"}

@router.delete("/{item_id}")
async def remove_from_watchlist(
    item_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    item = await db.get(WatchlistItem, item_id)
    if not item or not _can_access_watchlist_item(item, current_user):
        raise HTTPException(status_code=404, detail="Elemento Watchlist non trovato.")

    await db.delete(item)
    await db.commit()
    return {"status": "success", "message": "Rimosso dalla Watchlist"}

@router.delete("/ticker/{ticker}")
async def remove_by_ticker(
    ticker: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    ticker_up = ticker.strip().upper()
    result = await db.execute(select(Stock).where(Stock.ticker == ticker_up))
    stock = result.scalars().first()
    if not stock:
        raise HTTPException(status_code=404, detail="Titolo non trovato.")

    w_res = await db.execute(
        select(WatchlistItem)
        .where(WatchlistItem.stock_id == stock.id, WatchlistItem.user_id == current_user.id)
    )
    item = w_res.scalars().first()
    if item:
        await db.delete(item)
        await db.commit()

    return {"status": "success", "message": f"{ticker_up} rimosso dalla Watchlist"}
