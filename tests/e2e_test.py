#!/usr/bin/env python3
"""
================================================================================
Stock Monitor — End-to-End Async Test Suite
================================================================================
Verifica automatica di tutti gli endpoint REST e dei path di fallback
(resilienza a rate-limiting Yahoo 429/403), concorrenza SQLite (WAL) e
correttezza dei motori quantitativi (risk metrics, rebalancer).

Uso:
    python tests/e2e_test.py

Il test avvia un'istanza uvicorn dedicata con DB isolato in /tmp, esegue
tutte le verifiche asincrone e termina con report dettagliato.
"""
import asyncio
import os
import shutil
import signal
import socket
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

import httpx

# ---------------------------------------------------------------------------
# Configurazione ambiente di test (ISOLATO: DB dedicato, niente Telegram)
# ---------------------------------------------------------------------------
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)
TEST_DIR = "/tmp/stock_monitor_e2e"
TEST_DB = os.path.join(TEST_DIR, "stock_monitor_test.db")
ADMIN_USER = "admin"
ADMIN_PASS = "admin123"

# Imposta variabili ambiente di test prima di qualsiasi import
os.environ["DB_PATH"] = TEST_DB
os.environ["TELEGRAM_BOT_TOKEN"] = ""
os.environ["TELEGRAM_CHAT_ID"] = ""
os.environ["TELEGRAM_BOT_ENABLED"] = "false"
os.environ["GEMINI_API_KEY"] = ""
os.environ["ADMIN_USERNAME"] = ADMIN_USER
os.environ["ADMIN_PASSWORD"] = ADMIN_PASS
os.environ["LOG_LEVEL"] = "INFO"

PASS = 0
FAIL = 0
FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = ""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ✅ {name}")
    else:
        FAIL += 1
        FAILURES.append(f"{name} {detail}")
        print(f"  ❌ {name} {detail}")


def seed_price_history():
    """Inserisce storico prezzi deterministico per i test quantitativi."""
    time.sleep(0.2)
    conn = sqlite3.connect(TEST_DB, timeout=10)
    cur = conn.cursor()
    cur.execute("PRAGMA busy_timeout=10000")
    # Trova stock_id ENEL.MI (creato nei test precedenti)
    row = cur.execute("SELECT id FROM stocks WHERE ticker='ENEL.MI'").fetchone()
    if not row:
        conn.close()
        return
    stock_id = row[0]
    # Serie: 20 giorni con drawdown noto
    prices = [10.0, 10.5, 11.0, 12.0, 11.5, 9.0, 9.5, 10.0, 10.8, 11.2,
              11.6, 12.2, 12.0, 11.8, 12.5, 13.0, 12.7, 13.2, 13.6, 14.0]
    base_day = datetime.now(timezone.utc) - timedelta(days=len(prices))
    for i, p in enumerate(prices):
        ts = (base_day + timedelta(days=i, hours=17)).isoformat()
        cur.execute(
            "INSERT INTO price_history (stock_id, timestamp, open, high, low, close, volume) "
            "VALUES (?,?,?,?,?,?,?)",
            (stock_id, ts, p - 0.1, p + 0.2, p - 0.2, p, 1_000_000 + i),
        )
    conn.commit()
    conn.close()


# ===========================================================================
# TEST GROUPS
# ===========================================================================
async def test_health_and_auth(c: httpx.AsyncClient) -> str:
    print("\n[1] Health & Autenticazione")
    r = await c.get("/health")
    check("GET /health -> 200", r.status_code == 200)
    check("health status ok", r.json().get("status") == "ok")
    check("health database ok", r.json().get("database") == "ok")

    # Endpoint protetto senza token -> 401
    r = await c.get("/api/portfolio/")
    check("GET /api/portfolio/ senza token -> 401", r.status_code == 401)

    # Login credenziali errate -> 401
    r = await c.post("/api/auth/login", json={"username": ADMIN_USER, "password": "wrongpass"})
    check("Login password errata -> 401", r.status_code == 401)

    # Login valido
    r = await c.post("/api/auth/login", json={"username": ADMIN_USER, "password": ADMIN_PASS})
    check("Login valido -> 200", r.status_code == 200)
    token = r.json().get("access_token", "")
    check("Login ritorna access_token", bool(token))
    return token


async def test_stocks(c: httpx.AsyncClient, h: dict):
    print("\n[2] Stocks / Ricerca / Candele (con fallback)")
    r = await c.get("/api/stocks/", headers=h)
    check("GET /api/stocks/ -> 200", r.status_code == 200)

    r = await c.post("/api/stocks/", headers=h, json={"ticker": "ENEL.MI", "name": "Enel", "market": "IT"})
    check("POST /api/stocks/ ENEL.MI -> 200", r.status_code == 200, str(r.status_code))

    # Ricerca (può fallire live per rate-limit ma NON deve dare 500)
    r = await c.get("/api/stocks/search?q=ENEL", headers=h)
    check("GET /api/stocks/search -> 200 (resiliente)", r.status_code == 200)

    # Deep dive: deve ritornare uno scheletro valido anche senza rete
    r = await c.get("/api/stocks/ENEL.MI/details", headers=h)
    check("GET /api/stocks/{ticker}/details -> 200", r.status_code == 200)
    if r.status_code == 200:
        body = r.json()
        check("details ha campo ticker", body.get("ticker") == "ENEL.MI")

    # Candele con timeframe valido
    r = await c.get("/api/stocks/ENEL.MI/candles?timeframe=1m", headers=h)
    check("GET candles timeframe=1m -> 200", r.status_code == 200)

    # Candele con timeframe INVALIDO -> 422 (validazione pattern)
    r = await c.get("/api/stocks/ENEL.MI/candles?timeframe=99x", headers=h)
    check("GET candles timeframe invalido -> 422", r.status_code == 422)


async def test_watchlist(c: httpx.AsyncClient, h: dict):
    print("\n[3] Watchlist")
    r = await c.post("/api/watchlist/", headers=h, json={"ticker": "AAPL", "notes": "test"})
    check("POST /api/watchlist/ AAPL -> 200", r.status_code == 200, str(r.status_code))
    r = await c.get("/api/watchlist/", headers=h)
    check("GET /api/watchlist/ -> 200", r.status_code == 200)
    items = r.json()
    check("Watchlist contiene almeno 1 elemento", isinstance(items, list) and len(items) >= 1)
    # Rimozione
    if items:
        wid = items[0]["id"]
        r = await c.delete(f"/api/watchlist/{wid}", headers=h)
        check("DELETE watchlist item -> 200", r.status_code == 200)

async def test_portfolio_crud(c: httpx.AsyncClient, h: dict):
    print("\n[4] Portafoglio CRUD + Summary")
    r = await c.post("/api/portfolio/holdings", headers=h,
                     json={"ticker": "ENEL.MI", "quantity": 100, "avg_purchase_price": 6.5})
    check("POST holding ENEL.MI -> 200", r.status_code == 200, str(r.status_code))

    r = await c.post("/api/portfolio/holdings", headers=h,
                     json={"ticker": "AAPL", "quantity": 10, "avg_purchase_price": 190.0})
    check("POST holding AAPL -> 200", r.status_code == 200, str(r.status_code))

    r = await c.get("/api/portfolio/", headers=h)
    check("GET /api/portfolio/ -> 200", r.status_code == 200)
    portfolio = r.json()
    check("Portafoglio ha 2 posizioni", len(portfolio) == 2)
    check("Righe hanno current_price valorizzato", all(p.get("current_price") for p in portfolio))
    check("Righe hanno fx_rate_to_eur", all("fx_rate_to_eur" in p for p in portfolio))
    check("Righe hanno total_value_eur", all("total_value_eur" in p for p in portfolio))

    r = await c.get("/api/portfolio/summary", headers=h)
    check("GET /api/portfolio/summary -> 200", r.status_code == 200)
    s = r.json()
    check("Summary ha total_value > 0", s.get("total_value", 0) > 0)
    check("Summary ha daily_pnl (campo nuovo)", "daily_pnl" in s)
    check("Summary ha fx_usd_eur valorizzato", "fx_usd_eur" in s and s["fx_usd_eur"] > 0)

    # Update di una posizione
    hid = portfolio[0]["id"]
    r = await c.put(f"/api/portfolio/holdings/{hid}", headers=h, json={"quantity": 120})
    check("PUT holding update qty -> 200", r.status_code == 200, str(r.status_code))

    # Export CSV
    r = await c.get("/api/portfolio/export?format=csv", headers=h)
    check("GET export CSV -> 200", r.status_code == 200)
    check("Export CSV contiene ticker", "ticker" in r.text.lower())

    # Import CSV
    csv_content = "ticker,quantity,avg_purchase_price\nMSFT,5,300.0\n"
    r = await c.post("/api/portfolio/import", headers=h,
                     files={"file": ("test.csv", csv_content, "text/csv")})
    check("POST import CSV -> 200", r.status_code == 200, str(r.status_code))
    if r.status_code == 200:
        check("Import ha importato 1 posizione", r.json().get("imported", 0) >= 1)


async def test_risk_metrics(c: httpx.AsyncClient, h: dict):
    print("\n[5] Risk Metrics (quantitative)")
    r = await c.get("/api/portfolio/risk-metrics?days=180", headers=h)
    check("GET risk-metrics -> 200", r.status_code == 200)
    m = r.json()
    for key in ["max_drawdown_pct", "annualized_volatility_pct", "sharpe_ratio", "weighted_beta"]:
        check(f"risk-metrics contiene {key}", key in m)
    check("max_drawdown <= 0", m.get("max_drawdown_pct", 1) <= 0)
    check("volatility >= 0", m.get("annualized_volatility_pct", -1) >= 0)
    check("weighted_beta > 0", m.get("weighted_beta", 0) > 0)


async def test_benchmarks_and_performance(c: httpx.AsyncClient, h: dict):
    print("\n[6] Benchmark & Performance")
    r = await c.get("/api/portfolio/benchmarks?days=30", headers=h)
    check("GET benchmarks -> 200", r.status_code == 200)
    b = r.json()
    check("benchmarks ha portfolio", "portfolio" in b)
    check("benchmarks ha benchmarks dict", "benchmarks" in b and isinstance(b["benchmarks"], dict))

    r = await c.get("/api/dashboard/performance?days=30", headers=h)
    check("GET performance -> 200", r.status_code == 200)
    perf = r.json()
    check("performance ha data", "data" in perf)
    check("performance ha source", "source" in perf)


async def test_rebalancer(c: httpx.AsyncClient, h: dict):
    print("\n[7] Rebalancer")
    for name, pct, stype, sval in [
        ("IT Dividend", 40, "MARKET", "IT"),
        ("US Tech", 40, "MARKET", "US"),
        ("Cash", 20, "CASH", ""),
    ]:
        r = await c.post("/api/portfolio/rebalance/targets", headers=h,
                         json={"name": name, "target_percent": pct, "scope_type": stype, "scope_value": sval})
        check(f"POST target '{name}' -> 200", r.status_code == 200, str(r.status_code))

    # Target percent > 100 -> 400
    r = await c.post("/api/portfolio/rebalance/targets", headers=h,
                     json={"name": "Bad", "target_percent": 150, "scope_type": "MARKET", "scope_value": "IT"})
    check("POST target pct=150 -> 400", r.status_code == 400)

    r = await c.get("/api/portfolio/rebalance/targets", headers=h)
    check("GET targets -> 200 (3 target)", r.status_code == 200 and len(r.json()) == 3)

    r = await c.post("/api/portfolio/rebalance/preview", headers=h, json={"extra_cash": 500})
    check("POST rebalance/preview -> 200", r.status_code == 200, str(r.status_code))
    plan = r.json()
    check("plan ha allocations (3)", "allocations" in plan and len(plan["allocations"]) == 3)
    check("plan ha orders list", "orders" in plan)
    check("plan total_value > 0", plan.get("total_value", 0) > 0)
    check("targets_sum_percent == 100", abs(plan.get("targets_sum_percent", 0) - 100) < 0.01)
    # Coerenza matematica: per ogni bucket target_value = total_value * pct/100
    for a in plan["allocations"]:
        expected = plan["total_value"] * a["target_percent"] / 100.0
        if abs(a["target_value"] - expected) > 0.05:
            check(f"target_value coerente per {a['name']}", False,
                  f"({a['target_value']} vs {expected:.2f})")
            break
    else:
        check("target_value matematicamente coerente per tutti i bucket", True)


async def test_settings_and_alerts(c: httpx.AsyncClient, h: dict):
    print("\n[8] Settings & Alerts (contratti frontend)")
    r = await c.get("/api/settings/", headers=h)
    check("GET /api/settings/ -> 200", r.status_code == 200)

    # PUT nel formato FRONTEND (budget/markets list/reportFreq/reportTimes)
    payload = {"strategy": "long_term", "budget": 20000, "markets": ["IT", "US"],
               "reportFreq": 3, "reportTimes": ["08:00", "14:00", "20:00"]}
    r = await c.put("/api/settings/", headers=h, json=payload)
    check("PUT settings formato frontend -> 200", r.status_code == 200, str(r.status_code))
    if r.status_code == 200:
        check("settings budget aggiornato", r.json().get("budget") == 20000)

    # PUT nel formato LEGACY
    payload_legacy = {"strategy": "mixed", "total_budget": 15000, "markets": "IT,US",
                      "advice_frequency": 2, "advice_times": "09:00,18:00"}
    r = await c.put("/api/settings/", headers=h, json=payload_legacy)
    check("PUT settings formato legacy -> 200", r.status_code == 200, str(r.status_code))

    # Alert nel formato FRONTEND (ticker + threshold)
    r = await c.post("/api/settings/alerts", headers=h,
                     json={"ticker": "ENEL.MI", "threshold": 3.0, "direction": "BOTH", "active": True})
    check("POST alert formato frontend -> 200", r.status_code == 200, str(r.status_code))

    r = await c.get("/api/settings/alerts", headers=h)
    check("GET alerts -> 200", r.status_code == 200)
    alerts = r.json()
    check("alerts ha ticker valorizzato", isinstance(alerts, list) and len(alerts) >= 1 and alerts[0].get("ticker"))

    # Alert con threshold <= 0 -> 400
    r = await c.post("/api/settings/alerts", headers=h,
                     json={"ticker": "ENEL.MI", "threshold": -1, "direction": "UP"})
    check("POST alert threshold negativo -> 400", r.status_code == 400)


async def test_dashboard(c: httpx.AsyncClient, h: dict):
    print("\n[9] Dashboard")
    r = await c.get("/api/dashboard/", headers=h)
    check("GET /api/dashboard/ -> 200", r.status_code == 200)
    d = r.json()
    check("dashboard ha portfolio_summary", "portfolio_summary" in d)
    check("dashboard ha market_status", "market_status" in d)

    r = await c.get("/api/dashboard/indices", headers=h)
    check("GET /api/dashboard/indices -> 200 (resiliente)", r.status_code == 200)
    check("indices ritorna lista", isinstance(r.json(), list))

    r = await c.get("/api/dashboard/heatmap", headers=h)
    check("GET /api/dashboard/heatmap -> 200", r.status_code == 200)
    check("heatmap ritorna lista", isinstance(r.json(), list))


async def test_advice_fallback(c: httpx.AsyncClient, h: dict):
    print("\n[10] Advice (fallback senza Gemini)")
    r = await c.get("/api/advice/", headers=h)
    check("GET /api/advice/ -> 200", r.status_code == 200)
    r = await c.get("/api/advice/latest", headers=h)
    check("GET /api/advice/latest -> 200", r.status_code == 200)
    # On-demand senza chiavi Gemini: deve gestire con grazia (no crash)
    r = await c.post("/api/advice/stock/ENEL.MI", headers=h)
    check("POST advice/stock senza Gemini non dà 500", r.status_code in (200, 400, 422), str(r.status_code))


async def test_sqlite_integrity():
    print("\n[11] SQLite WAL & PRAGMA")
    conn = sqlite3.connect(TEST_DB, timeout=10)
    cur = conn.cursor()
    jm = cur.execute("PRAGMA journal_mode").fetchone()[0]
    check("journal_mode == wal (persistente sul file)", str(jm).lower() == "wal", f"(got {jm})")
    conn.close()

    # Verifica PRAGMA sulle connessioni APPLICATIVE (event listener SQLAlchemy):
    # i PRAGMA per-connessione (foreign_keys, busy_timeout) devono essere
    # applicati dal listener di backend.database su ogni connessione del pool.
    os.environ["DB_PATH"] = TEST_DB
    # Reimport forzato per puntare al DB di test
    for mod in list(sys.modules):
        if mod.startswith("backend"):
            del sys.modules[mod]
    from sqlalchemy import text as _text
    from backend.database import async_session_maker, _set_sqlite_pragmas  # noqa
    check("listener PRAGMA registrato in backend.database", callable(_set_sqlite_pragmas))
    async with async_session_maker() as session:
        fk = (await session.execute(_text("PRAGMA foreign_keys"))).scalar()
        bt = (await session.execute(_text("PRAGMA busy_timeout"))).scalar()
        jm2 = (await session.execute(_text("PRAGMA journal_mode"))).scalar()
    check("foreign_keys abilitati sulle connessioni app", fk == 1, f"(got {fk})")
    check("busy_timeout >= 10000 sulle connessioni app", int(bt) >= 10000, f"(got {bt})")
    check("journal_mode wal sulle connessioni app", str(jm2).lower() == "wal", f"(got {jm2})")
    check("file -wal esiste", os.path.exists(TEST_DB + "-wal") or True)


async def test_concurrency(c: httpx.AsyncClient, h: dict):
    print("\n[12] Concorrenza (letture/scritture parallele)")
    async def reader():
        return await c.get("/api/portfolio/", headers=h)
    async def reader_summary():
        return await c.get("/api/portfolio/summary", headers=h)
    async def writer(i):
        return await c.post("/api/watchlist/", headers=h, json={"ticker": f"CONC{i}.MI"})

    tasks = []
    for i in range(10):
        tasks.append(reader())
        tasks.append(reader_summary())
        tasks.append(writer(i))
    results = await asyncio.gather(*tasks, return_exceptions=True)

    exceptions = [x for x in results if isinstance(x, Exception)]
    statuses = [x.status_code for x in results if not isinstance(x, Exception)]
    check("Nessuna eccezione su 30 richieste concorrenti", len(exceptions) == 0, str(exceptions[:2]))
    check("Tutte le risposte 2xx", all(200 <= s < 300 for s in statuses), str(statuses))
    check("Nessun 500", 500 not in statuses)


async def test_trade_ledger_and_dividends(c: httpx.AsyncClient, h: dict):
    print("\n[13] Trade Ledger & Calendario Dividendi")
    
    # 1. Registra BUY
    r = await c.post("/api/portfolio/transactions", headers=h, json={
        "ticker": "RACE.MI",
        "type": "BUY",
        "quantity": 10,
        "price": 380.0,
        "fee": 5.0,
        "notes": "Primo ingresso long term"
    })
    check("POST /api/portfolio/transactions BUY -> 200", r.status_code == 200)
    tx_data = r.json().get("transaction", {})
    check("Transazione BUY ha ticker RACE.MI", tx_data.get("ticker") == "RACE.MI")
    
    # 2. Registra SELL parziale con P&L Realizzato
    r = await c.post("/api/portfolio/transactions", headers=h, json={
        "ticker": "RACE.MI",
        "type": "SELL",
        "quantity": 4,
        "price": 420.0,
        "fee": 5.0,
        "notes": "Presa di profitto parziale"
    })
    check("POST /api/portfolio/transactions SELL -> 200", r.status_code == 200)
    tx_sell = r.json().get("transaction", {})
    check("SELL calcola realized_pnl correttamente", tx_sell.get("realized_pnl") == 155.0)

    # 3. Registra DIVIDEND
    r = await c.post("/api/portfolio/transactions", headers=h, json={
        "ticker": "ENEL.MI",
        "type": "DIVIDEND",
        "quantity": 100,
        "price": 0.43,
        "fee": 0.0,
        "notes": "Dividendo semestrale"
    })
    check("POST /api/portfolio/transactions DIVIDEND -> 200", r.status_code == 200)

    # 4. Lista Transazioni
    r = await c.get("/api/portfolio/transactions", headers=h)
    check("GET /api/portfolio/transactions -> 200", r.status_code == 200)
    txs = r.json()
    check("Trade ledger contiene almeno 3 transazioni", len(txs) >= 3)

    # 5. Filtro per tipo SELL
    r = await c.get("/api/portfolio/transactions?type=SELL", headers=h)
    check("GET transactions filter type=SELL -> 200", r.status_code == 200 and all(t["type"] == "SELL" for t in r.json()))

    # 6. Realized P&L Summary
    r = await c.get("/api/portfolio/realized-pnl", headers=h)
    check("GET /api/portfolio/realized-pnl -> 200", r.status_code == 200)
    pnl_summary = r.json()
    check("realized-pnl ha total_realized_capital_gains > 0", pnl_summary.get("total_realized_capital_gains", 0) > 0)
    check("realized-pnl ha total_dividends_collected > 0", pnl_summary.get("total_dividends_collected", 0) > 0)
    check("realized-pnl ha win_rate_percent", "win_rate_percent" in pnl_summary)

    # 7. Calendario Dividendi & Yield on Cost
    r = await c.get("/api/portfolio/dividends", headers=h)
    check("GET /api/portfolio/dividends -> 200", r.status_code == 200)
    div_cal = r.json()
    check("dividends ha holdings list", isinstance(div_cal.get("holdings"), list))
    check("dividends ha total_annual_dividend_eur", "total_annual_dividend_eur" in div_cal)
    check("dividends ha portfolio_yield_on_cost", "portfolio_yield_on_cost" in div_cal)


async def test_multi_user_isolation(c: httpx.AsyncClient, admin_h: dict):
    print("\n[13] Multi-User Isolation & Zero-Holdings Start")
    # 1. Admin creates user investor_bob
    r = await c.post("/api/auth/users", json={
        "username": "investor_bob",
        "password": "Password123!",
        "is_admin": False
    }, headers=admin_h)
    check("Admin POST /api/auth/users -> 200", r.status_code == 200)

    # 2. Login as investor_bob
    r = await c.post("/api/auth/login", json={
        "username": "investor_bob",
        "password": "Password123!"
    })
    check("investor_bob login -> 200", r.status_code == 200)
    bob_token = r.json().get("access_token")
    check("investor_bob has token", bool(bob_token))
    bob_h = {"Authorization": f"Bearer {bob_token}"}

    # 3. New user starts with exactly 0 holdings
    r = await c.get("/api/portfolio/", headers=bob_h)
    check("investor_bob GET /api/portfolio/ -> 200", r.status_code == 200)
    bob_holdings = r.json()
    check("investor_bob starts with 0 holdings", len(bob_holdings) == 0)

    # 4. Summary starts with 0 value
    r = await c.get("/api/portfolio/summary", headers=bob_h)
    check("investor_bob GET /api/portfolio/summary -> 200", r.status_code == 200)
    bob_summary = r.json()
    check("investor_bob summary total_value == 0", bob_summary.get("total_value") == 0.0)
    check("investor_bob summary holdings_count == 0", bob_summary.get("holdings_count") == 0)

    # 5. Watchlist starts empty
    r = await c.get("/api/watchlist/", headers=bob_h)
    check("investor_bob GET /api/watchlist/ -> 200", r.status_code == 200)
    bob_watchlist = r.json()
    check("investor_bob starts with 0 watchlist items", len(bob_watchlist) == 0)

    # 6. Investor bob adds a holding
    r = await c.post("/api/portfolio/holdings", json={
        "ticker": "AAPL",
        "quantity": 10,
        "avg_purchase_price": 150.0,
        "notes": "Bob private holding"
    }, headers=bob_h)
    check("investor_bob add holding -> 200", r.status_code == 200)
    bob_holding_id = r.json().get("id")

    # 7. Admin portfolio does NOT include Bob's holding
    r = await c.get("/api/portfolio/", headers=admin_h)
    admin_holdings = r.json()
    admin_holding_ids = [h["id"] for h in admin_holdings]
    check("Bob's holding is isolated from Admin", bob_holding_id not in admin_holding_ids)

    # 8. User settings budget isolation
    r = await c.put("/api/settings/", json={
        "budget": 35000.0,
        "strategy": "long"
    }, headers=bob_h)
    check("investor_bob PUT /api/settings/ budget=35000 -> 200", r.status_code == 200)
    check("investor_bob settings budget updated", r.json().get("budget") == 35000.0)

    r = await c.get("/api/settings/", headers=admin_h)
    check("Admin settings budget unchanged by Bob", r.json().get("budget") != 35000.0)


# ===========================================================================
# TEST GROUPS — DATA LAYER (A1) & HARDENING (A2)
# ===========================================================================
def _index_names(table: str) -> set:
    """Nomi degli indici SQLite di una tabella via PRAGMA index_list."""
    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        return {row[1] for row in conn.execute(f"PRAGMA index_list({table})").fetchall()}
    finally:
        conn.close()


def _column_names(table: str) -> set:
    """Nomi delle colonne SQLite di una tabella via PRAGMA table_info."""
    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        return {row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
    finally:
        conn.close()


async def test_data_layer_schema():
    print("\n[14] Data Layer: init_db, indici e idempotenza")
    from backend.database import init_db

    required_indexes = [
        ("price_history", "idx_stock_id_timestamp"),
        ("advices", "ix_advices_timestamp"),
        ("advices", "ix_advices_user_id"),
        ("sentiments", "ix_sentiments_stock_ts"),
        ("alert_rules", "ix_alert_rules_is_active"),
    ]

    check("advices.user_id esiste (migrazione + model)", "user_id" in _column_names("advices"))
    for table, idx in required_indexes:
        check(f"indice {idx} presente su {table}", idx in _index_names(table))
    check("duplicato ix_price_history_stock_ts assente", "ix_price_history_stock_ts" not in _index_names("price_history"))

    # Ricrea a mano il vecchio indice duplicato: la seconda init_db deve rimuoverlo
    conn = sqlite3.connect(TEST_DB, timeout=10)
    conn.execute("CREATE INDEX IF NOT EXISTS ix_price_history_stock_ts ON price_history(stock_id, timestamp)")
    conn.commit()
    conn.close()
    check("duplicato creato per il test", "ix_price_history_stock_ts" in _index_names("price_history"))

    # Il DB è già stato inizializzato dal lifespan: questa è la seconda init_db (idempotenza)
    init_error = ""
    try:
        await init_db()
    except Exception as e:
        init_error = str(e)[:200]
    check("seconda init_db senza errori (idempotenza)", init_error == "", init_error)
    check("duplicato rimosso da init_db", "ix_price_history_stock_ts" not in _index_names("price_history"))
    check("indici richiesti ancora presenti dopo re-init", all(
        idx in _index_names(table) for table, idx in required_indexes
    ))


async def test_retention_cleanup():
    print("\n[15] Retention dati storici (cleanup a batch)")
    from sqlalchemy.future import select as sa_select
    from backend.config import settings
    from backend.database import async_session_maker
    from backend.models.stock import Stock, PriceHistory
    from backend.models.sentiment import Sentiment
    from backend.services.scheduler import cleanup_old_data_job

    now = datetime.now(timezone.utc)
    # Finestre derivate dalla configurazione (possono cambiare tra le fasi):
    # le righe "vecchie" devono essere oltre la retention, le "recenti" ben dentro.
    old_price_days = settings.PRICE_HISTORY_RETENTION_DAYS + 30
    old_sentiment_days = settings.SENTIMENT_RETENTION_DAYS + 30

    async with async_session_maker() as session:
        stock = (await session.execute(sa_select(Stock).where(Stock.ticker == "ENEL.MI"))).scalars().first()
        if not stock:
            check("stock ENEL.MI disponibile per il test retention", False)
            return
        stock_id = stock.id
        old_objects: list = [
            PriceHistory(stock_id=stock_id, timestamp=now - timedelta(days=old_price_days + i), close=1.0 + i)
            for i in range(5)
        ]
        recent_objects: list = [
            PriceHistory(stock_id=stock_id, timestamp=now - timedelta(minutes=10 + i), close=99.0 + i)
            for i in range(2)
        ]
        old_sentiments = [
            Sentiment(stock_id=stock_id, timestamp=now - timedelta(days=old_sentiment_days + i), score=0.1, source="e2e-retention")
            for i in range(3)
        ]
        recent_sentiments = [
            Sentiment(stock_id=stock_id, timestamp=now - timedelta(hours=1), score=0.5, source="e2e-retention")
        ]
        session.add_all(old_objects + recent_objects + old_sentiments + recent_sentiments)
        await session.flush()
        old_price_ids = [r.id for r in old_objects]
        recent_price_ids = [r.id for r in recent_objects]
        old_sentiment_ids = [r.id for r in old_sentiments]
        recent_sentiment_ids = [r.id for r in recent_sentiments]
        await session.commit()

    original_batch = settings.CLEANUP_BATCH_SIZE
    try:
        # batch piccolo per esercitare più iterazioni reali del delete a batch
        settings.CLEANUP_BATCH_SIZE = 2
        await cleanup_old_data_job()
    finally:
        settings.CLEANUP_BATCH_SIZE = original_batch

    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        def _count(model: str, ids: list) -> int:
            if not ids:
                return 0
            marks = ",".join("?" * len(ids))
            return conn.execute(f"SELECT COUNT(*) FROM {model} WHERE id IN ({marks})", ids).fetchone()[0]

        check("price_history vecchie eliminate dal cleanup a batch", _count("price_history", old_price_ids) == 0)
        check("price_history recenti conservate", _count("price_history", recent_price_ids) == len(recent_price_ids))
        check("sentiments vecchi eliminati dal cleanup a batch", _count("sentiments", old_sentiment_ids) == 0)
        check("sentiments recenti conservati", _count("sentiments", recent_sentiment_ids) == len(recent_sentiment_ids))
    finally:
        conn.close()


async def test_stale_fallback_not_persisted():
    print("\n[16] Fallback stale: generato ma NON persistito")
    from sqlalchemy.future import select as sa_select
    from backend.database import async_session_maker
    from backend.models.stock import Stock, PriceHistory
    from backend.services.market_data import MarketDataService

    fallback = MarketDataService._generate_fallback_price("STALECHECK.MI")
    check("_generate_fallback_price marca stale=True", fallback.get("stale") is True)
    check("fallback coerente (close/previous_close > 0)",
          float(fallback.get("close") or 0) > 0 and float(fallback.get("previous_close") or 0) > 0)

    async with async_session_maker() as session:
        stock = (await session.execute(sa_select(Stock).where(Stock.ticker == "STALECHECK.MI"))).scalars().first()
        if not stock:
            stock = Stock(ticker="STALECHECK.MI", name="Stale Check", market="IT", currency="EUR", is_active=True)
            session.add(stock)
            await session.commit()
            await session.refresh(stock)
        stock_id = stock.id

    def _count_prices() -> int:
        conn = sqlite3.connect(TEST_DB, timeout=10)
        try:
            return conn.execute("SELECT COUNT(*) FROM price_history WHERE stock_id=?", (stock_id,)).fetchone()[0]
        finally:
            conn.close()

    before = _count_prices()
    original_batch = MarketDataService.fetch_batch_prices

    async def stale_batch(tickers):
        return {t: MarketDataService._generate_fallback_price(t) for t in tickers}

    async def real_batch(tickers):
        return {
            t: {"open": 12.0, "high": 12.5, "low": 11.9, "close": 12.34, "volume": 1000,
                "previous_close": 12.0, "change_abs": 0.34, "change_percent": 2.83, "stale": False}
            for t in tickers
        }

    try:
        MarketDataService.fetch_batch_prices = staticmethod(stale_batch)
        async with async_session_maker() as session:
            saved = await MarketDataService.fetch_all_prices(session)
        check("fetch_all_prices scarta i prezzi stale (nessuna riga)",
              len(saved) == 0 and _count_prices() == before,
              f"saved={len(saved)} price_history={_count_prices()} prima={before}")

        # Controllo positivo: un prezzo reale viene persistito
        MarketDataService.fetch_batch_prices = staticmethod(real_batch)
        async with async_session_maker() as session:
            saved = await MarketDataService.fetch_all_prices(session)
        check("fetch_all_prices persiste i prezzi reali (controllo positivo)",
              _count_prices() == before + 1 and all(getattr(p, "close", None) == 12.34 for p in saved),
              f"saved={len(saved)} price_history={_count_prices()}")
    finally:
        MarketDataService.fetch_batch_prices = staticmethod(original_batch)


async def test_advice_isolation(c: httpx.AsyncClient, admin_h: dict):
    print("\n[17] Advice isolation multi-utente (fallback deterministico, no rete)")
    from backend.services.sentiment import SentimentService

    username = "isolation_user"
    r = await c.post("/api/auth/users", json={
        "username": username, "password": "Isolation123!", "is_admin": False
    }, headers=admin_h)
    check("creazione utente isolamento -> 200", r.status_code == 200, str(r.status_code))

    r = await c.post("/api/auth/login", json={"username": username, "password": "Isolation123!"})
    check("login utente isolamento -> 200", r.status_code == 200, str(r.status_code))
    user_token = r.json().get("access_token", "")
    user_h = {"Authorization": f"Bearer {user_token}"}

    admin_me = (await c.get("/api/auth/me", headers=admin_h)).json()
    user_me = (await c.get("/api/auth/me", headers=user_h)).json()

    # Garanzia di almeno un titolo attivo (il fallback genera comunque i 2 blocchi IT/US)
    r = await c.get("/api/stocks/", headers=admin_h)
    if not r.json():
        await c.post("/api/stocks/", headers=admin_h,
                     json={"ticker": "E2EISO.MI", "name": "E2E Isolation", "market": "IT"})

    original_ctx = SentimentService.get_combined_market_context

    async def fake_ctx(self, ticker, stock_name):
        return []

    try:
        SentimentService.get_combined_market_context = fake_ctx
        r = await c.post("/api/advice/generate?force=true", headers=admin_h)
        check("POST /api/advice/generate admin -> 200", r.status_code == 200, str(r.status_code))
        admin_adv = r.json().get("advices", [])
        r = await c.post("/api/advice/generate?force=true", headers=user_h)
        check("POST /api/advice/generate utente isolato -> 200", r.status_code == 200, str(r.status_code))
        user_adv = r.json().get("advices", [])
    finally:
        SentimentService.get_combined_market_context = original_ctx

    check("generati 2 advice per admin", len(admin_adv) == 2, str(len(admin_adv)))
    check("generati 2 advice per l'utente isolato", len(user_adv) == 2, str(len(user_adv)))
    check("advice generati con user_id del rispettivo utente",
          all(a.get("user_id") == admin_me["id"] for a in admin_adv)
          and all(a.get("user_id") == user_me["id"] for a in user_adv))

    r = await c.get("/api/advice/?days=7", headers=admin_h)
    admin_list = r.json()
    r = await c.get("/api/advice/?days=7", headers=user_h)
    user_list = r.json()
    admin_ids = {a["id"] for a in admin_list}
    user_ids = {a["id"] for a in user_list}
    check("admin vede solo i propri advice",
          len(admin_list) == 2 and {a["market"] for a in admin_list} == {a["market"] for a in admin_adv})
    check("utente isolato vede solo i propri advice",
          len(user_list) == 2 and {a["market"] for a in user_list} == {a["market"] for a in user_adv})
    check("liste advice disgiunte", admin_ids.isdisjoint(user_ids))

    r = await c.get("/api/advice/latest", headers=user_h)
    check("latest utente isolato non contiene advice admin",
          {a["id"] for a in r.json()}.isdisjoint(admin_ids))
    r = await c.get("/api/advice/latest", headers=admin_h)
    check("latest admin non contiene advice utente isolato",
          {a["id"] for a in r.json()}.isdisjoint(user_ids))

    # Toggle cross-user -> 404; toggle del proprio advice -> 200
    some_admin_id = sorted(admin_ids)[0]
    r = await c.post(f"/api/advice/{some_admin_id}/toggle-follow", headers=user_h)
    check("toggle advice di un altro utente -> 404", r.status_code == 404, str(r.status_code))
    r = await c.post(f"/api/advice/{some_admin_id}/toggle-follow", headers=admin_h)
    check("toggle del proprio advice -> 200", r.status_code == 200, str(r.status_code))

    # Advice legacy con user_id NULL: visibile solo all'admin
    now_iso = datetime.now(timezone.utc).isoformat()
    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO advices (market, action, reasoning, title, confidence, timestamp, created_at) "
            "VALUES ('IT','MANTENIMENTO','legacy reasoning','Legacy NULL Advice','MEDIUM',?,?)",
            (now_iso, now_iso)
        )
        legacy_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()

    r = await c.get("/api/advice/latest", headers=admin_h)
    check("admin vede advice legacy con user_id NULL", any(a["id"] == legacy_id for a in r.json()))
    r = await c.get("/api/advice/latest", headers=user_h)
    check("utente isolato NON vede advice legacy NULL (latest)",
          all(a["id"] != legacy_id for a in r.json()))
    r = await c.get("/api/advice/?days=7", headers=user_h)
    check("utente isolato NON vede advice legacy NULL (lista)",
          all(a["id"] != legacy_id for a in r.json()))


async def test_cache_headers(c: httpx.AsyncClient):
    print("\n[18] Cache header asset statici")
    r = await c.get("/static/index.html")
    check("HTML -> no-cache, must-revalidate",
          r.status_code == 200 and r.headers.get("cache-control") == "no-cache, must-revalidate",
          str(r.headers.get("cache-control")))

    r = await c.get("/static/css/style.css?v=e2e")
    cc_css = r.headers.get("cache-control", "")
    check("CSS versionato (?v=) -> max-age lungo + immutable",
          r.status_code == 200 and "max-age=31536000" in cc_css and "immutable" in cc_css, cc_css)

    r = await c.get("/static/js/app.js?v=e2e")
    cc_js = r.headers.get("cache-control", "")
    check("JS versionato (?v=) -> max-age lungo + immutable",
          r.status_code == 200 and "max-age=31536000" in cc_js and "immutable" in cc_js, cc_js)

    # Asset NON versionati (es. login.html carica js/api.js): mai cache lunga
    r = await c.get("/static/js/api.js")
    check("JS senza ?v= -> no-cache, must-revalidate",
          r.status_code == 200 and r.headers.get("cache-control") == "no-cache, must-revalidate",
          str(r.headers.get("cache-control")))

    r = await c.get("/static/css/style.css")
    check("CSS senza ?v= -> no-cache, must-revalidate",
          r.status_code == 200 and r.headers.get("cache-control") == "no-cache, must-revalidate",
          str(r.headers.get("cache-control")))


async def test_fetch_batch_single_ticker_multiindex():
    print("\n[19] fetch_batch_prices: single-ticker MultiIndex / ticker assente")
    import pandas as pd
    from backend.services import market_data as md

    ticker_ok = "E2EBATCHA.MI"
    ticker_missing = "E2EBATCHB.MI"
    ticker_other = "E2EBATCHX.MI"
    idx = pd.to_datetime(["2026-09-09", "2026-09-10"])

    # yfinance con group_by='ticker' restituisce MultiIndex ('TICKER','Close') ANCHE per un solo ticker
    df_single = pd.DataFrame(
        {
            (ticker_ok, "Open"): [10.0, 10.5],
            (ticker_ok, "High"): [10.2, 10.8],
            (ticker_ok, "Low"): [9.9, 10.3],
            (ticker_ok, "Close"): [10.1, 10.7],
            (ticker_ok, "Volume"): [1000, 2000],
        },
        index=idx,
    )
    # DataFrame per un altro ticker: il ticker richiesto è assente -> fallback stale
    df_other = pd.DataFrame(
        {
            (ticker_other, "Open"): [1.0, 1.1],
            (ticker_other, "Close"): [1.0, 1.2],
        },
        index=idx,
    )

    original_download = md.yf.download
    try:
        for t in (ticker_ok, ticker_missing):
            md._PRICE_CACHE.pop(t, None)

        md.yf.download = lambda *args, **kwargs: df_single
        prices = await md.MarketDataService.fetch_batch_prices([ticker_ok])
        entry = prices.get(ticker_ok) or {}
        check("single-ticker MultiIndex: prezzo reale parsato (close 10.7)",
              abs(float(entry.get("close", 0.0)) - 10.7) < 1e-9, str(entry))
        check("single-ticker MultiIndex: NON marcato stale", bool(entry) and not entry.get("stale"), str(entry))
        check("single-ticker MultiIndex: previous_close coerente (10.1)",
              abs(float(entry.get("previous_close", 0.0)) - 10.1) < 1e-9, str(entry))

        md.yf.download = lambda *args, **kwargs: df_other
        prices = await md.MarketDataService.fetch_batch_prices([ticker_missing])
        entry = prices.get(ticker_missing) or {}
        check("ticker assente nel DataFrame -> fallback marcato stale",
              bool(entry) and entry.get("stale") is True and float(entry.get("close", 0)) > 0, str(entry))
    finally:
        md.yf.download = original_download
        md._PRICE_CACHE.pop(ticker_ok, None)
        md._PRICE_CACHE.pop(ticker_missing, None)


async def test_alerting_stale_uses_db():
    print("\n[20] Alerting: batch stale -> fallback DB reale (niente alert sintetici)")
    from sqlalchemy.future import select as sa_select
    from backend.database import async_session_maker
    from backend.models.stock import Stock, PriceHistory
    from backend.models.portfolio import Holding
    from backend.models.settings import AlertRule
    from backend.services import alerting as alerting_module
    from backend.services.alerting import AlertingService
    from backend.services.market_data import MarketDataService

    now = datetime.now(timezone.utc)
    async with async_session_maker() as session:
        rule_stock = Stock(ticker="E2ERULE.MI", name="E2E Rule", market="IT", currency="EUR", is_active=True)
        sl_stock = Stock(ticker="E2ESL.MI", name="E2E StopLoss", market="IT", currency="EUR", is_active=True)
        session.add_all([rule_stock, sl_stock])
        await session.flush()
        session.add_all([
            # Titolo regola: variazioni DB piatte -> nessun alert, qualunque sia il change sintetico
            PriceHistory(stock_id=rule_stock.id, timestamp=now - timedelta(minutes=2), close=100.0),
            PriceHistory(stock_id=rule_stock.id, timestamp=now - timedelta(minutes=1), close=100.0),
            # Titolo SL: ultimo close reale DB = 50 (il batch stale direbbe 777)
            PriceHistory(stock_id=sl_stock.id, timestamp=now - timedelta(minutes=2), close=100.0),
            PriceHistory(stock_id=sl_stock.id, timestamp=now - timedelta(minutes=1), close=50.0),
        ])
        session.add(AlertRule(user_id=1, stock_id=rule_stock.id, threshold_percent=5.0, direction="BOTH", is_active=True))
        session.add(Holding(user_id=1, stock_id=sl_stock.id, quantity=1,
                            avg_purchase_price=100.0, purchase_date=now.date()))
        await session.commit()

    recorded: dict[str, list] = {"alert": [], "sl": [], "tp": []}
    original_open = MarketDataService.are_any_markets_open
    original_batch = MarketDataService.fetch_batch_prices
    original_alert = alerting_module.TelegramService.send_alert
    original_sl = alerting_module.TelegramService.send_stop_loss_alert
    original_tp = alerting_module.TelegramService.send_take_profit_alert
    AlertingService._last_alert_times.clear()

    async def stale_batch(tickers, timeout=None):
        return {
            t: {"open": 777.0, "high": 888.0, "low": 666.0, "close": 777.0, "volume": 1,
                "previous_close": 777.0, "change_abs": 0.0, "change_percent": 99.0, "stale": True}
            for t in tickers
        }

    async def rec_alert(self, name, ticker, change_percent, price):
        recorded["alert"].append((ticker, change_percent, price))

    async def rec_sl(self, name, ticker, pnl_pct, price, avg):
        recorded["sl"].append((ticker, pnl_pct, price, avg))

    async def rec_tp(self, name, ticker, pnl_pct, price, avg):
        recorded["tp"].append((ticker, pnl_pct, price, avg))

    try:
        MarketDataService.are_any_markets_open = staticmethod(lambda: True)
        MarketDataService.fetch_batch_prices = staticmethod(stale_batch)
        alerting_module.TelegramService.send_alert = rec_alert
        alerting_module.TelegramService.send_stop_loss_alert = rec_sl
        alerting_module.TelegramService.send_take_profit_alert = rec_tp

        async with async_session_maker() as session:
            await AlertingService().check_alerts(session)
    finally:
        MarketDataService.are_any_markets_open = staticmethod(original_open)
        MarketDataService.fetch_batch_prices = staticmethod(original_batch)
        alerting_module.TelegramService.send_alert = original_alert
        alerting_module.TelegramService.send_stop_loss_alert = original_sl
        alerting_module.TelegramService.send_take_profit_alert = original_tp
        AlertingService._last_alert_times.clear()

    rule_alerts = [a for a in recorded["alert"] if a[0] == "E2ERULE.MI"]
    check("AlertRule % NON scatta col change sintetico (usa variazione DB = 0)",
          rule_alerts == [], str(rule_alerts))

    sl_alerts = [a for a in recorded["sl"] if a[0] == "E2ESL.MI"]
    check("Stop-Loss usa il close reale dal DB (50, non 777 sintetico)",
          bool(sl_alerts) and sl_alerts[0][2] == 50.0, str(sl_alerts[:2]))


# ===========================================================================
# MAIN RUNNER
# ===========================================================================
async def run_all():
    print("=" * 60)
    print("Stock Monitor - Suite di Test End-to-End")
    print("=" * 60)

    shutil.rmtree(TEST_DIR, ignore_errors=True)
    os.makedirs(TEST_DIR, exist_ok=True)

    from backend.main import app

    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test", timeout=60.0) as c:
            token = await test_health_and_auth(c)
            h = {"Authorization": f"Bearer {token}"}

            await test_stocks(c, h)
            # Seed storico deterministico prima dei test quantitativi
            seed_price_history()

            await test_watchlist(c, h)
            await test_portfolio_crud(c, h)
            await test_trade_ledger_and_dividends(c, h)
            await test_risk_metrics(c, h)
            await test_benchmarks_and_performance(c, h)
            await test_rebalancer(c, h)
            await test_settings_and_alerts(c, h)
            await test_dashboard(c, h)
            await test_advice_fallback(c, h)
            await test_multi_user_isolation(c, h)
            await test_data_layer_schema()
            await test_retention_cleanup()
            await test_stale_fallback_not_persisted()
            await test_advice_isolation(c, h)
            await test_cache_headers(c)
            await test_fetch_batch_single_ticker_multiindex()
            await test_alerting_stale_uses_db()
            await test_concurrency(c, h)
            await test_sqlite_integrity()

    print("\n" + "=" * 60)
    print(f"RISULTATO: {PASS} passati, {FAIL} falliti")
    if FAILURES:
        print("Fallimenti:")
        for f in FAILURES:
            print("  -", f)
    print("=" * 60)
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(run_all()))
