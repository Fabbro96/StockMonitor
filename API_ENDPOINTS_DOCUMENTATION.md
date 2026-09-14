# Stock Monitor API Endpoints Documentation

## Base URL

All endpoints are prefixed with `/api`. The Flutter client calls them through
`app/lib/core/api_client.dart` (Dio) and the typed wrappers in
`app/lib/core/api/*.dart`. The base URL is resolved at runtime:

- **web**: same origin that serves the Flutter build (`Uri.base.resolve('/api')`);
- **Android/desktop**: `<server configured in the app>/api`, with
  `--dart-define=API_BASE_URL` as build-time fallback.

## Authentication & status codes

All `/api/*` endpoints require a JWT (`Authorization: Bearer <token>`) except
`/api/auth/login` and `/api/auth/logout`. Repeated common status codes:

- **307**: missing trailing slash on collection endpoints (`/api/advice/`,
  `/api/portfolio/`, `/api/watchlist/`) → redirect to the slash URL.
- **401**: missing/invalid/expired token, wrong credentials.
- **403**: admin-only endpoint called by a non-admin user (or disabled account on login).
- **404**: not found or **ownership** violation (another user's row is hidden, never 403).
- **409**: data conflicts (duplicate stock creation, insufficient quantity on SELL, batch rules).
- **422**: validation errors — `detail` can be a **string** (custom checks) or an
  **array** of objects (FastAPI body validation).
- **429**: login lockout (5 failed attempts → 15 min) or AI rate limit (12 AI calls/min).
- **503**: SQLite temporarily busy (`database temporaneamente occupato, riprova`).

---

## 1. AUTH ENDPOINTS

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/auth/login` | **POST** | `username`, `password` (JSON body) | `{ access_token, token_type, username, is_admin }` | Login. `401` wrong credentials, `403` disabled account, `429` lockout after 5 failed attempts (15 min); used by `auth_api.dart` + auth controller |
| `/auth/logout` | **POST** | None (public) | `{ status, message }` | Logout; clears the HttpOnly cookie server-side, the client clears the stored token; used by `auth_api.dart` |
| `/auth/me` | **GET** | None (needs auth token) | `{ id, username, is_admin, is_active, created_at, last_login }` | Get current user (including `is_admin`); used by `auth_api.dart` |
| `/auth/change-password` | **POST** | `current_password`, `new_password` (min 8 chars, JSON body) | `{ status, message }` | Password change; `400` when the current password is wrong; used by `auth_api.dart` |

---

## 2. ADMIN USER MANAGEMENT

Admin only (`403` for non-admin users).

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/auth/users` | **GET** | None (admin only) | `[{ id, username, is_admin, is_active, created_at, last_login }]` | List all users; used by `auth_api.dart` (settings UI) |
| `/auth/users` | **POST** | `username` (3–50 chars), `password` (min 8 chars), `is_admin` (JSON body) | Created user object | Create user; `400` if the username already exists; used by `auth_api.dart` |
| `/auth/users/{user_id}` | **DELETE** | `user_id` (path, admin only) | `{ status, message }` | Delete user; `400` if deleting yourself, `404` if missing; used by `auth_api.dart` |
| `/auth/users/{user_id}/reset-password` | **PUT** | `new_password` (min 8 chars, JSON body, admin) | `{ status, message }` | Admin reset password (also clears lockout); exposed in the Flutter settings screen via `auth_api.dart` |

---

## 3. STOCKS & DEEP-DIVE

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/stocks/search?q=` | **GET** | `q` (URL query param, required — **not** `query`) | `[{ ticker, name, ... }]` | Search ticker; used by `stocks_api.dart` |
| `/stocks/{ticker}/details` | **GET** | `ticker` (path param) | Full stock details: `{ ticker, name, current_price, currency, change_abs, change_percent, market, fifty_two_week_low, fifty_two_week_high, fifty_two_week_pct, pe_ratio, eps, dividend_yield, beta, summary, technical: { rsi_14, rsi_status, rsi_badge, sma_20, sma_50, trend }, market_cap, avg_volume }` | Used by `stocks_api.dart` (stock detail modal, dashboard, advice, portfolio) |
| `/stocks/{ticker}/candles?timeframe=` | **GET** | `ticker` (path), `timeframe` (query, default `1m`; one of `1d`, `1w`, `1m`, `6m`, `1y`, `5y`) | Candlestick array `[{ time, open, high, low, close, value, volume }]`: `value` is the close; `time` is an **int epoch** for `1d`/`1w` and a `YYYY-MM-DD` **string** otherwise. Invalid timeframe → `422` | Used by `stocks_api.dart` |
| `/stocks/{ticker}` | **PUT** | `market` (JSON body: `{ market }`, one of `IT`/`US`/`EU`) | `{ ticker, market, currency }` | Update stock market (currency follows market); `404` unknown ticker, `422` invalid market; used by `stocks_api.dart` |

---

## 4. WATCHLIST

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/watchlist/` | **GET** | None (needs auth token) | Array of watchlist items with deep-dive data | Used by `watchlist_api.dart` |
| `/watchlist/` | **POST** | `ticker`, `notes` (opt), `alert_above` (opt), `alert_below` (opt) (JSON body) | `{ status, message, id }`; `status` is `"exists"` when the ticker was already present (notes/alerts are then updated) | Add to watchlist; used by `watchlist_api.dart` |
| `/watchlist/{item_id}/alert` | **PUT** | `item_id` (path), `alert_above` (opt), `alert_below` (opt) (JSON body) | `{ status, message }` | Update alert rules; **both thresholds are overwritten**, `null` clears an alert; `404` for another user's item; used by `watchlist_api.dart` |
| `/watchlist/{item_id}` | **DELETE** | `item_id` (path param) | `{ status, message }` | Remove from watchlist; `404` for another user's item; used by `watchlist_api.dart` |
| `/watchlist/ticker/{ticker}` | **DELETE** | `ticker` (path param) | `{ status, message }` | Remove by ticker (no error if not watched); exposed by `watchlist_api.dart`, the UI normally deletes by id |

---

## 5. PORTFOLIO

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/portfolio/` | **GET** | None (needs auth token) | Array of holdings with current prices | Used by `portfolio_api.dart` (`holdings()`) |
| `/portfolio/summary` | **GET** | None (needs auth token) | `{ total_value, total_invested, total_pnl, total_pnl_percent, daily_pnl, daily_pnl_percent, holdings_count, top_gainer, top_loser, market_allocation: { IT, US, EU }, estimated_annual_dividends, estimated_dividend_yield, fx_usd_eur }` | Used by `portfolio_api.dart` (`summary()`) and dashboard stat cards |
| `/portfolio/seed-demo` | **POST** | None (needs auth token) | `{ status, message, created_holdings, created_watchlist }` | Seed demo data; used by `portfolio_api.dart` |
| `/portfolio/risk-metrics?days=` | **GET** | `days` (query, default 180, min 30) | `{ days_analyzed, series_start, series_end, max_drawdown_pct, annualized_volatility_pct, sharpe_ratio, annualized_return_pct, weighted_beta, risk_free_rate_pct, current_value, betas? }` (`betas` = per-ticker map, present only with holdings) | Used by `portfolio_api.dart` (`riskMetrics()`) |
| `/portfolio/benchmarks?days=&tickers=` | **GET** | `days` (default 90, min 7), `tickers` (opt, comma-sep) | `{ start_date, end_date, portfolio: [{ date, growth_pct }], benchmarks: { ticker: { name, flag, data: [{ date, growth_pct }] } } }` | Used by `portfolio_api.dart` (`benchmarks()`) |
| `/portfolio/holdings` | **POST** | `ticker` or `stock_id`, `quantity` (>0), `avg_purchase_price` (>0), `purchase_date` (opt), `notes` (opt) (JSON body) | Created/merged holding object | Add holding; `400` when the resulting quantity would be ≤ 0; used by `portfolio_api.dart` |
| `/portfolio/holdings/{holding_id}` | **PUT** | `holding_id` (path), `quantity` (opt), `avg_purchase_price` (opt), `purchase_date` (opt), `notes` (opt) (JSON body) | Updated holding; `404` for another user's row | Inline edit; used by `portfolio_api.dart` |
| `/portfolio/batch` | **PUT** | `holdings` (JSON array: `[{ id, quantity, avg_purchase_price, notes }]`) | `{ status, updated_count }` | Batch save modifications; used by `portfolio_api.dart` |
| `/portfolio/holdings/{holding_id}` | **DELETE** | `holding_id` (path param) | `{ status, message }` | Delete holding; used by `portfolio_api.dart` |
| `/portfolio/transactions` | **GET** | `type` (opt), `ticker` (opt), `limit` (default 100), `skip` (default 0) as query params | Array of transaction objects (`transaction_date` is a string) | Used by `portfolio_api.dart` (`transactions()`) |
| `/portfolio/transactions` | **POST** | `ticker`, `type` (`BUY`/`SELL`/`DIVIDEND`), `quantity`, `price`, `fee`, `transaction_date` (opt), `notes` (opt) (JSON body) | `{ status, transaction: { id, ticker, type, quantity, price, fee, realized_pnl, currency, transaction_date } }` | Register transaction; `400` validation, `409` insufficient quantity on SELL; used by `portfolio_api.dart` |
| `/portfolio/transactions/{tx_id}` | **DELETE** | `tx_id` (path param) | `{ status, message }` | Delete transaction and recompute the position; used by `portfolio_api.dart` |
| `/portfolio/realized-pnl` | **GET** | None (needs auth token) | `{ total_realized_capital_gains, total_dividends_collected, total_fees_paid, net_realized_profit, trade_count, win_trades, loss_trades, win_rate_percent, transactions_count }` | Used by `portfolio_api.dart` |
| `/portfolio/dividends` | **GET** | None (needs auth token) | `{ holdings: [{ ticker, name, market, currency, quantity, current_price, avg_purchase_price, dividend_yield_pct, yield_on_cost_pct, annual_dividend_per_share, annual_income_eur, monthly_income_eur }], total_annual_dividend_eur, total_monthly_dividend_eur, portfolio_total_value, portfolio_yield_on_cost }` | Used by `portfolio_api.dart` (`dividends()`) |
| `/portfolio/import` | **POST** | `file` (multipart/form-data CSV, `,` or `;` separator) | `{ status, imported, updated, errors }` | Import CSV via `portfolio_api.dart` (`importCsv()`, multipart upload) |
| `/portfolio/export?format=` | **GET** | `format` (query: `csv` or `json`, default `csv`) | CSV content or JSON array | Export via `portfolio_api.dart` (`exportCsv()`, binary download; 401 handled by the client) |

---

## 6. REBALANCER

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/portfolio/rebalance/targets` | **GET** | None (needs auth token) | `[{ id, name, target_percent, scope_type, scope_value }]` | Load targets; used by `portfolio_api.dart` |
| `/portfolio/rebalance/targets` | **POST** | `name`, `target_percent` (0–100), `scope_type` (`MARKET`/`TICKERS`/`CASH`), `scope_value` (JSON body) | Created target object; `400` if the target sum would exceed 100% | Add target; used by `portfolio_api.dart` |
| `/portfolio/rebalance/targets/{target_id}` | **DELETE** | `target_id` (path param) | `{ status }` | Delete target; used by `portfolio_api.dart` |
| `/portfolio/rebalance/preview` | **POST** | `extra_cash` (opt, JSON body: `{ extra_cash }`) | `{ extra_cash, targets_sum_percent, allocations, orders, orders_count, total_value, total_buy_value, total_sell_value, portfolio_empty }`; `400` if no target is configured | Preview rebalance plan; used by `portfolio_api.dart` |

---

## 7. DASHBOARD & LIVE MARKETS

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/dashboard/` | **GET** | None (needs auth token) | `{ portfolio_summary, recent_advices, active_alerts_count, market_status: { IT, US, EU, ANY_OPEN, details } }` | Main dashboard data; used by `dashboard_api.dart` |
| `/dashboard/market-status` | **GET** | None (needs auth token) | `{ IT, US, EU, ANY_OPEN, details }` — stesso blocco `market_status` di `/dashboard/`, senza summary/advices | Lightweight market clocks; used by `dashboard_api.dart` |
| `/dashboard/indices` | **GET** | None (needs auth token) | `[{ ticker, name, price, change_percent, ... }]` (real-time) | Marquee ticker; used by `dashboard_api.dart` |
| `/dashboard/heatmap` | **GET** | None (needs auth token) | `[{ ticker, name, market, currency, current_price, change_percent, change_abs, day_high, day_low, volume, stale }]` | Heatmap; used by `dashboard_api.dart` |
| `/dashboard/performance?days=` | **GET** | `days` (query, default 30), needs auth token | `{ data: [{ date, value }], source, points }` | Performance chart data; used by `dashboard_api.dart` |

---

## 8. ADVICE & AI ON-DEMAND

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/advice/` | **GET** | `skip` (default 0), `limit` (default 20, **max 200**), `days` (default 7), `market`, `action`, `date` (query params — **no `page`, no `q`**, search is client-side) | Array of advice cards | Used by `advice_api.dart` (`list()`); "load more" while `length == limit` |
| `/advice/latest` | **GET** | None (last 7 days) | Latest 4 advices (items have **no** `ticker`/`name`) | Used by `advice_api.dart` |
| `/advice/{advice_id}/follow` | **POST** | `advice_id` (path param) | `{ status, followed }` | Toggle follow status (`/toggle-follow` is an alias); `404` for another user's advice; used by `advice_api.dart` |
| `/advice/generate?force=` | **POST** | `force` (query, default false) | `{ status, generated_count, advices }` | Generate new analysis; `400` when all markets are closed and `force=false`, `429` AI rate limit (12/min); used by `advice_api.dart` |
| `/advice/stock/{ticker}` | **POST** | `ticker` (path param) | `{ ticker, name, action, action_label, confidence, timeframe, target_price, upside_potential_pct, stop_loss, summary, bull_case, bear_case, technical_verdict, operational_strategy, holding_context: { quantity, avg_purchase_price, current_pnl_abs, current_pnl_pct } oppure null }` — **no `current_price`**; `429` AI rate limit | On-demand stock analysis (Gemini, up to ~120s, client timeout 120s); used by `advice_api.dart` |

---

## 9. SETTINGS

| Endpoint | Method | Required Parameters | Response Format | Usage |
|---|---|---|---|---|
| `/settings/` | **GET** | None (needs auth token) | `{ id, strategy, markets: [IT,US,EU], budget, total_budget, reportFreq, reportTimes, apiStatus: { telegram, gemini, gemini_model, reddit } }` | Used by `settings_api.dart` |
| `/settings/` | **PUT** | `strategy`, `budget` **or** `total_budget`, `markets` (list or CSV string), `reportFreq` **or** `advice_frequency`, `reportTimes` **or** `advice_times` (JSON body) | Updated settings object **without `apiStatus`**; `400` when no valid field is sent | Used by `settings_api.dart` |
| `/settings/alerts` | **GET** | None (needs auth token) | `[{ id, stock_id, ticker, name, direction, threshold, threshold_percent, active }]` | Used by `settings_api.dart` |
| `/settings/alerts` | **POST** | `ticker` **or** `stock_id`, `threshold` **or** `threshold_percent` (>0), `direction` (`UP`/`DOWN`/`BOTH`, default `BOTH`), `active` (JSON body) | Created alert rule **without `name`/`threshold_percent`**: `{ id, stock_id, ticker, direction, threshold, active }`; `400` invalid threshold/direction, `409` stock creation race | Used by `settings_api.dart` |
| `/settings/alerts/{rule_id}` | **DELETE** | `rule_id` (path param) | `{ status }` | Used by `settings_api.dart` (there is **no update endpoint**) |
| `/settings/telegram/test` | **POST** | None (needs auth token) | `{ status }` | Test Telegram connection; used by `settings_api.dart` |

---

## 10. NOTE E LIMITI NOTI

1. **Export CSV** — nessuna fetch fuori dal client: `portfolio_api.dart`
   (`exportCsv()`) scarica i byte e il 401 è gestito da `ApiClient`.
2. **Watchlist per ticker** — `DELETE /api/watchlist/ticker/{ticker}` esiste nel
   backend ma non è usato dal client Flutter; la UI rimuove sempre per id
   (`404` se l'elemento non appartiene all'utente).
3. **Reset password admin** — endpoint e UI Flutter disponibili (`auth_api.dart`
   + schermata Impostazioni).
4. **No token refresh/revocation** — scelta di design: il JWT dura 7 giorni
   (`ACCESS_TOKEN_EXPIRE_DAYS`, `config.py`); su `401` il client pulisce la
   sessione e riporta al login.
5. **`PUT /api/stocks/{ticker}`** — aggiorna il mercato (`IT`/`US`/`EU`) e la
   valuta derivata; usato dal market editor.
6. **Import multipart** — `importCsv()` invia `FormData` (necessario per il file
   upload) ma resta dentro `ApiClient`.
7. **Timestamp misti** — formati eterogenei (spazio vs `T`, senza timezone): il
   client fa parsing tollerante senza sollevare eccezioni.

---

## 11. ENDPOINT USAGE SUMMARY BY CLIENT MODULE

| Flutter module (`app/lib/core/api/`) | API methods |
|---|---|
| **auth_api.dart** | login, logout, me, changePassword, users, createUser, deleteUser, resetUserPassword |
| **stocks_api.dart** | search, details, candles, updateMarket |
| **watchlist_api.dart** | list, add, updateAlert, remove |
| **portfolio_api.dart** | holdings, summary, riskMetrics, benchmarks, seedDemo, addHolding, deleteHolding, batchUpdateHoldings, transactions, createTransaction, deleteTransaction, realizedPnl, dividends, rebalanceTargets, addRebalanceTarget, deleteRebalanceTarget, rebalancePreview, importCsv, exportCsv |
| **dashboard_api.dart** | dashboard, indices, heatmap, performance |
| **advice_api.dart** | list, latest, toggleFollow, generate, analyzeStock |
| **settings_api.dart** | getSettings, updateSettings, getAlertRules, addAlertRule, deleteAlertRule, testTelegram |
| **api_client.dart** | Dio client condiviso: base URL, Bearer, 401→sessione scaduta, timeout, upload/download binari |

---

## 12. ERROR HANDLING PATTERNS (`app/lib/core/api_client.dart`)

1. **401 Unauthorized** (non-login) → callback `onUnauthorized`: pulizia token,
   redirect a `/#/login`, messaggio `Sessione non valida o scaduta. Effettua il login.`
2. **204 / body vuoto** → `null` (nessuna eccezione).
3. **Body non-JSON** → `null` (degradazione controllata); i payload attesi come
   lista sono verificati dai moduli API, che lanciano `ApiException` su shape errata.
4. **Status non-ok** → `ApiException(message)` con messaggio da `detail`
   (stringa, lista 422 di `msg` uniti con `'; '`, o oggetto JSON-encodato),
   altrimenti `message`, altrimenti `API Error: {status}`.
5. **Errori di rete/timeout** → `ApiException` con messaggio Dio (timeout:
   connect/send 10s, receive 20s; le chiamate AI usano 120s).
6. **Web** → il client usa l'origine della pagina per `/api`; su Android l'origin
   è configurabile e un cambio di server azzera la sessione.

Le schermate gestiscono gli errori via `AsyncValue`/`try-catch` + toast
(`showAppToast`), con empty state e retry.

---

## 13. AUTHENTICATION FLOW

1. **Login**: POST `/api/auth/login` con le credenziali → `{ access_token,
   token_type, username, is_admin }` (il backend imposta anche un cookie
   HttpOnly, ma il client usa il Bearer).
2. **Token storage**: Android/iOS `flutter_secure_storage`; web/desktop
   `shared_preferences` (LAN HTTP: accepted trade-off).
3. **Automatic auth**: `ApiClient` aggiunge `Authorization: Bearer <token>` a
   ogni richiesta se il token è presente.
4. **401 handling**: pulizia della sessione e redirect a `/#/login`; al login
   scaduto la UI mostra l'avviso inline.
5. **Session expiry**: token valido **7 giorni** (`ACCESS_TOKEN_EXPIRE_DAYS`).
6. **Logout**: POST `/api/auth/logout` (best-effort) + pulizia del token locale e
   redirect al login.