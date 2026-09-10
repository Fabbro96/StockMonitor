# 📈 Stock Monitor

Web app self-hosted per il monitoraggio dei mercati (IT/US/EU) e la gestione del
portafoglio, pensata per girare su NAS ARM64 con 2 GB di RAM. Include consigli
finanziari AI (Google Gemini) e un bot Telegram interattivo.

---

## ✨ Funzionalità

- **UI minimal light/dark**, responsive e con **zero richieste esterne**: i grafici
  usano Lightweight Charts vendorizzato in `frontend/vendor/` (licenza inclusa).
- **Monitoraggio orario** dei mercati: prezzi scaricati con un'unica richiesta
  batch e fallback "stale" quando Yahoo Finance risponde 429/403.
- **Portafoglio multi-utente**: CRUD, P&L live, conversione FX EUR/USD,
  import/export CSV.
- **Analytics**: Max Drawdown, volatilità annualizzata, Sharpe Ratio, Beta pesato,
  confronto benchmark (`^GSPC`, `FTSEMIB.MI`) e rebalancer con allocazioni target.
- **AI & notizie**: consigli finanziari bilanciati (5–10) via Gemini, analisi
  on-demand per ticker e sentiment multi-fonte zero-auth (Yahoo News, Google News
  RSS, Reddit pubblico).
- **Sicurezza**: JWT in cookie `HttpOnly`, utenti admin-only, lockout anti
  brute-force.
- **Bot Telegram**: `/value`, `/radar`, `/advice <TICKER>`.

## 🛠️ Stack

- **Backend**: Python 3.12, FastAPI, SQLAlchemy 2.0 async + SQLite in modalità WAL.
- **Dati di mercato**: yfinance con timeout HTTP espliciti, executor dedicato
  bounded e cache TTL in-process.
- **AI/Servizi**: google-genai (Gemini), python-telegram-bot, httpx, APScheduler.

## 🚀 Performance & NAS

- Fetch prezzi **orario in batch** (una richiesta per tutti i ticker attivi, budget
  dedicato per il job di background).
- **Retention automatica** del DB: `price_history` 400 giorni, `sentiments`
  30 giorni, cleanup notturno a batch.
- Asset statici **versionati (`?v=`)** con `Cache-Control` lungo e `immutable`;
  HTML sempre rivalidato.
- **1 worker** uvicorn e limiti risorse Docker: **768 MB RAM / 1.5 CPU**.

## 📦 Deploy su NAS (file unico)

Sul NAS serve solo `docker-compose.nas.yml`: copialo in una cartella (es.
`/home/<utente>/docker/stock_monitor`) e avvia:

```bash
docker compose up -d
```

L'app risponde su `http://<IP-NAS>:8000/`. L'auto-update è gestito da
**Watchtower**, che controlla `ghcr.io/fabbro96/stockmonitor:latest` ogni ora e
riavvia il container quando esce una nuova immagine.

> ⚠️ Prima del primo avvio cambia `SECRET_KEY`, `ADMIN_PASSWORD` e `GEMINI_API_KEY`
> nel compose (il placeholder è `your_gemini_api_key_here`).
>
> Il container gira volutamente come **root**: il bind-mount `./data` contiene il
> database SQLite creato dal container precedente e un UID non-root potrebbe non
> avere i permessi di scrittura. Rischio accettato su LAN.

Tutti i dati (utenti, portafoglio, storico) restano in `./data/` e sopravvivono
agli aggiornamenti dell'immagine.

## 🧪 Test

```bash
.venv/bin/python tests/e2e_test.py
```

Suite end-to-end (**180 check**) su DB temporaneo in `/tmp`: autenticazione, CRUD,
portafoglio/watchlist, metriche di rischio, benchmark, rebalancer, fallback Yahoo,
concorrenza SQLite/WAL, retention e contratti REST. Non tocca i dati reali.
