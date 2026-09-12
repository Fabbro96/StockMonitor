import logging
import asyncio
import math
import time
from datetime import datetime, timedelta, timezone

import numpy as np
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.config import settings
from backend.models.stock import PriceHistory
from backend.services.market_data import MarketDataService
from backend.services.portfolio_service import build_portfolio_rows

logger = logging.getLogger(__name__)

TRADING_DAYS_PER_YEAR = 252

# Cache risultati costosi: (result, timestamp)
_RISK_CACHE: dict[str, tuple[dict, float]] = {}
_RISK_CACHE_TTL = 300.0  # 5 minuti
# Cache serie giornaliera portafoglio: il backfill Yahoo (fino a N candele "1y"
# per ticker con storico scarso) costava ~2.4s a OGNI chiamata con Yahoo ko.
# Lo storico reale resta su PriceHistory; qui si cachia solo il risultato.
_SERIES_CACHE: dict[str, tuple[list[dict], float]] = {}
_SERIES_CACHE_TTL = 120.0  # 2 minuti
# Tetto semplice anti-crescita illimitata (multi-utente x più finestre `days`).
_ANALYTICS_CACHE_MAX_ENTRIES = 256


def _cache_store(cache: dict, key: str, value: tuple) -> None:
    """Scrive in cache applicando un tetto FIFO (le entry più vecchie escono)."""
    cache[key] = value
    while len(cache) > _ANALYTICS_CACHE_MAX_ENTRIES:
        cache.pop(next(iter(cache)), None)


def invalidate_user_caches(user_id) -> None:
    """Invalida le cache analytics (serie giornaliera e risk) di un utente.

    Le chiavi sono `series:{user_id}:{days}` e `risk:{user_id}:{days}`: rimuove
    tutte le varianti per quel solo utente, senza toccare gli altri. Sicura da
    chiamare in qualsiasi momento (cache vuote, user_id None/str/int) e non
    solleva mai: BE-1/BE-2 la invocano via import lazy dopo mutazioni di
    portafoglio/watchlist/holdings.
    """
    try:
        prefixes = (f"series:{user_id}:", f"risk:{user_id}:")
        for cache in (_SERIES_CACHE, _RISK_CACHE):
            stale_keys = [k for k in list(cache.keys()) if k.startswith(prefixes)]
            for k in stale_keys:
                cache.pop(k, None)
    except Exception as e:  # l'invalidazione non deve mai propagare errori
        logger.debug(f"invalidate_user_caches fallita per user_id={user_id}: {e}")


# ---------------------------------------------------------------------------
# Serie storica giornaliera del valore del portafoglio
# ---------------------------------------------------------------------------
async def build_portfolio_daily_series(
    db: AsyncSession,
    days: int = 180,
    user_id: int | None = None,
    portfolio_rows: list[dict] | None = None
) -> list[dict]:
    """
    Costruisce la serie giornaliera del valore del portafoglio per un utente:
    1. chiusura giornaliera da PriceHistory (dati raccolti dallo scheduler)
    2. backfill con candele giornaliere Yahoo (fetch_stock_candles '1y')
    3. forward-fill dei giorni mancanti; prezzo corrente per l'ultimo giorno
    Ritorna [{"date": "YYYY-MM-DD", "value": float}] ordinato per data.
    Ogni `value` è il controvalore del portafoglio in EUR: i prezzi nativi dei
    titoli in valuta estera sono convertiti con `fx_rate_to_eur` (stesso
    percorso FX di `build_portfolio_rows` e del rebalancer), così le metriche
    derivate (drawdown, volatilità, Sharpe) non sommano valute diverse.

    `portfolio_rows`: righe già calcolate da build_portfolio_rows per la stessa
    richiesta; se fornite evitano un ricalcolo completo del portafoglio.
    """
    cache_key = f"series:{user_id}:{days}"
    now_ts = time.time()
    cached = _SERIES_CACHE.get(cache_key)
    if cached and now_ts - cached[1] < _SERIES_CACHE_TTL:
        return cached[0]

    portfolio = portfolio_rows if portfolio_rows is not None else await build_portfolio_rows(db, user_id=user_id)
    if not portfolio:
        return []

    today = datetime.now(timezone.utc).date()
    start_date = today - timedelta(days=days)

    # 1. Chiusure giornaliere aggregate da PriceHistory (aggregazione in Python
    #    per massima robustezza con i tipi data di SQLite/aiosqlite)
    stock_ids = [h["stock_id"] for h in portfolio]
    cutoff = datetime(start_date.year, start_date.month, start_date.day, tzinfo=timezone.utc)
    result = await db.execute(
        select(PriceHistory.stock_id, PriceHistory.timestamp, PriceHistory.close)
        .where(PriceHistory.stock_id.in_(stock_ids), PriceHistory.timestamp >= cutoff)
        .order_by(PriceHistory.timestamp)
    )
    rows = result.all()

    daily_close: dict[int, dict[str, float]] = {sid: {} for sid in stock_ids}
    for sid, ts, close in rows:
        if not close:
            continue
        ts_date = ts.date() if hasattr(ts, "date") else ts
        day_str = str(ts_date)[:10]
        # Le righe sono ordinate per timestamp: l'ultima chiusura del giorno vince
        daily_close[sid][day_str] = float(close)

    # 2. Backfill con candele giornaliere Yahoo per i ticker con storico insufficiente
    backfill_tasks = {}
    for h in portfolio:
        if len(daily_close.get(h["stock_id"], {})) < 5:
            backfill_tasks[h["stock_id"]] = MarketDataService.fetch_stock_candles(h["ticker"], "1y")
    if backfill_tasks:
        results = await asyncio.gather(*backfill_tasks.values(), return_exceptions=True)
        for sid, res in zip(backfill_tasks.keys(), results):
            if isinstance(res, list) and res:
                merged = daily_close.setdefault(sid, {})
                for c in res:
                    if isinstance(c.get("time"), str) and c.get("close"):
                        merged.setdefault(c["time"], float(c["close"]))

    # 3. Costruzione serie giornaliera con forward-fill
    series = []
    last_known: dict[int, float] = {}
    for h in portfolio:
        if h["stock_id"] in daily_close and daily_close[h["stock_id"]]:
            first_day = sorted(daily_close[h["stock_id"]].keys())[0]
            last_known[h["stock_id"]] = daily_close[h["stock_id"]][first_day]

    current = start_date
    while current <= today:
        day_str = current.isoformat()
        total = 0.0
        has_data = False
        for h in portfolio:
            closes = daily_close.get(h["stock_id"], {})
            if day_str in closes:
                last_known[h["stock_id"]] = closes[day_str]
            price = last_known.get(h["stock_id"])
            if price:
                # Valore della posizione in EUR: stessa conversione FX per-holding
                # usata da `compute_rebalance_plan` (price * fx_rate_to_eur).
                total += float(h["quantity"]) * price * _holding_fx_to_eur(h)
                has_data = True
        if has_data:
            series.append({"date": day_str, "value": round(total, 2)})
        current += timedelta(days=1)

    _cache_store(_SERIES_CACHE, cache_key, (series, now_ts))
    return series


def normalize_growth(series: list[dict]) -> list[dict]:
    """Normalizza una serie di valori in crescita percentuale dal primo punto."""
    if not series:
        return []
    base = series[0]["value"]
    if not base:
        base = next((p["value"] for p in series if p["value"]), 0.0)
    if not base:
        return [{"date": p["date"], "growth_pct": 0.0} for p in series]
    return [
        {"date": p["date"], "growth_pct": round((p["value"] / base - 1.0) * 100.0, 3)}
        for p in series
    ]


# ---------------------------------------------------------------------------
# Metriche di rischio quantitative
# ---------------------------------------------------------------------------
async def compute_risk_metrics(
    db: AsyncSession,
    days: int = 180,
    user_id: int | None = None,
    portfolio_rows: list[dict] | None = None
) -> dict:
    """
    Calcola le metriche di rischio/performance del portafoglio per utente:
    Max Drawdown, Volatilità annualizzata, Sharpe Ratio, Beta pesato,
    Rendimento annualizzato.

    `portfolio_rows` opzionale: righe già calcolate per la stessa richiesta.
    """
    cache_key = f"risk:{user_id}:{days}"
    now_ts = time.time()
    cached = _RISK_CACHE.get(cache_key)
    if cached and now_ts - cached[1] < _RISK_CACHE_TTL:
        return cached[0]

    portfolio = portfolio_rows if portfolio_rows is not None else await build_portfolio_rows(db, user_id=user_id)
    series = await build_portfolio_daily_series(db, days=days, user_id=user_id, portfolio_rows=portfolio)
    values = [p["value"] for p in series if p["value"] > 0]

    metrics = {
        "days_analyzed": len(values),
        "series_start": series[0]["date"] if series else None,
        "series_end": series[-1]["date"] if series else None,
        "max_drawdown_pct": 0.0,
        "annualized_volatility_pct": 0.0,
        "sharpe_ratio": 0.0,
        "annualized_return_pct": 0.0,
        "weighted_beta": 0.0,
        "risk_free_rate_pct": round(settings.RISK_FREE_RATE * 100, 2),
        "current_value": values[-1] if values else 0.0,
    }

    if len(values) >= 3:
        arr = np.asarray(values, dtype=float)

        # --- Max Drawdown (peak-to-trough) ---
        running_max = np.maximum.accumulate(arr)
        drawdowns = (arr - running_max) / running_max
        metrics["max_drawdown_pct"] = round(float(drawdowns.min()) * 100.0, 2)

        # --- Rendimenti giornalieri -> volatilità annualizzata ---
        daily_returns = np.diff(arr) / arr[:-1]
        ann_vol = float(np.std(daily_returns, ddof=1) * math.sqrt(TRADING_DAYS_PER_YEAR))
        metrics["annualized_volatility_pct"] = round(ann_vol * 100.0, 2)

        # --- Rendimento annualizzato (geometrico) ---
        n_days = max(len(arr) - 1, 1)
        total_return = arr[-1] / arr[0]
        years = n_days / TRADING_DAYS_PER_YEAR
        if total_return > 0 and years > 0:
            ann_return = total_return ** (1.0 / years) - 1.0
        else:
            ann_return = 0.0
        metrics["annualized_return_pct"] = round(ann_return * 100.0, 2)

        # --- Sharpe Ratio stimato ---
        if ann_vol > 1e-9:
            metrics["sharpe_ratio"] = round((ann_return - settings.RISK_FREE_RATE) / ann_vol, 2)

    # --- Beta pesato (pesi = controvalore attuale convertito in EUR) ---
    total_value = sum(_holding_value_eur(h) for h in portfolio)
    if portfolio and total_value > 0:
        deep_tasks = [MarketDataService.fetch_stock_deep_dive(h["ticker"]) for h in portfolio]
        deep_results = await asyncio.gather(*deep_tasks, return_exceptions=True)
        weighted_beta = 0.0
        betas = {}
        for h, deep in zip(portfolio, deep_results):
            beta = deep.get("beta") if isinstance(deep, dict) else None
            try:
                beta = float(beta)
            except (TypeError, ValueError):
                beta = None
            if beta is None or not (0.0 <= beta <= 5.0):
                beta = 1.0  # default prudenziale
            betas[h["ticker"]] = round(beta, 2)
            weighted_beta += (_holding_value_eur(h) / total_value) * beta
        metrics["weighted_beta"] = round(weighted_beta, 2)
        metrics["betas"] = betas

    _cache_store(_RISK_CACHE, cache_key, (metrics, now_ts))
    return metrics


# ---------------------------------------------------------------------------
# Confronto Benchmark (S&P 500 / FTSE MIB)
# ---------------------------------------------------------------------------
BENCHMARKS = {
    "^GSPC": {"name": "S&P 500", "flag": "🇺🇸"},
    "FTSEMIB.MI": {"name": "FTSE MIB", "flag": "🇮🇹"},
}


def _period_for_days(days: int) -> str:
    if days <= 31:
        return "3mo"
    if days <= 120:
        return "6mo"
    if days <= 380:
        return "1y"
    return "5y"


async def compute_benchmark_comparison(
    db: AsyncSession,
    days: int = 90,
    benchmark_tickers: list[str] | None = None,
    user_id: int | None = None,
    portfolio_rows: list[dict] | None = None
) -> dict:
    """
    Confronta la crescita percentuale del portafoglio dell'utente con gli indici benchmark.
    `portfolio_rows` opzionale: righe già calcolate per la stessa richiesta.
    """
    if benchmark_tickers is None:
        benchmark_tickers = ["^GSPC", "FTSEMIB.MI"]

    period = _period_for_days(days)
    portfolio = portfolio_rows if portfolio_rows is not None else await build_portfolio_rows(db, user_id=user_id)
    series = await build_portfolio_daily_series(db, days=days, user_id=user_id, portfolio_rows=portfolio)
    portfolio_growth = normalize_growth(series)

    start_date = series[0]["date"] if series else None
    end_date = series[-1]["date"] if series else None

    tasks = [MarketDataService.fetch_index_history(t, period) for t in benchmark_tickers]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    benchmarks_out = {}
    for ticker, res in zip(benchmark_tickers, results):
        meta = BENCHMARKS.get(ticker, {"name": ticker, "flag": "📊"})
        # Contratto garantito: ogni benchmark richiesto ha SEMPRE "data" come
        # lista (vuota se senza dati), mai None/oggetti/eccezioni.
        data: list = []
        try:
            if isinstance(res, list) and res:
                filtered = [
                    p for p in res
                    if isinstance(p, dict)
                    and (start_date is None or p.get("time") is not None and p["time"] >= start_date)
                    and (end_date is None or p.get("time") is not None and p["time"] <= end_date)
                    and p.get("close")
                ]
                if not filtered:
                    filtered = res[-days:] if len(res) > days else res
                grown = normalize_growth([
                    {"date": p["time"], "value": p["close"]}
                    for p in filtered if isinstance(p, dict) and p.get("time") and p.get("close")
                ])
                data = grown if isinstance(grown, list) else []
        except Exception:
            logger.debug(f"Benchmark {ticker}: fallback a serie vuota.")
            data = []
        benchmarks_out[ticker] = {"name": meta["name"], "flag": meta["flag"], "data": data}

    return {
        "start_date": start_date,
        "end_date": end_date,
        "portfolio": portfolio_growth,
        "benchmarks": benchmarks_out
    }


# ---------------------------------------------------------------------------
# Motore di Ribilanciamento Smart
# ---------------------------------------------------------------------------
def _market_of(holding_row: dict) -> str:
    m = (holding_row.get("market") or "US").upper()
    if m.startswith("EU"):
        return "EU"
    return m


def _holding_value_eur(holding_row: dict) -> float:
    """Controvalore della posizione convertito in EUR (fallback al nativo).

    `build_portfolio_rows` espone `total_value_eur`; per righe legacy o parziali
    (test, chiamate dirette) si ricade sul valore nativo, come già fa il summary.
    """
    try:
        raw = holding_row.get("total_value_eur", holding_row.get("total_value", 0.0))
        return float(raw or 0.0)
    except (TypeError, ValueError):
        return 0.0


def _holding_fx_to_eur(holding_row: dict) -> float:
    try:
        fx = float(holding_row.get("fx_rate_to_eur") or 1.0)
        return fx if fx > 0 else 1.0
    except (TypeError, ValueError):
        return 1.0


def _merge_rebalance_orders(raw_orders: list[dict]) -> list[dict]:
    """Consolida gli ordini per ticker (fix doppio conteggio target sovrapposti).

    Le quantità con segno si sommano: un ticker presente in più bucket non genera
    più gambe duplicate. La gamba SELL aggregata viene poi limitata alla quantità
    detenuta. `estimated_value` è ricalcolato come quantità * prezzo nativo.
    """
    merged: dict[str, dict] = {}
    for o in raw_orders:
        tk = o["ticker"]
        current = merged.get(tk)
        if current is None:
            current = {
                "ticker": tk,
                "name": o["name"],
                "allocation_names": [],
                "signed_quantity": 0.0,
                "estimated_price": o["estimated_price"],
                "currency": o["currency"],
                "fx_rate_to_eur": o["fx_rate_to_eur"],
                "held_quantity": o["held_quantity"],
            }
            merged[tk] = current
        alloc_name = o.get("allocation_name")
        if alloc_name and alloc_name not in current["allocation_names"]:
            current["allocation_names"].append(alloc_name)
        current["signed_quantity"] += o["signed_quantity"]
        current["held_quantity"] = max(current["held_quantity"], o["held_quantity"])

    orders = []
    for m in merged.values():
        qty = m["signed_quantity"]
        if qty < 0:
            # Cap aggregato: mai vendere più di quanto posseduto.
            qty = max(qty, -m["held_quantity"])
        if abs(qty) < 0.0001:
            continue
        price = float(m["estimated_price"])
        value_native = abs(qty) * price
        orders.append({
            "ticker": m["ticker"],
            "name": m["name"],
            "allocation_name": " + ".join(m["allocation_names"]) if m["allocation_names"] else None,
            "side": "BUY" if qty > 0 else "SELL",
            "quantity": round(abs(qty), 4),
            "estimated_price": round(price, 2),
            "estimated_value": round(value_native, 2),
            "currency": m["currency"],
            # Solo per i totali di piano in EUR; rimosso dal payload pubblico.
            "_value_eur": round(value_native * float(m["fx_rate_to_eur"] or 1.0), 2),
        })
    return orders


def compute_rebalance_plan(portfolio: list[dict], targets: list[dict], extra_cash: float = 0.0) -> dict:
    """
    Motore di ribilanciamento: date le allocazioni target e le posizioni correnti,
    calcola per ciascun bucket il delta e genera gli ordini (buy/sell) necessari,
    distribuiti pro-quota sui titoli del bucket.

    targets: [{"id", "name", "target_percent", "scope_type" (MARKET|TICKERS|CASH), "scope_value"}]

    Tutti gli aggregati di piano (total_value, allocations) sono in EUR
    (`total_value_eur`), per non sommare controvalori USD ed EUR. Gli ordini
    restano nella valuta nativa del titolo (estimated_price/estimated_value/
    currency) e sono consolidati per ticker.
    """
    extra_cash = max(extra_cash, 0.0)
    total_value = sum(_holding_value_eur(h) for h in portfolio) + extra_cash

    allocations = []
    raw_orders = []

    for target in targets:
        scope_type = (target.get("scope_type") or "MARKET").upper()
        scope_value = (target.get("scope_value") or "").strip().upper()
        target_pct = float(target.get("target_percent") or 0.0)
        target_value = total_value * target_pct / 100.0

        # Identifica i titoli nel bucket
        constituents = []
        if scope_type == "MARKET":
            constituents = [h for h in portfolio if _market_of(h) == scope_value]
        elif scope_type == "TICKERS":
            ticker_set = {t.strip().upper() for t in scope_value.split(",") if t.strip()}
            constituents = [h for h in portfolio if h["ticker"].upper() in ticker_set]
        # CASH -> nessun titolo costituente

        current_value = extra_cash if scope_type == "CASH" else sum(_holding_value_eur(h) for h in constituents)
        delta = target_value - current_value
        current_pct = (current_value / total_value * 100.0) if total_value > 0 else 0.0

        allocations.append({
            "id": target.get("id"),
            "name": target.get("name"),
            "scope_type": scope_type,
            "scope_value": scope_value,
            "target_percent": target_pct,
            "current_percent": round(current_pct, 2),
            "target_value": round(target_value, 2),
            "current_value": round(current_value, 2),
            "delta": round(delta, 2),
            "drift_pct": round(target_pct - current_pct, 2),
        })

        # Genera ordini distribuiti pro-quota sul bucket
        if scope_type != "CASH" and abs(delta) >= 1.0 and constituents:
            bucket_total = sum(_holding_value_eur(h) for h in constituents)
            for h in constituents:
                price = float(h.get("current_price") or 0.0)
                fx = _holding_fx_to_eur(h)
                price_eur = price * fx
                if price <= 0 or price_eur <= 0:
                    continue
                weight = (_holding_value_eur(h) / bucket_total) if bucket_total > 0 else (1.0 / len(constituents))
                leg_value_eur = delta * weight
                qty = leg_value_eur / price_eur
                if abs(qty) < 0.0001:
                    continue
                held_qty = abs(float(h.get("quantity") or 0.0))
                # Non vendere mai più di quanto posseduto (clamp per gamba;
                # il cap aggregato è applicato dopo il merge per ticker).
                if qty < 0:
                    qty = max(qty, -held_qty)
                raw_orders.append({
                    "ticker": h["ticker"],
                    "name": h["name"],
                    "allocation_name": target.get("name"),
                    "signed_quantity": qty,
                    "estimated_price": round(price, 2),
                    "currency": h.get("currency", "EUR"),
                    "fx_rate_to_eur": fx,
                    "held_quantity": held_qty,
                })

    # Consolida i duplicati da target sovrapposti (M7)
    merged_orders = _merge_rebalance_orders(raw_orders)

    total_buy_value = round(sum(o["_value_eur"] for o in merged_orders if o["side"] == "BUY"), 2)
    total_sell_value = round(sum(o["_value_eur"] for o in merged_orders if o["side"] == "SELL"), 2)
    orders = [{k: v for k, v in o.items() if k != "_value_eur"} for o in merged_orders]

    # Ordini: prima i BUY più grandi, poi i SELL
    orders.sort(key=lambda o: (o["side"] != "BUY", -o["estimated_value"]))

    covered_targets = sum(a["target_percent"] for a in allocations)

    return {
        "total_value": round(total_value, 2),
        "extra_cash": round(extra_cash, 2),
        "targets_sum_percent": round(covered_targets, 2),
        "allocations": allocations,
        "orders": orders,
        "orders_count": len(orders),
        "total_buy_value": total_buy_value,
        "total_sell_value": total_sell_value,
    }
