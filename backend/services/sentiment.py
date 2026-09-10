import logging
import asyncio
import time
import xml.etree.ElementTree as ET
from collections import OrderedDict
from datetime import datetime, timezone
import httpx
import yfinance as yf
from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from backend.models.stock import Stock
from backend.models.sentiment import Sentiment
from backend.services.market_data import get_yf_session, run_blocking_yf

logger = logging.getLogger(__name__)

# Cache TTL in-process dei contesti (Yahoo + Google + Reddit) per ticker:
# evita che l'advisor ripeta le stesse 3 fonti a ogni generazione di consigli.
_CONTEXT_CACHE_TTL = 2700.0  # 45 minuti
_CONTEXT_CACHE_MAX_ENTRIES = 256
_CONTEXT_CACHE: OrderedDict[str, tuple[list[dict], float]] = OrderedDict()

# Client HTTP condiviso e riusato da Google News e Reddit (timeout esplicito).
_HTTP_TIMEOUT = 8.0
_http_client: httpx.AsyncClient | None = None


def _get_http_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None or _http_client.is_closed:
        _http_client = httpx.AsyncClient(
            timeout=httpx.Timeout(_HTTP_TIMEOUT),
            limits=httpx.Limits(max_connections=8, max_keepalive_connections=4),
            headers={"User-Agent": "Mozilla/5.0 (StockMonitor/1.0)"}
        )
    return _http_client


async def close_shared_http_client() -> None:
    """Chiude il client HTTP condiviso, se aperto.

    Idempotente e best-effort: non solleva eccezioni, così può essere invocata
    in sicurezza nello shutdown dell'app (lifespan) anche più volte o quando
    il client non è mai stato creato.
    """
    global _http_client
    client = _http_client
    _http_client = None
    if client is None:
        return
    try:
        await client.aclose()
    except Exception as e:
        logger.debug(f"Chiusura client HTTP condiviso fallita (ignorata): {e}")


class SentimentService:
    """
    Servizio di Sentiment e Notizie multi-fonte.
    Non richiede API key: utilizza Yahoo Finance News, Google News RSS e
    Reddit pubblico (zero-auth) per raccogliere notizie e trend in tempo reale.
    """

    MAX_CONCURRENT_STOCKS = 3

    def __init__(self):
        self._semaphore = asyncio.Semaphore(self.MAX_CONCURRENT_STOCKS)

    async def fetch_yahoo_news(self, ticker: str) -> list[dict]:
        """Recupera le ultime notizie finanziarie da Yahoo Finance (gratuito, zero auth)."""
        def _get_news():
            try:
                stock = yf.Ticker(ticker, session=get_yf_session())
                raw_news = stock.news or []
                news_list = []
                for item in raw_news[:5]:
                    title = item.get("title") or (item.get("content", {}).get("title") if isinstance(item.get("content"), dict) else "")
                    publisher = item.get("publisher") or (item.get("content", {}).get("provider", {}).get("displayName") if isinstance(item.get("content"), dict) else "")
                    if title:
                        news_list.append({
                            "title": title,
                            "source": f"Yahoo ({publisher})" if publisher else "Yahoo Finance",
                            "type": "news"
                        })
                return news_list
            except Exception as e:
                logger.debug(f"Errore recupero Yahoo News per {ticker}: {e}")
                return []

        try:
            return await run_blocking_yf(_get_news, timeout=6.0)
        except Exception as e:
            logger.debug(f"Timeout recupero Yahoo News per {ticker}: {e}")
            return []

    async def fetch_google_news_rss(self, ticker: str, stock_name: str) -> list[dict]:
        """Recupera le ultime notizie da Google News RSS (gratuito, zero auth)."""
        clean_ticker = ticker.split(".")[0]
        query = f"{clean_ticker} {stock_name} stock".replace(" ", "+")
        url = f"https://news.google.com/rss/search?q={query}&hl=it&gl=IT&ceid=IT:it"

        try:
            client = _get_http_client()
            resp = await client.get(url, timeout=_HTTP_TIMEOUT)
            if resp.status_code != 200:
                return []

            root = ET.fromstring(resp.text)
            items = root.findall(".//item")
            results = []
            for item in items[:4]:
                title_elem = item.find("title")
                source_elem = item.find("source")
                if title_elem is not None and title_elem.text:
                    source_name = source_elem.text if source_elem is not None else "Google News"
                    results.append({
                        "title": title_elem.text,
                        "source": f"News ({source_name})",
                        "type": "news"
                    })
            return results
        except Exception as e:
            logger.debug(f"Errore recupero Google News per {ticker}: {e}")
            return []

    async def fetch_public_reddit_discussions(self, ticker: str, stock_name: str) -> list[dict]:
        """Recupera discussioni da Reddit tramite endpoint JSON pubblico (zero chiavi API)."""
        clean_ticker = ticker.split(".")[0]
        url = f"https://www.reddit.com/r/stocks+investing+wallstreetbets/search.json?q={clean_ticker}&sort=new&limit=5&restrict_sr=1"
        try:
            client = _get_http_client()
            resp = await client.get(url, timeout=_HTTP_TIMEOUT)
            if resp.status_code != 200:
                return []
            data = resp.json()
            children = data.get("data", {}).get("children", [])
            results = []
            for child in children:
                post = child.get("data", {})
                title = post.get("title")
                sub = post.get("subreddit")
                score = post.get("score", 0)
                if title:
                    results.append({
                        "title": title,
                        "source": f"Reddit r/{sub} (upvotes: {score})",
                        "type": "social",
                        "score": score
                    })
            return results
        except Exception as e:
            logger.debug(f"Errore recupero Reddit pubblico per {ticker}: {e}")
            return []

    @staticmethod
    def _cache_context(cache_key: str, combined: list[dict], now_ts: float) -> None:
        if not combined:
            return  # Non cachare risultati vuoti: permette di ritentare le fonti
        _CONTEXT_CACHE[cache_key] = (combined, now_ts)
        while len(_CONTEXT_CACHE) > _CONTEXT_CACHE_MAX_ENTRIES:
            _CONTEXT_CACHE.popitem(last=False)

    async def get_combined_market_context(self, ticker: str, stock_name: str) -> list[dict]:
        """Aggrega notizie e discussioni da tutte le fonti disponibili in parallelo.

        I risultati per ticker sono cachati in-process per 45 minuti, così l'advisor
        non ripete le stesse 3 richieste esterne a ogni ciclo di generazione.
        """
        cache_key = (ticker or "").strip().upper()
        now_ts = time.time()
        cached = _CONTEXT_CACHE.get(cache_key)
        if cached and (now_ts - cached[1] < _CONTEXT_CACHE_TTL):
            return list(cached[0])

        tasks = [
            self.fetch_yahoo_news(ticker),
            self.fetch_google_news_rss(ticker, stock_name),
            self.fetch_public_reddit_discussions(ticker, stock_name)
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        combined = []
        for res in results:
            if isinstance(res, list):
                combined.extend(res)

        self._cache_context(cache_key, combined, time.time())
        return list(combined)

    async def _analyze_single_stock(self, stock: Stock) -> Sentiment | None:
        try:
            async with self._semaphore:
                context_items = await self.get_combined_market_context(stock.ticker, stock.name or stock.ticker)

            # Calcolo sentiment basico su polarità parole chiave (il giudizio avanzato lo farà Gemini)
            positive_keywords = ['record', 'crescita', 'buy', 'upgrade', 'profit', 'rialzo', 'utile', 'dividendo', 'gain', 'bullish']
            negative_keywords = ['crollo', 'perdita', 'downgrade', 'sell', 'calo', 'crisi', 'inflazione', 'bearish', 'warning']

            pos_count = 0
            neg_count = 0
            titles_sample = []

            for item in context_items:
                text_lower = item['title'].lower()
                titles_sample.append(item['title'])
                if any(k in text_lower for k in positive_keywords):
                    pos_count += 1
                if any(k in text_lower for k in negative_keywords):
                    neg_count += 1

            total = max(pos_count + neg_count, 1)
            score = (pos_count - neg_count) / total
            score = round(max(min(score, 1.0), -1.0), 2)

            summary = f"Trovate {len(context_items)} notizie/discussioni su Yahoo, Google e Reddit"
            if titles_sample:
                summary += f": {titles_sample[0]}"

            return Sentiment(
                stock_id=stock.id,
                timestamp=datetime.now(timezone.utc),
                score=score,
                source='multi-source (yahoo/google/reddit)',
                summary=summary[:250]
            )
        except Exception as e:
            logger.error(f"Errore durante l'analisi del sentiment per {stock.ticker}: {e}")
            return None

    async def analyze_all_stocks(self, db_session: AsyncSession):
        """Job periodico per raccogliere news e aggiornare il sentiment per tutti i titoli attivi.

        Le analisi girano in parallelo con concorrenza limitata (semaforo, max 3 stock).
        """
        result = await db_session.execute(select(Stock).where(Stock.is_active == True))
        stocks = result.scalars().all()

        results = await asyncio.gather(
            *(self._analyze_single_stock(stock) for stock in stocks),
            return_exceptions=True
        )

        for stock, res in zip(stocks, results):
            if isinstance(res, Sentiment):
                db_session.add(res)
            elif isinstance(res, Exception):
                logger.error(f"Errore durante l'analisi del sentiment per {stock.ticker}: {res}")

        await db_session.commit()
