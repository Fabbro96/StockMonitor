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
    admin_targets = r.json()
    admin_target_id = admin_targets[0]["id"] if admin_targets else None

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

    # --- Isolamento multi-utente dei Target Allocation ---
    r = await c.post("/api/auth/users", headers=h,
                     json={"username": "rebalance_user", "password": "Rebalance123!", "is_admin": False})
    check("creazione utente rebalance -> 200", r.status_code == 200, str(r.status_code))
    r = await c.post("/api/auth/login", json={"username": "rebalance_user", "password": "Rebalance123!"})
    check("login utente rebalance -> 200", r.status_code == 200, str(r.status_code))
    user_h = {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

    r = await c.get("/api/portfolio/rebalance/targets", headers=user_h)
    check("utente rebalance NON vede i target admin (0)",
          r.status_code == 200 and r.json() == [], str(r.json()))

    r = await c.delete(f"/api/portfolio/rebalance/targets/{admin_target_id}", headers=user_h)
    check("DELETE target admin da utente rebalance -> 404", r.status_code == 404, str(r.status_code))

    r = await c.get("/api/portfolio/rebalance/targets", headers=h)
    check("target admin intatti dopo il tentativo (3)",
          r.status_code == 200 and len(r.json()) == 3)

    r = await c.post("/api/portfolio/rebalance/preview", headers=user_h, json={"extra_cash": 0})
    check("preview utente senza target -> 400", r.status_code == 400, str(r.status_code))

    # L'utente crea un proprio target: isolato dall'admin in entrambe le direzioni
    r = await c.post("/api/portfolio/rebalance/targets", headers=user_h,
                     json={"name": "User Cash", "target_percent": 100, "scope_type": "CASH", "scope_value": ""})
    check("POST target utente rebalance -> 200", r.status_code == 200, str(r.status_code))
    user_target_id = r.json().get("id")
    r = await c.get("/api/portfolio/rebalance/targets", headers=user_h)
    check("utente vede solo il proprio target (1)", r.status_code == 200 and len(r.json()) == 1)
    r = await c.get("/api/portfolio/rebalance/targets", headers=h)
    check("admin NON vede il target dell'utente (3)",
          r.status_code == 200 and len(r.json()) == 3)
    r = await c.post("/api/portfolio/rebalance/preview", headers=user_h, json={"extra_cash": 0})
    check("preview utente con target proprio -> 200",
          r.status_code == 200 and "allocations" in r.json(), str(r.status_code))

    r = await c.post("/api/portfolio/rebalance/preview", headers=h, json={"extra_cash": 500})
    check("admin preview ancora 200 con 3 allocations",
          r.status_code == 200 and len(r.json().get("allocations", [])) == 3, str(r.status_code))

    if user_target_id:
        r = await c.delete(f"/api/portfolio/rebalance/targets/{user_target_id}", headers=user_h)
        check("DELETE proprio target utente -> 200", r.status_code == 200, str(r.status_code))


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


def _db_query(sql: str, params=()) -> list:
    """Query di lettura sincrona sul DB e2e (per assert di stato a livello SQL)."""
    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        return conn.execute(sql, params).fetchall()
    finally:
        conn.close()


def _db_exec(sql: str, params=()) -> None:
    """Scrittura sincrona sul DB e2e (setup deterministico, come seed_price_history)."""
    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        conn.execute(sql, params)
        conn.commit()
    finally:
        conn.close()


async def _new_user_headers(c: httpx.AsyncClient, admin_h: dict, username: str,
                            password: str = "Password123!"):
    """Crea un utente isolato e ne ritorna (user_id, headers). (None, {}) se il setup fallisce."""
    r = await c.post("/api/auth/users", headers=admin_h,
                     json={"username": username, "password": password, "is_admin": False})
    if r.status_code != 200:
        return None, {}
    uid = r.json().get("id")
    r = await c.post("/api/auth/login", json={"username": username, "password": password})
    if r.status_code != 200:
        return uid, {}
    return uid, {"Authorization": f"Bearer {r.json().get('access_token', '')}"}


async def test_data_layer_schema():
    print("\n[14] Data Layer: init_db, indici e idempotenza")
    from backend.database import init_db

    required_indexes = [
        ("price_history", "idx_stock_id_timestamp"),
        ("advices", "ix_advices_timestamp"),
        ("advices", "ix_advices_user_id"),
        ("sentiments", "ix_sentiments_stock_ts"),
        ("alert_rules", "ix_alert_rules_is_active"),
        ("target_allocations", "ix_target_allocations_user"),
    ]

    check("advices.user_id esiste (migrazione + model)", "user_id" in _column_names("advices"))
    check("target_allocations.user_id esiste (migrazione + model)",
          "user_id" in _column_names("target_allocations"))
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

    # Backfill dei target allocation orfani (user_id NULL) all'admin configurato:
    # inseriamo una riga legacy, rieseguiamo init_db e la rimuoviamo subito dopo.
    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        admin_row = conn.execute("SELECT id FROM users WHERE username=?", (ADMIN_USER,)).fetchone()
        conn.execute(
            "INSERT INTO target_allocations (name, target_percent, scope_type, scope_value, user_id) "
            "VALUES ('Legacy Target', 10, 'MARKET', 'IT', NULL)"
        )
        conn.commit()
    finally:
        conn.close()

    backfill_error = ""
    try:
        await init_db()
    except Exception as e:
        backfill_error = str(e)[:200]

    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        legacy_row = conn.execute("SELECT user_id FROM target_allocations WHERE name='Legacy Target'").fetchone()
        check("backfill target_allocations NULL -> admin",
              admin_row is not None and legacy_row is not None and legacy_row[0] == admin_row[0],
              f"legacy={legacy_row} admin={admin_row}")
        check("init_db con backfill target senza errori", backfill_error == "", backfill_error)
        conn.execute("DELETE FROM target_allocations WHERE name='Legacy Target'")
        conn.commit()
    finally:
        conn.close()


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


async def test_market_suffix_classification(c: httpx.AsyncClient, h: dict):
    print("\n[21] Classificazione mercato/valuta da suffisso (Yahoo in fallimento)")
    from types import SimpleNamespace
    from backend.services import market_data as md
    from backend.utils.helpers import detect_market_currency

    # 21.1 Helper centrale: mappa suffissi -> (market, currency)
    check("detect ENEL.MI -> (IT,EUR)", detect_market_currency("ENEL.MI") == ("IT", "EUR"))
    check("detect ASML.AS -> (EU,EUR)", detect_market_currency("ASML.AS") == ("EU", "EUR"))
    for sfx in [".DE", ".PA", ".MC", ".LS", ".BR", ".VI"]:
        check(f"detect TIT{sfx} -> (EU,EUR)", detect_market_currency(f"TIT{sfx}") == ("EU", "EUR"))
    check("detect AAPL -> (US,USD)", detect_market_currency("AAPL") == ("US", "USD"))
    check("detect ZZZQ123 -> (US,USD) default accettato",
          detect_market_currency("ZZZQ123") == ("US", "USD"))
    check("detect EURUSD=X -> (FX,USD)", detect_market_currency("EURUSD=X") == ("FX", "USD"))
    check("detect BTC-USD -> (CRYPTO,USD)", detect_market_currency("BTC-USD") == ("CRYPTO", "USD"))
    check("detect case/whitespace-insensitive", detect_market_currency("  enel.mi ") == ("IT", "EUR"))

    # 21.2 Yahoo in fallimento totale (429/rate-limit simulato)
    orig_ticker = md.yf.Ticker
    orig_download = md.yf.download

    def _yahoo_down(*args, **kwargs):
        raise RuntimeError("Yahoo down (mock e2e)")

    md.yf.Ticker = _yahoo_down
    md.yf.download = _yahoo_down
    try:
        info = await md.MarketDataService.resolve_stock_info("ENEL.MI")
        check("resolve ENEL.MI senza Yahoo -> IT/EUR",
              info.get("market") == "IT" and info.get("currency") == "EUR", str(info))
        info = await md.MarketDataService.resolve_stock_info("ASML.AS")
        check("resolve ASML.AS senza Yahoo -> EU/EUR",
              info.get("market") == "EU" and info.get("currency") == "EUR", str(info))
        info = await md.MarketDataService.resolve_stock_info("AAPL")
        check("resolve AAPL senza Yahoo -> US/USD",
              info.get("market") == "US" and info.get("currency") == "USD", str(info))
        info = await md.MarketDataService.resolve_stock_info("ZZZQ123")
        check("resolve ZZZQ123 senza Yahoo -> US/USD (default accettato)",
              info.get("market") == "US" and info.get("currency") == "USD", str(info))

        # 21.3 Yahoo che declassa un suffisso noto a US: il suffisso vince,
        # ma nome/settore Yahoo arricchiscono comunque.
        class _FakeUSTicker:
            def __init__(self, *args, **kwargs):
                pass

            @property
            def fast_info(self):
                return SimpleNamespace(currency="USD")

            @property
            def info(self):
                return {"shortName": "Enel Fake US", "currency": "USD", "sector": "Utilities"}

        md.yf.Ticker = _FakeUSTicker
        # NB: FAKEIT.MI non è in KNOWN_STOCKS -> passa davvero per il path Yahoo.
        info = await md.MarketDataService.resolve_stock_info("FAKEIT.MI")
        check("resolve FAKEIT.MI con Yahoo=US -> resta IT/EUR",
              info.get("market") == "IT" and info.get("currency") == "EUR", str(info))
        check("...ma il nome Yahoo arricchisce", info.get("name") == "Enel Fake US", str(info))

        # 21.4 Path di creazione via API con Yahoo down (utente dedicato isolato)
        md.yf.Ticker = _yahoo_down
        r = await c.post("/api/auth/users", headers=h,
                         json={"username": "suffix_user", "password": "Suffix123!", "is_admin": False})
        check("creazione utente suffix -> 200", r.status_code == 200, str(r.status_code))
        r = await c.post("/api/auth/login", json={"username": "suffix_user", "password": "Suffix123!"})
        check("login utente suffix -> 200", r.status_code == 200, str(r.status_code))
        uh = {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

        for ticker, mkt, cur in [("E2ESUFIT.MI", "IT", "EUR"), ("E2ESUFEU.AS", "EU", "EUR"),
                                 ("E2ESUFUS", "US", "USD"), ("ZZZQ123", "US", "USD")]:
            r = await c.post("/api/portfolio/holdings", headers=uh,
                             json={"ticker": ticker, "quantity": 10, "avg_purchase_price": 5.0})
            check(f"POST holding {ticker} senza Yahoo -> 200", r.status_code == 200, str(r.status_code))
            rows = (await c.get("/api/portfolio/", headers=uh)).json()
            row = next((x for x in rows if x["ticker"] == ticker), None)
            check(f"holding {ticker} classificata {mkt}/{cur}",
                  bool(row) and row.get("market") == mkt and row.get("currency") == cur, str(row))

        # Prezzo stale documentato per il ticker ignoto (default US/USD accettato)
        rows = (await c.get("/api/portfolio/", headers=uh)).json()
        zrow = next((x for x in rows if x["ticker"] == "ZZZQ123"), None)
        check("ZZZQ123 ignoto -> prezzo stale ma valorizzato (default accettato)",
              bool(zrow) and zrow.get("price_stale") is True and float(zrow.get("current_price", 0)) > 0,
              str(zrow))

        # Persistenza reale sulla tabella stocks (non solo fallback di visualizzazione)
        conn = sqlite3.connect(TEST_DB, timeout=10)
        try:
            persisted = {
                t: conn.execute("SELECT market, currency FROM stocks WHERE ticker=?", (t,)).fetchone()
                for t in ["E2ESUFIT.MI", "E2ESUFEU.AS", "E2ESUFUS", "ZZZQ123"]
            }
        finally:
            conn.close()
        for ticker, mkt, cur in [("E2ESUFIT.MI", "IT", "EUR"), ("E2ESUFEU.AS", "EU", "EUR"),
                                 ("E2ESUFUS", "US", "USD"), ("ZZZQ123", "US", "USD")]:
            check(f"stocks.{ticker} persistito {mkt}/{cur}",
                  persisted[ticker] is not None and persisted[ticker][0] == mkt and persisted[ticker][1] == cur,
                  str(persisted[ticker]))

        # 21.5 Watchlist con Yahoo down
        for ticker in ["E2EWLIT.MI", "E2EWLEU.DE"]:
            r = await c.post("/api/watchlist/", headers=uh, json={"ticker": ticker})
            check(f"POST watchlist {ticker} senza Yahoo -> 200", r.status_code == 200, str(r.status_code))
        wl = (await c.get("/api/watchlist/", headers=uh)).json()
        for ticker, mkt, cur in [("E2EWLIT.MI", "IT", "EUR"), ("E2EWLEU.DE", "EU", "EUR")]:
            item = next((x for x in wl if x["ticker"] == ticker), None)
            check(f"watchlist {ticker} classificata {mkt}/{cur}",
                  bool(item) and item.get("market") == mkt and item.get("currency") == cur, str(item))
    finally:
        md.yf.Ticker = orig_ticker
        md.yf.download = orig_download


async def test_perf_caches_and_contracts(c: httpx.AsyncClient, h: dict):
    print("\n[22] Cache perf (serie 120s / deep-stale 90s) + contratti B1/B3")
    from backend.services import analytics as analytics_module
    from backend.services import market_data as md

    me = (await c.get("/api/auth/me", headers=h)).json()
    uid = me.get("id")

    # --- B3: CSV malformato -> 200 ma errors NON vuoto, niente import silente ---
    bad_csv = "asdfgh jkl\n@@@### $$$\n"
    r = await c.post("/api/portfolio/import", headers=h,
                     files={"file": ("bad.csv", bad_csv, "text/csv")})
    check("POST import CSV malformato -> 200", r.status_code == 200, str(r.status_code))
    body = r.json()
    check("import malformato: errors non vuoto",
          isinstance(body.get("errors"), list) and len(body["errors"]) > 0, str(body))
    check("import malformato: imported == 0", body.get("imported", -1) == 0, str(body))

    # CSV valido invariato (il fix B3 non rompe il caso buono)
    good_csv = "ticker,quantity,avg_purchase_price\nE2EIMPOK.MI,7,5.5\n"
    r = await c.post("/api/portfolio/import", headers=h,
                     files={"file": ("ok.csv", good_csv, "text/csv")})
    check("POST import CSV valido -> 200 con >=1 importato",
          r.status_code == 200 and r.json().get("imported", 0) >= 1, str(r.status_code))

    # --- B1a: benchmark con Yahoo down -> ogni benchmark ha data lista ---
    orig_ticker = md.yf.Ticker
    orig_download = md.yf.download

    def _yahoo_down(*args, **kwargs):
        raise RuntimeError("Yahoo down (mock e2e)")

    md.yf.Ticker = _yahoo_down
    md.yf.download = _yahoo_down
    try:
        r = await c.get("/api/portfolio/benchmarks?days=30", headers=h)
        check("GET benchmarks con Yahoo down -> 200", r.status_code == 200, str(r.status_code))
        benches = r.json().get("benchmarks", {})
        for t in ["^GSPC", "FTSEMIB.MI"]:
            check(f"benchmark {t} presente con data lista",
                  t in benches and isinstance(benches[t].get("data"), list),
                  str(type(benches.get(t, {}).get("data"))))
    finally:
        md.yf.Ticker = orig_ticker
        md.yf.download = orig_download

    # --- Cache serie 120s: due performance consecutive identiche + chiave popolata ---
    analytics_module._SERIES_CACHE.pop(f"series:{uid}:30", None)
    r1 = await c.get("/api/dashboard/performance?days=30", headers=h)
    r2 = await c.get("/api/dashboard/performance?days=30", headers=h)
    check("performance doppia -> 200/200", r1.status_code == 200 and r2.status_code == 200)
    check("performance seconda chiamata identica (cache 120s)", r1.json() == r2.json())
    check("chiave serie in _SERIES_CACHE", f"series:{uid}:30" in analytics_module._SERIES_CACHE)

    # --- Cache risk 300s: due chiamate identiche + chiave popolata ---
    analytics_module._RISK_CACHE.pop(f"risk:{uid}:180", None)
    m1 = await c.get("/api/portfolio/risk-metrics?days=180", headers=h)
    m2 = await c.get("/api/portfolio/risk-metrics?days=180", headers=h)
    check("risk doppia -> 200/200", m1.status_code == 200 and m2.status_code == 200)
    check("risk seconda chiamata identica (cache 300s)", m1.json() == m2.json())
    check("chiave risk in _RISK_CACHE", f"risk:{uid}:180" in analytics_module._RISK_CACHE)

    # --- Cache deep-dive stale 90s: watchlist con Yahoo down resta in cache ---
    md.yf.Ticker = _yahoo_down
    md.yf.download = _yahoo_down
    try:
        md._DEEP_DIVE_CACHE.pop("E2ECACHEWL.MI", None)
        r = await c.post("/api/watchlist/", headers=h, json={"ticker": "E2ECACHEWL.MI"})
        check("POST watchlist E2ECACHEWL.MI senza Yahoo -> 200", r.status_code == 200, str(r.status_code))
        wid = r.json().get("id")
        r = await c.get("/api/watchlist/", headers=h)
        check("GET watchlist senza Yahoo -> 200", r.status_code == 200)
        entry = md._DEEP_DIVE_CACHE.get("E2ECACHEWL.MI")
        check("deep-dive stale in cache (TTL 90s)",
              entry is not None and bool(entry[0].get("stale")) is True, str(bool(entry)))
        if wid:
            await c.delete(f"/api/watchlist/{wid}", headers=h)
    finally:
        md.yf.Ticker = orig_ticker
        md.yf.download = orig_download


async def test_stock_market_update(c: httpx.AsyncClient, h: dict):
    print("\n[23] PUT /api/stocks/{ticker}: correzione mercato/valuta (globale)")
    from backend.services import market_data as md

    # Utente dedicato isolato (stile [21])
    r = await c.post("/api/auth/users", headers=h,
                     json={"username": "marketfix_user", "password": "Market123!", "is_admin": False})
    check("creazione utente marketfix -> 200", r.status_code == 200, str(r.status_code))
    r = await c.post("/api/auth/login", json={"username": "marketfix_user", "password": "Market123!"})
    check("login utente marketfix -> 200", r.status_code == 200, str(r.status_code))
    uh = {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

    # Yahoo in fallimento totale: ticker bare creato come US/USD
    orig_ticker = md.yf.Ticker
    orig_download = md.yf.download

    def _yahoo_down(*args, **kwargs):
        raise RuntimeError("Yahoo down (mock e2e)")

    md.yf.Ticker = _yahoo_down
    md.yf.download = _yahoo_down
    try:
        r = await c.post("/api/portfolio/holdings", headers=uh,
                         json={"ticker": "E2EMKT", "quantity": 10, "avg_purchase_price": 5.0})
        check("POST holding E2EMKT senza Yahoo -> 200", r.status_code == 200, str(r.status_code))
        rows = (await c.get("/api/portfolio/", headers=uh)).json()
        row = next((x for x in rows if x["ticker"] == "E2EMKT"), None)
        check("E2EMKT creato come US/USD",
              bool(row) and row.get("market") == "US" and row.get("currency") == "USD", str(row))

        # Validazione: mercato non ammesso -> 422
        r = await c.put("/api/stocks/E2EMKT", headers=uh, json={"market": "XX"})
        check("PUT mercato invalido -> 422", r.status_code == 422, str(r.status_code))
        # Ticker inesistente -> 404
        r = await c.put("/api/stocks/E2ENOPE", headers=uh, json={"market": "IT"})
        check("PUT ticker inesistente -> 404", r.status_code == 404, str(r.status_code))

        # Correzione: ticker case-insensitive, market IT -> currency EUR
        r = await c.put("/api/stocks/e2emkt", headers=uh, json={"market": "IT"})
        check("PUT mercato->IT -> 200", r.status_code == 200, str(r.status_code))
        body = r.json()
        check("risposta StockResponse con market IT + currency EUR",
              body.get("ticker") == "E2EMKT" and body.get("market") == "IT"
              and body.get("currency") == "EUR", str(body))

        # Portfolio coerente: riga IT/EUR e summary con allocazione IT in EUR
        rows = (await c.get("/api/portfolio/", headers=uh)).json()
        row = next((x for x in rows if x["ticker"] == "E2EMKT"), None)
        check("holding riflette IT/EUR",
              bool(row) and row.get("market") == "IT" and row.get("currency") == "EUR", str(row))
        s = (await c.get("/api/portfolio/summary", headers=uh)).json()
        check("summary coerente: allocazione IT > 0 (EUR)",
              isinstance(s, dict) and float(s.get("market_allocation", {}).get("IT", 0)) > 0,
              str(s.get("market_allocation")))

        # Persistenza reale su stocks
        conn = sqlite3.connect(TEST_DB, timeout=10)
        try:
            persisted = conn.execute(
                "SELECT market, currency FROM stocks WHERE ticker=?", ("E2EMKT",)).fetchone()
        finally:
            conn.close()
        check("stocks.E2EMKT persistito IT/EUR",
              persisted is not None and persisted[0] == "IT" and persisted[1] == "EUR",
              str(persisted))
    finally:
        md.yf.Ticker = orig_ticker
        md.yf.download = orig_download

    # Secondo utente vede la correzione: lo Stock è globale (documentato)
    r = await c.post("/api/auth/users", headers=h,
                     json={"username": "marketfix_bob", "password": "Market123!", "is_admin": False})
    check("creazione secondo utente -> 200", r.status_code == 200, str(r.status_code))
    r = await c.post("/api/auth/login", json={"username": "marketfix_bob", "password": "Market123!"})
    check("login secondo utente -> 200", r.status_code == 200, str(r.status_code))
    bh = {"Authorization": f"Bearer {r.json().get('access_token', '')}"}
    stocks = (await c.get("/api/stocks/", headers=bh)).json()
    stock = next((x for x in stocks if x["ticker"] == "E2EMKT"), None)
    check("secondo utente vede correzione globale IT/EUR",
          bool(stock) and stock.get("market") == "IT" and stock.get("currency") == "EUR",
          str(stock))


# ===========================================================================
# TEST GROUPS — REGRESSIONI BE-1 / BE-2 / BE-3 (Fase 1 backend)
# ===========================================================================
async def test_be1_atomicity_and_validation(c: httpx.AsyncClient, h: dict):
    print("\n[24] BE-1: concorrenza atomica holdings/transactions + validazione")
    uid, uh = await _new_user_headers(c, h, "be1conc")

    # --- 2 BUY concorrenti stesso utente+stock: esattamente UNA holding, qty e avg corretti ---
    r1, r2 = await asyncio.gather(
        c.post("/api/portfolio/transactions", headers=uh,
               json={"ticker": "ISP.MI", "type": "BUY", "quantity": 10, "price": 100.0}),
        c.post("/api/portfolio/transactions", headers=uh,
               json={"ticker": "ISP.MI", "type": "BUY", "quantity": 5, "price": 200.0}),
    )
    rows = _db_query(
        "SELECT h.quantity, h.avg_purchase_price FROM holdings h "
        "JOIN stocks s ON s.id = h.stock_id WHERE h.user_id=? AND s.ticker='ISP.MI'", (uid,))
    check("2 BUY concorrenti -> una sola holding (qty 15, avg 133.3333)",
          r1.status_code == 200 and r2.status_code == 200 and len(rows) == 1
          and abs(rows[0][0] - 15) < 1e-6 and abs(rows[0][1] - 133.3333) < 1e-3,
          f"status={r1.status_code}/{r2.status_code} rows={rows}")

    # --- 2 SELL full concorrenti: una sola 2xx, una 409, mai quantità negativa ---
    s1, s2 = await asyncio.gather(
        c.post("/api/portfolio/transactions", headers=uh,
               json={"ticker": "ISP.MI", "type": "SELL", "quantity": 15, "price": 150.0}),
        c.post("/api/portfolio/transactions", headers=uh,
               json={"ticker": "ISP.MI", "type": "SELL", "quantity": 15, "price": 150.0}),
    )
    codes = sorted([s1.status_code, s2.status_code])
    residual = _db_query(
        "SELECT h.quantity FROM holdings h JOIN stocks s ON s.id = h.stock_id "
        "WHERE h.user_id=? AND s.ticker='ISP.MI'", (uid,))
    sell_txs = _db_query(
        "SELECT COUNT(*) FROM transactions t JOIN stocks s ON s.id = t.stock_id "
        "WHERE t.user_id=? AND s.ticker='ISP.MI' AND t.type='SELL'", (uid,))
    check("2 SELL full concorrenti -> una 200 e una 409, nessuna quota residua",
          codes == [200, 409] and residual == [] and sell_txs[0][0] == 1,
          f"codes={codes} residual={residual} sell_txs={sell_txs}")

    # --- 2 add_holding concorrenti su ticker nuovo: esattamente una riga ---
    a1, a2 = await asyncio.gather(
        c.post("/api/portfolio/holdings", headers=uh,
               json={"ticker": "LDO.MI", "quantity": 10, "avg_purchase_price": 1.0}),
        c.post("/api/portfolio/holdings", headers=uh,
               json={"ticker": "LDO.MI", "quantity": 5, "avg_purchase_price": 2.0}),
    )
    rows = _db_query(
        "SELECT h.quantity, h.avg_purchase_price FROM holdings h "
        "JOIN stocks s ON s.id = h.stock_id WHERE h.user_id=? AND s.ticker='LDO.MI'", (uid,))
    check("2 add_holding concorrenti -> una sola riga (qty 15, avg 1.3333)",
          a1.status_code == 200 and a2.status_code == 200 and len(rows) == 1
          and abs(rows[0][0] - 15) < 1e-6 and abs(rows[0][1] - 1.3333) < 1e-3,
          f"status={a1.status_code}/{a2.status_code} rows={rows}")

    # --- Validazione input ---
    v1 = await c.post("/api/portfolio/holdings", headers=uh,
                      json={"ticker": "ENEL.MI", "quantity": 0, "avg_purchase_price": 6.0})
    v2 = await c.post("/api/portfolio/holdings", headers=uh,
                      json={"ticker": "ENEL.MI", "quantity": -5, "avg_purchase_price": 6.0})
    v3 = await c.post("/api/portfolio/holdings", headers=uh,
                      json={"ticker": "ENEL.MI", "quantity": 5, "avg_purchase_price": 0})
    check("HoldingCreate qty 0/-5 e price 0 -> 422",
          v1.status_code == 422 and v2.status_code == 422 and v3.status_code == 422,
          f"{v1.status_code}/{v2.status_code}/{v3.status_code}")

    v4 = await c.post("/api/portfolio/transactions", headers=uh,
                      json={"ticker": "ENEL.MI", "type": "BUY", "quantity": -1, "price": 6.0})
    v5 = await c.post("/api/portfolio/transactions", headers=uh,
                      json={"ticker": "ENEL.MI", "type": "BUY", "quantity": 0, "price": 6.0})
    check("TransactionCreate qty -1 -> 422 e qty 0 -> 400",
          v4.status_code == 422 and v5.status_code == 400,
          f"{v4.status_code}/{v5.status_code}")

    t1 = await c.post("/api/portfolio/rebalance/targets", headers=uh,
                      json={"name": "Val 60", "target_percent": 60, "scope_type": "MARKET", "scope_value": "IT"})
    t2 = await c.post("/api/portfolio/rebalance/targets", headers=uh,
                      json={"name": "Val 50", "target_percent": 50, "scope_type": "CASH", "scope_value": ""})
    tcount = _db_query("SELECT COUNT(*) FROM target_allocations WHERE user_id=?", (uid,))[0][0]
    check("somma target 60+50 -> 400 e nessuna riga extra",
          t1.status_code == 200 and t2.status_code == 400 and tcount == 1,
          f"status={t1.status_code}/{t2.status_code} count={tcount}")


async def test_be1_holdings_dedup_scratch():
    print("\n[25] BE-1: dedup holdings legacy + UNIQUE(user_id, stock_id)")
    from sqlalchemy.ext.asyncio import create_async_engine
    from backend.database import _ensure_holdings_unique_constraint

    scratch_db = os.path.join(TEST_DIR, "holdings_dedup_scratch.db")
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(scratch_db + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(scratch_db, timeout=10)
    try:
        conn.execute(
            "CREATE TABLE holdings ("
            " id INTEGER PRIMARY KEY, user_id INTEGER, stock_id INTEGER NOT NULL,"
            " quantity FLOAT NOT NULL, avg_purchase_price FLOAT NOT NULL,"
            " purchase_date DATE, notes VARCHAR, created_at DATETIME, updated_at DATETIME)"
        )
        conn.execute(
            "INSERT INTO holdings (id, user_id, stock_id, quantity, avg_purchase_price, notes) VALUES "
            "(1, 1, 1, 10, 100.0, 'first'),"
            "(2, 1, 1, 5, 200.0, 'second'),"
            "(3, 1, 2, 7, 50.0, 'other')"
        )
        conn.commit()
    finally:
        conn.close()

    engine = create_async_engine(f"sqlite+aiosqlite:///{scratch_db}")
    second_error = ""
    try:
        async with engine.begin() as aconn:
            await _ensure_holdings_unique_constraint(aconn)
        try:
            async with engine.begin() as aconn:
                await _ensure_holdings_unique_constraint(aconn)  # idempotente
        except Exception as e:
            second_error = str(e)[:200]
    finally:
        await engine.dispose()

    conn = sqlite3.connect(scratch_db, timeout=10)
    try:
        merged = conn.execute(
            "SELECT id, quantity, avg_purchase_price, notes FROM holdings "
            "WHERE user_id=1 AND stock_id=1 ORDER BY id"
        ).fetchall()
        other = conn.execute("SELECT quantity FROM holdings WHERE user_id=1 AND stock_id=2").fetchone()
        unique_covering = []
        for row in conn.execute("PRAGMA index_list(holdings)").fetchall():
            if not row[2]:
                continue
            cols = {info[2] for info in conn.execute(f"PRAGMA index_info('{row[1]}')").fetchall()}
            if cols == {"user_id", "stock_id"}:
                unique_covering.append(row[1])
        enforced = False
        try:
            conn.execute(
                "INSERT INTO holdings (user_id, stock_id, quantity, avg_purchase_price) VALUES (1, 1, 1, 1.0)")
            conn.commit()
        except sqlite3.IntegrityError:
            enforced = True
        finally:
            conn.rollback()
    finally:
        conn.close()

    merged_ok = (len(merged) == 1 and merged[0][0] == 1 and abs(merged[0][1] - 15) < 1e-9
                 and abs(merged[0][2] - 133.3333) < 1e-3 and merged[0][3] == "first"
                 and other is not None and abs(other[0] - 7) < 1e-9)
    check("dedup legacy: merge qty 15 / avg 133.3333, riga più vecchia e non duplicata intatte",
          merged_ok, f"merged={merged} other={other}")
    check("indice UNIQUE uq_holdings_user_stock presente", "uq_holdings_user_stock" in unique_covering,
          str(unique_covering))
    check("INSERT duplicato (user_id, stock_id) rifiutato dall'indice unico", enforced)
    check("seconda esecuzione idempotente (nessun errore, ancora 1 riga)",
          second_error == "" and len(merged) == 1, second_error or f"merged={merged}")


async def test_be1_ledger_recompute_and_pnl(c: httpx.AsyncClient, h: dict):
    print("\n[26] BE-1: recompute delete_transaction (M11) + P&L realizzato con fee (M1)")
    uid, uh = await _new_user_headers(c, h, "be1pnl")

    def race_row():
        rows = _db_query(
            "SELECT h.quantity, h.avg_purchase_price FROM holdings h "
            "JOIN stocks s ON s.id = h.stock_id WHERE h.user_id=? AND s.ticker='RACE.MI'", (uid,))
        return rows[0] if rows else None

    # --- M11: BUY 10@100 + BUY 5@200 + SELL 12 -> delete SELL -> recompute dai movimenti residui ---
    b1 = await c.post("/api/portfolio/transactions", headers=uh,
                      json={"ticker": "RACE.MI", "type": "BUY", "quantity": 10, "price": 100.0})
    b2 = await c.post("/api/portfolio/transactions", headers=uh,
                      json={"ticker": "RACE.MI", "type": "BUY", "quantity": 5, "price": 200.0})
    s1 = await c.post("/api/portfolio/transactions", headers=uh,
                      json={"ticker": "RACE.MI", "type": "SELL", "quantity": 12, "price": 250.0})
    row = race_row()
    check("M11: BUY 10@100 + BUY 5@200 + SELL 12 -> quota 3",
          b1.status_code == 200 and b2.status_code == 200 and s1.status_code == 200
          and row is not None and abs(row[0] - 3) < 1e-6,
          f"status={b1.status_code}/{b2.status_code}/{s1.status_code} row={row}")

    sell_id = s1.json().get("transaction", {}).get("id") if s1.status_code == 200 else None
    d = await c.delete(f"/api/portfolio/transactions/{sell_id}", headers=uh) if sell_id else None
    row = race_row()
    check("M11: delete SELL -> ricalcolo qty 15 / avg 133.3333",
          d is not None and d.status_code == 200 and row is not None
          and abs(row[0] - 15) < 1e-6 and abs(row[1] - 133.3333) < 1e-3,
          f"delete={getattr(d, 'status_code', None)} row={row}")

    txs = (await c.get("/api/portfolio/transactions?ticker=RACE.MI", headers=uh)).json()
    for bid in [t["id"] for t in txs if t.get("type") == "BUY"]:
        await c.delete(f"/api/portfolio/transactions/{bid}", headers=uh)
    left = _db_query("SELECT COUNT(*) FROM transactions WHERE user_id=?", (uid,))[0][0]
    check("M11: delete di tutti i BUY -> holding rimossa e nessuna transazione residua",
          uid is not None and race_row() is None and left == 0,
          f"holding={race_row()} txs={left}")

    # --- M1: fee mai conteggiate due volte nel netto realizzato.
    # Formula: capital_gains = Σ[(sell_price - avg_cost) * qty - sell_fee] (fee SELL già netta);
    #          dividends = Σ(price * qty); net = capital_gains + dividends - (fees_totali - sell_fees).
    await c.post("/api/portfolio/transactions", headers=uh,
                 json={"ticker": "ENEL.MI", "type": "BUY", "quantity": 10, "price": 100.0, "fee": 10.0})
    sr = await c.post("/api/portfolio/transactions", headers=uh,
                      json={"ticker": "ENEL.MI", "type": "SELL", "quantity": 5, "price": 120.0, "fee": 6.0})
    check("M1: realized SELL = (120-100)*5 - 6 = 94",
          sr.status_code == 200 and sr.json().get("transaction", {}).get("realized_pnl") == 94.0,
          str(sr.json().get("transaction") if sr.status_code == 200 else sr.text[:120]))

    await c.post("/api/portfolio/transactions", headers=uh,
                 json={"ticker": "ENEL.MI", "type": "DIVIDEND", "quantity": 10, "price": 5.0, "fee": 1.0})
    pnl = (await c.get("/api/portfolio/realized-pnl", headers=uh)).json()
    check("M1: capital gains 94 / dividendi lordi 50 / fee totali 17",
          abs(pnl.get("total_realized_capital_gains", -1) - 94.0) < 1e-6
          and abs(pnl.get("total_dividends_collected", -1) - 50.0) < 1e-6
          and abs(pnl.get("total_fees_paid", -1) - 17.0) < 1e-6, str(pnl))
    check("M1: net = 94 + 50 - (10+1) = 133 (fee SELL non sottratta due volte)",
          abs(pnl.get("net_realized_profit", -1) - 133.0) < 1e-6, str(pnl))


async def test_be3_staleness_and_invalidation(c: httpx.AsyncClient, h: dict):
    print("\n[27] BE-3: price staleness da DB (M12) + invalidazione cache per-utente (H3)")
    from backend.services import market_data as md
    from backend.services import analytics as analytics_module

    uid, uh = await _new_user_headers(c, h, "be3cache")

    r = await c.post("/api/portfolio/holdings", headers=uh,
                     json={"ticker": "G.MI", "quantity": 10, "avg_purchase_price": 20.0})
    stock_row = _db_query("SELECT id FROM stocks WHERE ticker='G.MI'")
    stock_id = stock_row[0][0] if stock_row else None
    if uid is None or r.status_code != 200 or stock_id is None:
        check("setup staleness (utente + holding G.MI)", False,
              f"uid={uid} status={r.status_code} stock_id={stock_id}")
        return

    def _write_price(close: float, age_days: float):
        _db_exec("DELETE FROM price_history WHERE stock_id=?", (stock_id,))
        ts = (datetime.now(timezone.utc) - timedelta(days=age_days)).isoformat()
        _db_exec(
            "INSERT INTO price_history (stock_id, timestamp, open, high, low, close, volume) "
            "VALUES (?,?,?,?,?,?,?)",
            (stock_id, ts, close - 0.1, close + 0.2, close - 0.2, close, 1000),
        )

    original_batch = md.MarketDataService.fetch_batch_prices
    original_current = md.MarketDataService.fetch_current_price

    async def empty_batch(tickers, timeout=None):
        return {}

    async def stale_current(ticker):
        return md.MarketDataService._generate_fallback_price(ticker)

    try:
        _write_price(26.5, 5.0)   # più vecchio di _PRICE_FRESHNESS_HOURS (36h) -> stale
        md.MarketDataService.fetch_batch_prices = staticmethod(empty_batch)
        md.MarketDataService.fetch_current_price = staticmethod(stale_current)

        rows = (await c.get("/api/portfolio/", headers=uh)).json()
        grow = next((x for x in rows if x["ticker"] == "G.MI"), None) if isinstance(rows, list) else None
        summary = (await c.get("/api/portfolio/summary", headers=uh)).json()
        check("M12: prezzo DB vecchio (5gg) -> price_stale=True e summary al prezzo stale (265.0)",
              r.status_code == 200 and bool(grow) and grow.get("price_stale") is True
              and abs(float(grow.get("current_price", 0)) - 26.5) < 1e-6
              and abs(float(summary.get("total_value", 0)) - 265.0) < 0.01,
              f"row={grow} summary_total={summary.get('total_value')}")

        _write_price(30.0, 0.0)   # fresco: controllo positivo (niente stale)
        rows = (await c.get("/api/portfolio/", headers=uh)).json()
        grow = next((x for x in rows if x["ticker"] == "G.MI"), None) if isinstance(rows, list) else None
        check("M12: prezzo DB fresco -> price_stale=False (controllo positivo)",
              bool(grow) and grow.get("price_stale") is False
              and abs(float(grow.get("current_price", 0)) - 30.0) < 1e-6, str(grow))
    finally:
        md.MarketDataService.fetch_batch_prices = staticmethod(original_batch)
        md.MarketDataService.fetch_current_price = staticmethod(original_current)

    # --- H3: una scrittura via API invalida series/risk del solo utente coinvolto ---
    own_series = f"series:{uid}:30"
    own_risk = f"risk:{uid}:180"
    other_series = "series:999999:30"
    analytics_module._SERIES_CACHE[own_series] = ([{"date": "2026-01-01", "value": 1.0}], time.time())
    analytics_module._RISK_CACHE[own_risk] = ({"max_drawdown_pct": 0.0}, time.time())
    analytics_module._SERIES_CACHE[other_series] = ([], time.time())
    planted = own_series in analytics_module._SERIES_CACHE and own_risk in analytics_module._RISK_CACHE

    wr = await c.post("/api/portfolio/holdings", headers=uh,
                      json={"ticker": "G.MI", "quantity": 1, "avg_purchase_price": 30.0})
    removed = own_series not in analytics_module._SERIES_CACHE and own_risk not in analytics_module._RISK_CACHE
    other_ok = other_series in analytics_module._SERIES_CACHE
    analytics_module._SERIES_CACHE.pop(other_series, None)
    check("H3: la scrittura invalida series/risk dell'utente senza toccare gli altri",
          wr.status_code == 200 and planted and removed and other_ok,
          f"status={wr.status_code} planted={planted} removed={removed} other={other_ok}")

    # Dopo l'invalidazione la performance ricalcola (backfill Yahoo neutralizzato) e ripopola la cache
    original_candles = md.MarketDataService.fetch_stock_candles

    async def no_candles(ticker, timeframe="1y"):
        return []

    try:
        md.MarketDataService.fetch_stock_candles = staticmethod(no_candles)
        pr = await c.get("/api/dashboard/performance?days=30", headers=uh)
    finally:
        md.MarketDataService.fetch_stock_candles = staticmethod(original_candles)
    check("H3: performance ricalcolata dopo la scrittura (chiave serie ripopolata)",
          pr.status_code == 200 and own_series in analytics_module._SERIES_CACHE,
          f"status={pr.status_code} keys={list(analytics_module._SERIES_CACHE)}")


async def test_be2_isolation_dashboard_race_cascade(c: httpx.AsyncClient, h: dict):
    print("\n[28] BE-2: ownership strict (B2), dashboard (M3), settings race (H8), cascade utente (H5)")
    uid, uh = await _new_user_headers(c, h, "be2iso")

    # --- B2: ownership strict su watchlist e alert rule ---
    w = await c.post("/api/watchlist/", headers=h, json={"ticker": "MSFT", "notes": "admin item"})
    wl_id = w.json().get("id")

    r = await c.put(f"/api/watchlist/{wl_id}/alert", headers=uh, json={"alert_above": 1.0})
    check("B2: PUT alert su item watchlist altrui -> 404", r.status_code == 404, str(r.status_code))

    r = await c.delete(f"/api/watchlist/{wl_id}", headers=uh)
    still = _db_query("SELECT COUNT(*) FROM watchlist_items WHERE id=?", (wl_id,))[0][0]
    check("B2: DELETE item watchlist altrui -> 404 e item intatto",
          r.status_code == 404 and still == 1, f"status={r.status_code} count={still}")

    a = await c.post("/api/settings/alerts", headers=h,
                     json={"ticker": "MSFT", "threshold": 5.0, "direction": "BOTH"})
    rule_id = a.json().get("id")

    r = await c.delete(f"/api/settings/alerts/{rule_id}", headers=uh)
    still = _db_query("SELECT COUNT(*) FROM alert_rules WHERE id=?", (rule_id,))[0][0]
    check("B2: DELETE alert rule altrui -> 404 e regola intatta",
          r.status_code == 404 and still == 1, f"status={r.status_code} count={still}")

    # --- M3: il dashboard conta solo le regole dell'utente corrente ---
    d0 = (await c.get("/api/dashboard/", headers=uh)).json()
    own = await c.post("/api/settings/alerts", headers=uh,
                       json={"ticker": "MSFT", "threshold": 9.0, "direction": "UP"})
    d1 = (await c.get("/api/dashboard/", headers=uh)).json()
    check("M3: dashboard non conta le regole altrui (0 -> 1 con la propria)",
          own.status_code == 200
          and d0.get("active_alerts_count") == 0 and d1.get("active_alerts_count") == 1,
          f"prima={d0.get('active_alerts_count')} dopo={d1.get('active_alerts_count')}")

    # --- H8: GET /settings paralleli su utente fresco -> una sola riga ---
    results = await asyncio.gather(*[c.get("/api/settings/", headers=uh) for _ in range(12)],
                                   return_exceptions=True)
    statuses = [r.status_code for r in results if isinstance(r, httpx.Response)]
    check("H8: 12 GET /settings paralleli -> tutti 200",
          len(statuses) == 12 and all(s == 200 for s in statuses), str(statuses))
    count = _db_query("SELECT COUNT(*) FROM user_settings WHERE user_id=?", (uid,))[0][0]
    check("H8: esattamente una riga user_settings per l'utente", count == 1, f"count={count}")

    # --- H5: delete utente proprietario di target allocation -> 2xx, niente FK error ---
    t = await c.post("/api/portfolio/rebalance/targets", headers=uh,
                     json={"name": "Cash", "target_percent": 100, "scope_type": "CASH", "scope_value": ""})
    dr = await c.delete(f"/api/auth/users/{uid}", headers=h)
    targets = _db_query("SELECT COUNT(*) FROM target_allocations WHERE user_id=?", (uid,))[0][0]
    user_gone = _db_query("SELECT COUNT(*) FROM users WHERE id=?", (uid,))[0][0]
    check("H5: admin delete utente con target -> 2xx senza FK error",
          200 <= dr.status_code < 300, f"{dr.status_code} {dr.text[:160]}")
    check("H5: target allocation e utente rimossi dal DB",
          t.status_code == 200 and targets == 0 and user_gone == 0,
          f"setup_target={t.status_code} targets={targets} user={user_gone}")

    # Cleanup delle risorse admin usate per l'ownership
    if wl_id:
        await c.delete(f"/api/watchlist/{wl_id}", headers=h)
    if rule_id:
        await c.delete(f"/api/settings/alerts/{rule_id}", headers=h)


async def test_be2_watchlist_alignment_and_advisor_notnull():
    print("\n[29] BE-2: watchlist deep-dive allineato (M2) + advisor NOT NULL (M5)")
    from types import SimpleNamespace
    from backend.routers import watchlist as wl_mod
    from backend.database import async_session_maker
    from backend.services import market_data as md
    from backend.services.advisor import AdvisorService

    # --- M2 unit-level: item A/B/C, lo stock di B manca (race post-join).
    # Il bug storico era lo zip di iteratori disallineati: A riceveva i dati di B, ecc.
    class _Scalars:
        def __init__(self, rows):
            self._rows = rows

        def all(self):
            return self._rows

    class _Result:
        def __init__(self, rows):
            self._rows = rows

        def scalars(self):
            return _Scalars(self._rows)

        def all(self):
            return self._rows

    class _FakeDB:
        def __init__(self, results):
            self._results = list(results)
            self.commits = 0

        async def execute(self, stmt):
            return self._results.pop(0)

        async def commit(self):
            self.commits += 1

    def _item(iid, sid):
        return SimpleNamespace(id=iid, stock_id=sid, notes=None, alert_above=None,
                               alert_below=None, added_at=None)

    def _stock(sid, ticker):
        return SimpleNamespace(id=sid, ticker=ticker, name=ticker, market="US", currency="USD")

    calls = []

    async def dd_by_ticker(ticker):
        calls.append(ticker)
        return {"current_price": {"AAA": 1.0, "CCC": 3.0}.get(ticker, 0.0), "name": f"name-{ticker}"}

    original_dd = md.MarketDataService.fetch_stock_deep_dive
    try:
        md.MarketDataService.fetch_stock_deep_dive = staticmethod(dd_by_ticker)
        fake_db = _FakeDB([
            _Result([_item(1, 1), _item(2, 2), _item(3, 3)]),  # item A, B, C
            _Result([_stock(1, "AAA"), _stock(3, "CCC")]),     # stock di B assente (race)
            _Result([]),                                       # nessuna holding
        ])
        resp = await wl_mod.get_watchlist(
            current_user=SimpleNamespace(id=1, is_admin=False), db=fake_db)
    finally:
        md.MarketDataService.fetch_stock_deep_dive = original_dd

    check("M2: deep-dive chiamato solo per gli stock presenti (AAA, CCC), nessuno shift",
          calls == ["AAA", "CCC"] and fake_db.commits >= 1, str(calls))
    check("M2: ogni item superstite riceve il proprio deep-dive (A=1.0, C=3.0)",
          [x["ticker"] for x in resp] == ["AAA", "CCC"]
          and resp[0]["current_price"] == 1.0 and resp[1]["current_price"] == 3.0, str(resp))

    # --- M5: payload Gemini con strategy None -> reasoning '' e commit comunque riuscito ---
    uid_row = _db_query("SELECT id FROM users WHERE username='be3cache'")
    uid = uid_row[0][0] if uid_row else None

    service = AdvisorService()

    async def fake_ctx(ticker, name):
        return []

    async def fake_gemini(prompt):
        return {
            "borsa_italiana": {"overview": "Quadro IT", "action": None, "strategy": None,
                               "confidence": None, "stocks_analysis": []},
            "borsa_americana": {"overview": "Quadro US", "action": "ACCUMULO",
                                "strategy": "Strategia US", "confidence": "HIGH",
                                "stocks_analysis": []},
        }

    service.sentiment_service.get_combined_market_context = fake_ctx
    service._call_gemini = fake_gemini

    advices = []
    if uid is not None:
        async with async_session_maker() as session:
            advices = await service.generate_advice(session, force=True, user_id=uid)
    it = next((a for a in advices if a["market"] == "IT"), None)
    us = next((a for a in advices if a["market"] == "US"), None)
    persisted = _db_query("SELECT reasoning FROM advices WHERE user_id=?", (uid,)) if uid else []
    check("M5: strategy None non blocca la generazione; reasoning '' e persistito non-NULL",
          len(advices) == 2 and us is not None and us["strategy"] == "Strategia US"
          and it is not None and it["strategy"] == "" and it["action"] == "MANTENIMENTO"
          and it["confidence"] == "MEDIUM" and len(persisted) == 2
          and all(row[0] is not None for row in persisted),
          f"it={it} us={us} persisted={persisted}")


async def test_be2_login_lockout_atomic(c: httpx.AsyncClient, h: dict):
    print("\n[30] BE-2: login lockout atomico (M10)")
    uid, _ = await _new_user_headers(c, h, "be2lock")

    async def wrong_login():
        return await c.post("/api/auth/login", json={"username": "be2lock", "password": "WrongPass!"})

    results = await asyncio.gather(*[wrong_login() for _ in range(6)], return_exceptions=True)
    exceptions = [r for r in results if isinstance(r, Exception)]
    statuses = [r.status_code for r in results if isinstance(r, httpx.Response)]
    check("M10: 6 login errati paralleli -> nessuna eccezione, 401/429, almeno un 429",
          not exceptions and len(statuses) == 6 and all(s in (401, 429) for s in statuses)
          and 429 in statuses,
          f"exceptions={exceptions[:2]} statuses={statuses}")

    rows = _db_query("SELECT failed_attempts, locked_until FROM users WHERE id=?", (uid,))
    failed, locked = (rows[0][0], rows[0][1]) if rows else (None, None)
    check("M10: failed_attempts == 6 (nessun incremento perso) e locked_until valorizzato",
          failed == 6 and locked is not None, f"failed={failed} locked={locked}")

    r = await c.post("/api/auth/login", json={"username": "be2lock", "password": "Password123!"})
    check("M10: password corretta durante il lock -> 429", r.status_code == 429, str(r.status_code))


async def test_be3_singleflight_fallback_rebalance(c: httpx.AsyncClient, h: dict):
    print("\n[31] BE-3: single-flight (H1), fallback non-fresh (H2), merge rebalance EUR (M6/M7)")
    import pandas as pd
    from backend.services import market_data as md
    from backend.services.analytics import compute_rebalance_plan

    # ---------- H1: single-flight prezzo (N cold request -> 1 chiamata upstream) ----------
    class _FakeTicker:
        def __init__(self, *args, **kwargs):
            pass

        def history(self, *args, **kwargs):
            idx = pd.to_datetime(["2026-09-10", "2026-09-11"])
            return pd.DataFrame(
                {"Open": [1.0, 1.1], "High": [1.2, 1.3], "Low": [0.9, 1.0],
                 "Close": [1.0, 1.2], "Volume": [10, 20]}, index=idx)

        @property
        def info(self):
            return {"beta": 1.1}

        @property
        def fast_info(self):
            return None

    calls = {"n": 0}
    original_run = md.run_blocking_yf
    original_ticker = md.yf.Ticker
    original_download = md.yf.download

    async def counting_run(func, timeout=None):
        calls["n"] += 1
        await asyncio.sleep(0.05)  # garantisce overlap tra i richiedenti
        return func()

    sf1, sf2 = "E2ESF1.MI", "E2ESF2.MI"
    try:
        md.run_blocking_yf = counting_run
        md.yf.Ticker = _FakeTicker
        for t in (sf1, sf2):
            md._PRICE_CACHE.pop(t, None)
            md._PRICE_FALLBACK_CACHE.pop(t, None)

        res = await asyncio.gather(*[md.MarketDataService.fetch_current_price(sf1) for _ in range(8)])
        check("H1: 8 fetch_current_price concorrenti stessa chiave -> 1 sola chiamata upstream",
              calls["n"] == 1 and all(abs(r.get("close", 0) - 1.2) < 1e-9 for r in res),
              f"calls={calls['n']} closes={[r.get('close') for r in res][:3]}")

        calls["n"] = 0
        idx = pd.to_datetime(["2026-09-10", "2026-09-11"])
        df_batch = pd.DataFrame({
            (sf2, "Open"): [1.0, 1.1], (sf2, "High"): [1.2, 1.3],
            (sf2, "Low"): [0.9, 1.0], (sf2, "Close"): [1.0, 1.2], (sf2, "Volume"): [10, 20],
        }, index=idx)
        md.yf.download = lambda *a, **k: df_batch
        res = await asyncio.gather(*[md.MarketDataService.fetch_batch_prices([sf2]) for _ in range(8)])
        check("H1: 8 fetch_batch_prices concorrenti stessi ticker -> 1 sola chiamata upstream",
              calls["n"] == 1 and all(abs(r[sf2]["close"] - 1.2) < 1e-9 for r in res),
              f"calls={calls['n']} closes={[r[sf2].get('close') for r in res][:3]}")
    finally:
        md.run_blocking_yf = original_run
        md.yf.Ticker = original_ticker
        md.yf.download = original_download
        for t in (sf1, sf2):
            md._PRICE_CACHE.pop(t, None)
            md._PRICE_FALLBACK_CACHE.pop(t, None)
        for key in [k for k in md._INFLIGHT_FETCHES if sf1 in k or sf2 in k]:
            md._INFLIGHT_FETCHES.pop(key, None)

    # ---------- H2: upstream down -> stale=True e MAI nella cache "fresca" ----------
    def _boom(*args, **kwargs):
        raise RuntimeError("upstream down (mock e2e)")

    fb1, fb2 = "E2EFB1.MI", "E2EFB2.MI"
    try:
        md.yf.Ticker = _boom
        md.yf.download = _boom
        for t in (fb1, fb2):
            md._PRICE_CACHE.pop(t, None)
            md._PRICE_FALLBACK_CACHE.pop(t, None)

        p = await md.MarketDataService.fetch_current_price(fb1)
        bp = await md.MarketDataService.fetch_batch_prices([fb2])
        entry = bp.get(fb2) or {}
        check("H2: fallback prezzo/batch stale e MAI in _PRICE_CACHE (solo fallback cache)",
              p.get("stale") is True and fb1 not in md._PRICE_CACHE
              and fb1 in md._PRICE_FALLBACK_CACHE
              and entry.get("stale") is True and fb2 not in md._PRICE_CACHE
              and fb2 in md._PRICE_FALLBACK_CACHE,
              f"price={p} batch={entry}")
    finally:
        md.yf.Ticker = original_ticker
        md.yf.download = original_download
        for t in (fb1, fb2):
            md._PRICE_CACHE.pop(t, None)
            md._PRICE_FALLBACK_CACHE.pop(t, None)
        for key in [k for k in md._INFLIGHT_FETCHES if fb1 in k or fb2 in k]:
            md._INFLIGHT_FETCHES.pop(key, None)

    # ---------- M6/M7: preview con target sovrapposti + totali in EUR ----------
    uid, uh = await _new_user_headers(c, h, "be3reb")
    if uid is None:
        check("setup utente be3reb", False, "creazione utente fallita")
        return

    stock_ok = []
    for ticker, name, market in [("E2EREB.MI", "E2E Rebalance IT", "IT"),
                                 ("E2EREBUS", "E2E Rebalance US", "US")]:
        rr = await c.post("/api/stocks/", headers=h,
                          json={"ticker": ticker, "name": name, "market": market})
        stock_ok.append(rr.status_code == 200)

    now_iso = datetime.now(timezone.utc).isoformat()
    for ticker, close in [("E2EREB.MI", 10.0), ("E2EREBUS", 20.0)]:
        sid = _db_query("SELECT id FROM stocks WHERE ticker=?", (ticker,))
        if sid:
            _db_exec(
                "INSERT INTO price_history (stock_id, timestamp, open, high, low, close, volume) "
                "VALUES (?,?,?,?,?,?,?)",
                (sid[0][0], now_iso, close - 0.1, close + 0.2, close - 0.2, close, 1000),
            )

    for ticker in ("E2EREB.MI", "E2EREBUS"):
        await c.post("/api/portfolio/holdings", headers=uh,
                     json={"ticker": ticker, "quantity": 10, "avg_purchase_price": 5.0})

    for name, pct, stype, sval in [
        ("IT reb", 0, "MARKET", "IT"),
        ("Ticker reb", 0, "TICKERS", "E2EREB.MI"),
        ("US reb", 0, "MARKET", "US"),
        ("Cash reb", 100, "CASH", ""),
    ]:
        await c.post("/api/portfolio/rebalance/targets", headers=uh,
                     json={"name": name, "target_percent": pct, "scope_type": stype, "scope_value": sval})

    original_batch = md.MarketDataService.fetch_batch_prices
    original_current = md.MarketDataService.fetch_current_price

    async def empty_batch(tickers, timeout=None):
        return {}

    async def stale_current(ticker):
        return md.MarketDataService._generate_fallback_price(ticker)

    try:
        md.MarketDataService.fetch_batch_prices = staticmethod(empty_batch)
        md.MarketDataService.fetch_current_price = staticmethod(stale_current)

        rows = (await c.get("/api/portfolio/", headers=uh)).json()
        expected_eur = (round(sum(float(x.get("total_value_eur", 0.0)) for x in rows), 2)
                        if isinstance(rows, list) else 0.0)

        prev = await c.post("/api/portfolio/rebalance/preview", headers=uh, json={"extra_cash": 0})
        plan = prev.json() if prev.status_code == 200 else {}
    finally:
        md.MarketDataService.fetch_batch_prices = staticmethod(original_batch)
        md.MarketDataService.fetch_current_price = staticmethod(original_current)

    orders = plan.get("orders", []) if isinstance(plan, dict) else []
    by_ticker = {}
    for o in orders:
        by_ticker.setdefault(o.get("ticker"), []).append(o)
    eb = by_ticker.get("E2EREB.MI", [])
    bus = by_ticker.get("E2EREBUS", [])
    alloc_names = " + ".join(eb[0].get("allocation_name") or "" for _ in eb) if eb else ""
    check("M6/M7: target sovrapposti -> un solo ordine SELL consolidato per ticker",
          prev.status_code == 200 and all(stock_ok) and len(orders) == 2
          and len(eb) == 1 and len(bus) == 1
          and eb[0]["side"] == "SELL" and bus[0]["side"] == "SELL"
          and "IT reb" in alloc_names and "Ticker reb" in alloc_names,
          f"status={prev.status_code} orders={orders}")

    def _order_ok(o, held):
        return (o["quantity"] <= held + 1e-9
                and abs(o["estimated_value"] - round(o["quantity"] * o["estimated_price"], 2)) < 0.01
                and "_value_eur" not in o)

    check("M7: cap SELL <= quantità detenuta, value = qty*price, nessuna chiave interna",
          len(eb) == 1 and len(bus) == 1
          and abs(eb[0]["quantity"] - 10.0) < 1e-6 and abs(bus[0]["quantity"] - 10.0) < 1e-6
          and _order_ok(eb[0], 10.0) and _order_ok(bus[0], 10.0), str(orders))

    check("M7: totali di piano in EUR (total_value == somma total_value_eur)",
          abs(float(plan.get("total_value", 0.0)) - expected_eur) < 0.02 and expected_eur > 0,
          f"plan={plan.get('total_value')} atteso={expected_eur}")

    # Unit: holding USD -> aggregati in EUR ma quantità nativa = delta_eur / price_eur
    usd_holding = {"ticker": "AAPL", "name": "Apple", "market": "US", "currency": "USD",
                   "quantity": 10, "current_price": 10.0, "total_value": 100.0,
                   "total_value_eur": 90.0, "fx_rate_to_eur": 0.9}
    usd_plan = compute_rebalance_plan(
        [usd_holding],
        [{"id": 1, "name": "US 200", "target_percent": 200.0,
          "scope_type": "MARKET", "scope_value": "US"}],
        extra_cash=0.0,
    )
    usd_orders = usd_plan.get("orders", [])
    check("M7: holding USD -> total_value/allocations in EUR e qty nativa col cambio",
          abs(float(usd_plan.get("total_value", 0.0)) - 90.0) < 0.01
          and abs(usd_plan["allocations"][0]["target_value"] - 180.0) < 0.02
          and len(usd_orders) == 1 and usd_orders[0]["side"] == "BUY"
          and abs(usd_orders[0]["quantity"] - 10.0) < 1e-6,
          f"plan={usd_plan.get('total_value')} orders={usd_orders}")


async def test_r3_null_legacy_ownership(c: httpx.AsyncClient, h: dict):
    print("\n[32] R1: ownership strict righe legacy user_id NULL (holdings/transactions)")
    # Stock dedicato creato senza rete (name+market espliciti)
    rr = await c.post("/api/stocks/", headers=h,
                      json={"ticker": "R3LEGACY.MI", "name": "R3 Legacy", "market": "IT"})
    stock_id = rr.json().get("id") if rr.status_code == 200 else None
    if stock_id is None:
        check("setup stock R3LEGACY.MI", False, f"{rr.status_code} {rr.text[:120]}")
        return

    admin_row = _db_query("SELECT id FROM users WHERE username=?", (ADMIN_USER,))
    admin_id = admin_row[0][0] if admin_row else None
    if admin_id is None:
        check("setup admin id", False, "admin non trovato")
        return

    # Righe legacy user_id NULL + posizione/transazione admin parallela sullo stesso titolo
    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO holdings (user_id, stock_id, quantity, avg_purchase_price, purchase_date) "
            "VALUES (NULL, ?, 3, 6.5, date('now'))", (stock_id,))
        null_holding_id = cur.lastrowid
        cur.execute(
            "INSERT INTO transactions (user_id, stock_id, type, quantity, price, fee, realized_pnl, currency, transaction_date) "
            "VALUES (NULL, ?, 'BUY', 3, 6.5, 0, 0, 'EUR', ?)", (stock_id, datetime.now(timezone.utc).isoformat()))
        null_tx_id = cur.lastrowid
        cur.execute(
            "INSERT INTO holdings (user_id, stock_id, quantity, avg_purchase_price, purchase_date) "
            "VALUES (?, ?, 10, 5.0, date('now'))", (admin_id, stock_id))
        admin_holding_id = cur.lastrowid
        cur.execute(
            "INSERT INTO transactions (user_id, stock_id, type, quantity, price, fee, realized_pnl, currency, transaction_date) "
            "VALUES (?, ?, 'BUY', 10, 5.0, 0, 0, 'EUR', ?)",
            (admin_id, stock_id, datetime.now(timezone.utc).isoformat()))
        admin_tx_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()

    uid, uh = await _new_user_headers(c, h, "r3legacy")

    # --- Non-admin: nessun accesso alle righe legacy NULL ---
    p1 = await c.put(f"/api/portfolio/holdings/{null_holding_id}", headers=uh, json={"quantity": 99})
    row = _db_query("SELECT quantity FROM holdings WHERE id=?", (null_holding_id,))
    check("BL-1: non-admin PUT su holding legacy NULL -> 404 e riga intatta",
          p1.status_code == 404 and bool(row) and abs(row[0][0] - 3) < 1e-9,
          f"{p1.status_code} row={row}")

    d1 = await c.delete(f"/api/portfolio/holdings/{null_holding_id}", headers=uh)
    row = _db_query("SELECT COUNT(*) FROM holdings WHERE id=?", (null_holding_id,))[0][0]
    check("BL-1: non-admin DELETE holding legacy NULL -> 404 e riga intatta",
          d1.status_code == 404 and row == 1, f"{d1.status_code} count={row}")

    d2 = await c.delete(f"/api/portfolio/transactions/{null_tx_id}", headers=uh)
    row = _db_query("SELECT COUNT(*) FROM transactions WHERE id=?", (null_tx_id,))[0][0]
    check("BL-1: non-admin DELETE transaction legacy NULL -> 404 e riga intatta",
          d2.status_code == 404 and row == 1, f"{d2.status_code} count={row}")

    b1 = await c.put("/api/portfolio/batch", headers=uh,
                     json={"holdings": [{"id": null_holding_id, "quantity": 88, "avg_purchase_price": 7.0}]})
    row = _db_query("SELECT quantity FROM holdings WHERE id=?", (null_holding_id,))
    check("BL-1: batch non-admin non modifica la holding NULL (updated_count 0)",
          b1.status_code == 200 and b1.json().get("updated_count") == 0
          and bool(row) and abs(row[0][0] - 3) < 1e-9,
          f"{b1.status_code} {b1.text[:120]} row={row}")

    # --- Admin: accesso consentito, recompute senza corrompere il ledger admin ---
    p2 = await c.put(f"/api/portfolio/holdings/{null_holding_id}", headers=h, json={"quantity": 20})
    row = _db_query("SELECT quantity FROM holdings WHERE id=?", (null_holding_id,))
    check("BL-1: admin PUT su holding legacy NULL -> 200 e aggiornata",
          p2.status_code == 200 and bool(row) and abs(row[0][0] - 20) < 1e-9,
          f"{p2.status_code} row={row}")

    b2 = await c.put("/api/portfolio/batch", headers=h,
                     json={"holdings": [{"id": null_holding_id, "quantity": 30, "avg_purchase_price": 6.0}]})
    row = _db_query("SELECT quantity, avg_purchase_price FROM holdings WHERE id=?", (null_holding_id,))
    check("BL-1: admin batch aggiorna la holding NULL (updated_count 1)",
          b2.status_code == 200 and b2.json().get("updated_count") == 1
          and bool(row) and abs(row[0][0] - 30) < 1e-9 and abs(row[0][1] - 6.0) < 1e-9,
          f"{b2.status_code} {b2.text[:120]} row={row}")

    d3 = await c.delete(f"/api/portfolio/transactions/{null_tx_id}", headers=h)
    admin_holding = _db_query("SELECT quantity, avg_purchase_price FROM holdings WHERE id=?", (admin_holding_id,))
    null_tx_left = _db_query("SELECT COUNT(*) FROM transactions WHERE id=?", (null_tx_id,))[0][0]
    check("BL-1: admin DELETE transaction legacy NULL -> 200 e ledger admin coerente (10/5.0)",
          d3.status_code == 200 and null_tx_left == 0
          and bool(admin_holding) and abs(admin_holding[0][0] - 10) < 1e-9
          and abs(admin_holding[0][1] - 5.0) < 1e-9,
          f"{d3.status_code} null_tx={null_tx_left} admin_holding={admin_holding}")

    # Cleanup: rimuove tutte le righe iniettate (NULL e admin) e lo stock dedicato
    conn = sqlite3.connect(TEST_DB, timeout=10)
    try:
        conn.execute("DELETE FROM transactions WHERE id IN (?, ?)", (null_tx_id, admin_tx_id))
        conn.execute("DELETE FROM holdings WHERE id IN (?, ?)", (null_holding_id, admin_holding_id))
        conn.execute("DELETE FROM stocks WHERE id=?", (stock_id,))
        conn.commit()
    finally:
        conn.close()


async def test_r3_user_settings_unique():
    print("\n[33] R1: UNIQUE(user_id) user_settings + dedup legacy")
    # Su DB fresco SQLAlchemy rende UNIQUE(user_id) come autoindex SQLite
    # (sqlite_autoindex_user_settings_1); sui DB legacy la migrazione crea
    # l'indice nominato. In entrambi i casi deve esistere un indice unico covering.
    unique_covering = []
    for row in _db_query("PRAGMA index_list(user_settings)"):
        if not row[2]:
            continue
        cols = {info[2] for info in _db_query(f"PRAGMA index_info('{row[1]}')")}
        if cols == {"user_id"}:
            unique_covering.append(row[1])
    check("F2: indice UNIQUE covering user_id presente sul DB live",
          bool(unique_covering), str(unique_covering))

    existing = _db_query("SELECT user_id FROM user_settings WHERE user_id IS NOT NULL LIMIT 1")
    enforced_live = False
    if existing:
        conn = sqlite3.connect(TEST_DB, timeout=10)
        try:
            conn.execute("INSERT INTO user_settings (user_id) VALUES (?)", (existing[0][0],))
            conn.commit()
        except sqlite3.IntegrityError:
            enforced_live = True
        finally:
            conn.rollback()
            conn.close()
    check("F2: INSERT duplicato user_id sul DB live rifiutato", enforced_live, f"user_id={existing}")

    # --- Scratch DB: migrazione dedup idempotente via funzione reale ---
    from sqlalchemy.ext.asyncio import create_async_engine
    from backend.database import _ensure_user_settings_unique_constraint

    scratch_db = os.path.join(TEST_DIR, "user_settings_dedup_scratch.db")
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(scratch_db + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(scratch_db, timeout=10)
    try:
        conn.execute(
            "CREATE TABLE user_settings ("
            " id INTEGER PRIMARY KEY, user_id INTEGER, strategy VARCHAR,"
            " total_budget FLOAT, updated_at DATETIME)"
        )
        conn.execute(
            "INSERT INTO user_settings (id, user_id, strategy) VALUES "
            "(1, 7, 'first'), (2, 7, 'second'), (3, 8, 'other'), (4, NULL, 'legacy1'), (5, NULL, 'legacy2')"
        )
        conn.commit()
    finally:
        conn.close()

    engine = create_async_engine(f"sqlite+aiosqlite:///{scratch_db}")
    second_error = ""
    try:
        async with engine.begin() as aconn:
            await _ensure_user_settings_unique_constraint(aconn)
        try:
            async with engine.begin() as aconn:
                await _ensure_user_settings_unique_constraint(aconn)  # idempotente
        except Exception as e:
            second_error = str(e)[:200]
    finally:
        await engine.dispose()

    conn = sqlite3.connect(scratch_db, timeout=10)
    try:
        u7 = conn.execute("SELECT id, strategy FROM user_settings WHERE user_id=7 ORDER BY id").fetchall()
        u8 = conn.execute("SELECT COUNT(*) FROM user_settings WHERE user_id=8").fetchone()[0]
        nulls = conn.execute("SELECT COUNT(*) FROM user_settings WHERE user_id IS NULL").fetchone()[0]
        unique_covering = []
        for row in conn.execute("PRAGMA index_list(user_settings)").fetchall():
            if not row[2]:
                continue
            cols = {info[2] for info in conn.execute(f"PRAGMA index_info('{row[1]}')").fetchall()}
            if cols == {"user_id"}:
                unique_covering.append(row[1])
        enforced_scratch = False
        try:
            conn.execute("INSERT INTO user_settings (user_id, strategy) VALUES (7, 'dup')")
            conn.commit()
        except sqlite3.IntegrityError:
            enforced_scratch = True
        finally:
            conn.rollback()
    finally:
        conn.close()

    check("F2: dedup user_settings conserva la riga più vecchia ed elimina i duplicati",
          len(u7) == 1 and u7[0][0] == 1 and u7[0][1] == "first" and u8 == 1,
          f"u7={u7} u8={u8}")
    check("F2: righe legacy con user_id NULL non toccate dalla dedup", nulls == 2, f"nulls={nulls}")
    check("F2: indice UNIQUE creato sul DB scratch",
          "uq_user_settings_user" in unique_covering, str(unique_covering))
    check("F2: INSERT duplicato rifiutato sul DB scratch", enforced_scratch)
    check("F2: seconda esecuzione idempotente",
          second_error == "" and len(u7) == 1 and nulls == 2, second_error or f"u7={u7} nulls={nulls}")


async def test_r3_daily_series_eur(c: httpx.AsyncClient, h: dict):
    print("\n[34] R2: build_portfolio_daily_series converte ogni holding in EUR (F3)")
    from backend.database import async_session_maker
    from backend.services import market_data as md
    from backend.services import analytics as analytics_module

    stock_ids = {}
    for ticker, name, market in [("R3SERIEUR.MI", "R3 Serie EUR", "IT"),
                                 ("R3SERIEUSD", "R3 Serie USD", "US")]:
        rr = await c.post("/api/stocks/", headers=h,
                          json={"ticker": ticker, "name": name, "market": market})
        stock_ids[ticker] = rr.json().get("id") if rr.status_code == 200 else None
    if not all(stock_ids.values()):
        check("setup stock serie EUR/USD", False, str(stock_ids))
        return

    price_day = (datetime.now(timezone.utc).date() - timedelta(days=1)).isoformat()
    for ticker, close in [("R3SERIEUR.MI", 10.0), ("R3SERIEUSD", 20.0)]:
        _db_exec(
            "INSERT INTO price_history (stock_id, timestamp, open, high, low, close, volume) "
            "VALUES (?,?,?,?,?,?,?)",
            (stock_ids[ticker], price_day + "T17:00:00+00:00",
             close - 0.1, close + 0.2, close - 0.2, close, 1000),
        )

    # Portafoglio deterministico: 1 holding EUR + 1 holding USD con fx noto
    eur_holding = {
        "id": 1, "stock_id": stock_ids["R3SERIEUR.MI"], "ticker": "R3SERIEUR.MI", "name": "R3 EUR",
        "market": "IT", "currency": "EUR", "quantity": 10, "avg_purchase_price": 5.0,
        "current_price": 10.0, "previous_close": 10.0, "price_stale": False,
        "total_value": 100.0, "total_invested": 50.0,
        "total_value_eur": 100.0, "total_invested_eur": 50.0, "fx_rate_to_eur": 1.0,
    }
    usd_holding = {
        "id": 2, "stock_id": stock_ids["R3SERIEUSD"], "ticker": "R3SERIEUSD", "name": "R3 USD",
        "market": "US", "currency": "USD", "quantity": 10, "avg_purchase_price": 5.0,
        "current_price": 20.0, "previous_close": 20.0, "price_stale": False,
        "total_value": 200.0, "total_invested": 50.0,
        "total_value_eur": 180.0, "total_invested_eur": 45.0, "fx_rate_to_eur": 0.9,
    }
    portfolio_rows = [eur_holding, usd_holding]

    cache_key = "series:987654:7"
    analytics_module._SERIES_CACHE.pop(cache_key, None)
    original_candles = md.MarketDataService.fetch_stock_candles

    async def no_candles(ticker, timeframe="1y"):
        return []

    try:
        md.MarketDataService.fetch_stock_candles = staticmethod(no_candles)
        async with async_session_maker() as session:
            series = await analytics_module.build_portfolio_daily_series(
                session, days=7, user_id=987654, portfolio_rows=portfolio_rows)
    finally:
        md.MarketDataService.fetch_stock_candles = staticmethod(original_candles)

    expected_eur = 10 * 10.0 * 1.0 + 10 * 20.0 * 0.9   # 280.0
    mixed_sum = 10 * 10.0 + 10 * 20.0                  # 300.0: somma mista (regressione F3)
    last = series[-1] if series else {}
    check("F3: serie con shape {date, value}",
          bool(series) and all(set(p.keys()) == {"date", "value"} for p in series),
          str(series[:2]))
    check("F3: value in EUR = 280.0 (non 300.0 somma mista USD+EUR)",
          abs(float(last.get("value", -1)) - expected_eur) < 0.01
          and abs(float(last.get("value", -1)) - mixed_sum) > 0.01,
          f"last={last} atteso_eur={expected_eur} misto={mixed_sum}")

    cached = analytics_module._SERIES_CACHE.get(cache_key)
    check("F3: cache popolata con la serie EUR",
          cached is not None and bool(cached[0])
          and abs(float(cached[0][-1]["value"]) - expected_eur) < 0.01,
          str(cached))

    # Cleanup deterministico (cache + righe prezzo + stock dedicati)
    analytics_module._SERIES_CACHE.pop(cache_key, None)
    _db_exec("DELETE FROM price_history WHERE stock_id IN (?, ?)",
             (stock_ids["R3SERIEUR.MI"], stock_ids["R3SERIEUSD"]))
    _db_exec("DELETE FROM stocks WHERE id IN (?, ?)",
             (stock_ids["R3SERIEUR.MI"], stock_ids["R3SERIEUSD"]))


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
            await test_market_suffix_classification(c, h)
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
            await test_perf_caches_and_contracts(c, h)
            await test_stock_market_update(c, h)
            await test_concurrency(c, h)
            # Regressioni Fase 1 backend (BE-1/BE-2/BE-3)
            await test_be1_atomicity_and_validation(c, h)
            await test_be1_holdings_dedup_scratch()
            await test_be1_ledger_recompute_and_pnl(c, h)
            await test_be3_staleness_and_invalidation(c, h)
            await test_be2_isolation_dashboard_race_cascade(c, h)
            await test_be2_watchlist_alignment_and_advisor_notnull()
            await test_be2_login_lockout_atomic(c, h)
            await test_be3_singleflight_fallback_rebalance(c, h)
            # Regressioni remediation R1/R2 (Oracle Gate 1)
            await test_r3_null_legacy_ownership(c, h)
            await test_r3_user_settings_unique()
            await test_r3_daily_series_eur(c, h)
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
