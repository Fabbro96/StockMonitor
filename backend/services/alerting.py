import logging
from datetime import datetime, timezone, timedelta
from sqlalchemy import func
from sqlalchemy.future import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from backend.models.settings import AlertRule
from backend.models.stock import Stock, PriceHistory
from backend.models.watchlist import WatchlistItem
from backend.models.portfolio import Holding
from backend.services.market_data import MarketDataService
from backend.services.telegram_bot import TelegramService

logger = logging.getLogger(__name__)

class AlertingService:
    _last_alert_times = {}  # dict mapping cache_key -> datetime

    async def check_alerts(self, db_session: AsyncSession):
        """
        Esegue il monitoraggio completo dei mercati:
        1. Regole Alert su variazione % giornaliera (AlertRule)
        2. Soglie di prezzo assolute su Watchlist (alert_above / alert_below)
        3. Livelli di Stop-Loss (<= -8%) e Take-Profit (>= +15%) su Holding possedute

        Salta l'intera run se nessun mercato è aperto ed esegue UN solo fetch
        prezzi in batch per tutti i ticker coinvolti (niente N chiamate esterne).
        """
        if not MarketDataService.are_any_markets_open():
            logger.info("Nessun mercato aperto: controllo alert saltato.")
            return

        telegram = TelegramService()
        now = datetime.now(timezone.utc)

        # 1. AlertRule (Variazione % giornaliera)
        rules_res = await db_session.execute(
            select(AlertRule).join(Stock).where(AlertRule.is_active == True, Stock.is_active == True).options(selectinload(AlertRule.stock))
        )
        rules = rules_res.scalars().all()

        # 2. WatchlistItem (Soglie prezzo assolute)
        wl_res = await db_session.execute(
            select(WatchlistItem).join(Stock).where(Stock.is_active == True).options(selectinload(WatchlistItem.stock))
        )
        watchlist_items = wl_res.scalars().all()

        # 3. Holding Stop-Loss / Take-Profit Monitor
        holdings_res = await db_session.execute(
            select(Holding).join(Stock).where(Stock.is_active == True).options(selectinload(Holding.stock))
        )
        holdings = holdings_res.scalars().all()

        # Prezzi: UNA sola chiamata batch per tutti i ticker della run
        stocks_by_id: dict[int, Stock] = {}
        for entity in list(rules) + list(watchlist_items) + list(holdings):
            stock = getattr(entity, "stock", None)
            if stock:
                stocks_by_id[stock.id] = stock
        if not stocks_by_id:
            return

        prices_map = await MarketDataService.fetch_batch_prices([s.ticker for s in stocks_by_id.values()])

        # Un prezzo batch MANCANTE o STALE (fallback sintetico) è trattato come assente:
        # si usa l'ultima chiusura reale dal DB (con la sua variazione reale), mai il
        # change sintetico del fallback. Se il DB non ha chiusure, il titolo viene
        # escluso dalle valutazioni (niente alert su prezzi finti).
        def _batch_entry(ticker: str) -> dict:
            return prices_map.get(ticker) or {}

        missing_ids = [
            stock_id for stock_id, stock in stocks_by_id.items()
            if not self._valid_price(_batch_entry(stock.ticker).get("close"))
            or bool(_batch_entry(stock.ticker).get("stale"))
        ]
        if missing_ids:
            db_prices = await self._last_db_prices(db_session, missing_ids)
            for stock_id in missing_ids:
                ticker = stocks_by_id[stock_id].ticker
                db_data = db_prices.get(stock_id)
                if db_data:
                    prices_map[ticker] = {
                        "close": db_data["close"],
                        "change_percent": db_data["change_percent"],
                        "stale": True,
                    }
                else:
                    prices_map.pop(ticker, None)

        def _price(ticker: str) -> float:
            try:
                return float((prices_map.get(ticker) or {}).get("close") or 0.0)
            except (TypeError, ValueError):
                return 0.0

        def _change(ticker: str) -> float:
            try:
                return float((prices_map.get(ticker) or {}).get("change_percent") or 0.0)
            except (TypeError, ValueError):
                return 0.0

        # 1. Regole Alert (variazione % giornaliera)
        for rule in rules:
            stock = rule.stock
            if not stock:
                continue

            cache_key = f"rule_{rule.id}"
            last_alert = self._last_alert_times.get(cache_key)
            if last_alert and (now - last_alert) < timedelta(hours=1):
                continue

            change_percent = _change(stock.ticker)

            trigger = False
            if rule.direction == 'UP' and change_percent >= rule.threshold_percent:
                trigger = True
            elif rule.direction == 'DOWN' and change_percent <= -rule.threshold_percent:
                trigger = True
            elif rule.direction == 'BOTH' and abs(change_percent) >= rule.threshold_percent:
                trigger = True

            if trigger:
                current_price = _price(stock.ticker)
                self._last_alert_times[cache_key] = now
                logger.info(f"Triggered AlertRule #{rule.id} per {stock.ticker}: {change_percent:+.2f}%")
                await telegram.send_alert(stock.name or stock.ticker, stock.ticker, change_percent, current_price)

        # 2. WatchlistItem (Soglie prezzo assolute)
        for item in watchlist_items:
            stock = item.stock
            if not stock:
                continue

            if not item.alert_above and not item.alert_below:
                continue

            cache_key = f"wl_{item.id}"
            last_alert = self._last_alert_times.get(cache_key)
            if last_alert and (now - last_alert) < timedelta(hours=2):
                continue

            current_price = _price(stock.ticker)
            if current_price <= 0:
                continue

            if item.alert_above and current_price >= item.alert_above:
                self._last_alert_times[cache_key] = now
                logger.info(f"Watchlist alert above superato per {stock.ticker}: {current_price} >= {item.alert_above}")
                await telegram.send_alert(stock.name or stock.ticker, stock.ticker, 0.0, current_price)
            elif item.alert_below and current_price <= item.alert_below:
                self._last_alert_times[cache_key] = now
                logger.info(f"Watchlist alert below raggiunto per {stock.ticker}: {current_price} <= {item.alert_below}")
                await telegram.send_alert(stock.name or stock.ticker, stock.ticker, 0.0, current_price)

        # 3. Holding Stop-Loss / Take-Profit Monitor
        for h in holdings:
            stock = h.stock
            if not stock or h.avg_purchase_price <= 0:
                continue

            cache_key = f"sl_tp_h_{h.id}"
            last_alert = self._last_alert_times.get(cache_key)
            if last_alert and (now - last_alert) < timedelta(hours=4):
                continue

            current_price = _price(stock.ticker)
            if current_price <= 0:
                continue

            pnl_pct = ((current_price - h.avg_purchase_price) / h.avg_purchase_price) * 100.0

            # Stop-Loss Alert a <= -8%
            if pnl_pct <= -8.0:
                self._last_alert_times[cache_key] = now
                logger.info(f"Stop-Loss triggered su {stock.ticker}: P&L {pnl_pct:.2f}%")
                await telegram.send_stop_loss_alert(
                    stock.name or stock.ticker, stock.ticker, pnl_pct, current_price, h.avg_purchase_price
                )
            # Take-Profit Alert a >= +15%
            elif pnl_pct >= 15.0:
                self._last_alert_times[cache_key] = now
                logger.info(f"Take-Profit raggiunto su {stock.ticker}: P&L +{pnl_pct:.2f}%")
                await telegram.send_take_profit_alert(
                    stock.name or stock.ticker, stock.ticker, pnl_pct, current_price, h.avg_purchase_price
                )

    @staticmethod
    def _valid_price(value) -> bool:
        try:
            return value is not None and float(value) > 0
        except (TypeError, ValueError):
            return False

    @staticmethod
    async def _last_db_prices(db_session: AsyncSession, stock_ids: list[int]) -> dict[int, dict]:
        """
        Ultimi due close reali dal DB per gli stock indicati (una sola query, window function).
        Ritorna {stock_id: {"close": ultimo_close, "change_percent": variazione % reale vs precedente}}.
        """
        if not stock_ids:
            return {}
        row_number = func.row_number().over(
            partition_by=PriceHistory.stock_id,
            order_by=PriceHistory.timestamp.desc()
        ).label("rn")
        ranked = (
            select(
                PriceHistory.stock_id.label("stock_id"),
                PriceHistory.close.label("close"),
                row_number
            )
            .where(PriceHistory.stock_id.in_(stock_ids), PriceHistory.close.isnot(None))
            .subquery()
        )
        res = await db_session.execute(
            select(ranked.c.stock_id, ranked.c.close)
            .where(ranked.c.rn <= 2)
            .order_by(ranked.c.stock_id, ranked.c.rn)
        )
        closes_by_stock: dict[int, list[float]] = {}
        for stock_id, close in res.all():
            closes_by_stock.setdefault(stock_id, []).append(float(close))

        out: dict[int, dict] = {}
        for stock_id, closes in closes_by_stock.items():
            if not closes:
                continue
            last = closes[0]
            prev = closes[1] if len(closes) > 1 else None
            change_percent = 0.0
            if prev:
                change_abs = round(last - prev, 3)
                change_percent = round((change_abs / prev) * 100, 2)
            out[stock_id] = {"close": last, "change_percent": change_percent}
        return out
