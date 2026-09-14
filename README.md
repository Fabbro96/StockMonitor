# 📈 Stock Monitor

Web app self-hosted per il monitoraggio dei mercati (IT/US/EU) e la gestione del
portafoglio, pensata per girare su NAS ARM64 con 2 GB di RAM. Include consigli
finanziari AI (Google Gemini) e un bot Telegram interattivo.

Un'unica codebase Flutter produce il **sito web** (build servita dal backend
FastAPI a `/`) e l'**app Android** (APK), sullo stesso backend Python.

---

## ✨ Funzionalità

- **Client Flutter unico** (web + Android) con UI light/dark responsive e **zero
  richieste esterne**: font di sistema, nessuna CDN, grafici con `fl_chart`.
- **Monitoraggio orario** dei mercati: prezzi scaricati con un'unica richiesta
  batch e fallback "stale" quando Yahoo Finance risponde 429/403.
- **Portafoglio multi-utente**: CRUD, P&L live, conversione FX EUR/USD,
  import/export CSV.
- **Analytics**: Max Drawdown, volatilità annualizzata, Sharpe Ratio, Beta pesato,
  confronto benchmark (`^GSPC`, `FTSEMIB.MI`) e rebalancer con allocazioni target.
- **AI & notizie**: consigli finanziari bilanciati (5–10) via Gemini, analisi
  on-demand per ticker e sentiment multi-fonte zero-auth (Yahoo News, Google News
  RSS, Reddit pubblico).
- **Sicurezza**: JWT (header `Authorization: Bearer`), utenti admin-only, lockout
  anti brute-force.
- **Bot Telegram**: `/value`, `/radar`, `/advice <TICKER>`.
- **App Android**: stesso client, indirizzo del server configurabile a runtime.

## 🛠️ Stack

- **Backend**: Python 3.12, FastAPI, SQLAlchemy 2.0 async + SQLite in modalità WAL.
- **Client**: Flutter 3.47 / Dart 3.13 — `flutter_riverpod` (stato), `go_router`
  (routing con hash URL strategy), `dio` (HTTP, Bearer e gestione 401),
  `fl_chart` (grafici). Build web e APK dalla stessa codebase.
- **Dati di mercato**: yfinance con timeout HTTP espliciti, executor dedicato
  bounded e cache TTL in-process.
- **AI/Servizi**: google-genai (Gemini), python-telegram-bot, httpx, APScheduler.

## 📂 Struttura del repository

- `app/` — client Flutter: sorgenti in `lib/` (`core/`, `features/`, `shell/`,
  `theme/`, `widgets/`) e test in `test/`. Produce web e APK.
- `backend/` — API FastAPI (`main.py`, `routers/`, `services/`, `models/`).
- `tests/` — suite end-to-end backend (`e2e_test.py`).
- Il vecchio `frontend/` HTML/JS è stato rimosso: la UI è solo Flutter (storia git
  a parte).

## 🚀 Performance & NAS

- Fetch prezzi **orario in batch** (una richiesta per tutti i ticker attivi, budget
  dedicato per il job di background).
- **Retention automatica** del DB: `price_history` 400 giorni, `sentiments`
  30 giorni, cleanup notturno a batch.
- Build web servita a root con **`no-cache, must-revalidate`** su tutto l'output
  Flutter (gli asset non sono content-hashed e il service worker è dismesso);
  `/api/*` e `/health` restano senza header di cache.
- **1 worker** uvicorn e limiti risorse Docker: **768 MB RAM / 1.5 CPU** per l'app
  (WUD: 256 MB / 0.5 CPU).

## 🧑💻 Sviluppo locale

```bash
# Backend (serve anche app/build/web se presente)
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn backend.main:app --reload
```

```bash
# Client web in hot reload
cd app
flutter run -d chrome
```

> Nota: sul web il client chiama l'API sulla **stessa origine della pagina**
> (`Uri.base.resolve('/api')`). Per provare i flussi completi apri
> `http://localhost:8000` dopo `flutter build web`: in assenza di `WEB_DIR` il
> backend ripiega sulla build in `app/build/web`. `flutter run -d chrome` resta
> comodo per l'hot reload della sola UI.

```bash
# Analisi statica, test e build
cd app
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
flutter build apk --release
```

## 📱 App Android

- **Quale APK installare**: la CI compila con `--split-per-abi` e pubblica i
  3 APK per-ABI nell'artifact `stock-monitor-apk`. Sui telefoni moderni
  installa `app-arm64-v8a-release.apk` (`armeabi-v7a` solo per dispositivi
  vecchi a 32 bit, `x86_64` per emulatori). Non mescolare ABI diverse tra update
  successivi: ogni ABI ha un versionCode dedicato, quindi aggiorna sempre con un
  APK della stessa ABI già installata.
- **Primo avvio**: inserisci l'indirizzo del backend (es. `http://<IP-NAS>:8000`)
  nel campo mostrato quando la build non ha un `API_BASE_URL` di default.
- L'indirizzo si può modificare dalla sezione **Server** delle Impostazioni; il
  cambio di server azzera la sessione e riporta al login.
- **Cleartext LAN** consentito da `network_security_config` (HTTP in rete locale).
- **Firma release**: con `app/android/key.properties` (git-ignored; stessi
  parametri `storeFile`/`storePassword`/`keyAlias`/`keyPassword`, generati dai
  secrets CI quando presenti) l'APK è firmato con la chiave release. Senza il file
  si ripiega sulla **debug key** (scelta documentata, nessuna distribuzione Play
  Store); un APK debug-signed non si aggiorna sopra uno release-signed, quindi in
  quel caso va **disinstallata** la versione precedente.
- **Android 17**: la rete locale richiederà il permesso runtime
  `ACCESS_LOCAL_NETWORK`; il `targetSdk` attuale è 36 e non va alzato senza gestire
  quel permesso.
- **Export CSV**: il salvataggio su file è supportato su **Android 10+**; su
  versioni precedenti usa la versione web.

## 📦 Deploy su NAS (file unico)

Sul NAS serve solo `docker-compose.nas.yml`: copialo in una cartella (es.
`/home/<utente>/docker/stock_monitor`) e avvia:

```bash
docker compose up -d
```

L'immagine Docker è **multi-stage**: lo stage `webbuilder` parte da
`debian:bookworm-slim` e installa il **tarball ufficiale di Flutter pinnato**
(`ARG FLUTTER_VERSION=3.47.2`, checkout configurato con `safe.directory`) perché
il tag `ghcr.io/cirruslabs/flutter:3.47.2` non esiste; compila la build web e la
copia in `/app/web`, dove il backend la serve a root. `FLUTTER_VERSION` va
aggiornato insieme al vincolo SDK di `app/pubspec.yaml`. Non serve più montare
`frontend/`. L'app risponde su
`http://<IP-NAS>:8000/`. L'auto-update è gestito da
**What's Up Docker (WUD 8.x)**, che controlla `ghcr.io/fabbro96/stockmonitor:latest`
ogni 2 minuti e ricrea il container quando cambia il digest. La UI di WUD è su
`http://<IP-NAS>:3001` (host 3001 perché la 3000 è occupata da AdGuard Home).

> ⚠️ Prima del primo avvio cambia `SECRET_KEY`, `ADMIN_PASSWORD` e `GEMINI_API_KEY`
> nel compose (il placeholder è `your_gemini_api_key_here`).
>
> Per l'accesso a WUD genera l'hash della password con
> `htpasswd -nb admin 'LaTuaPassword'` e incollalo in
> `WUD_AUTH_BASIC_ADMIN_HASH` raddoppiando i `$` (es. `$$apr1$$xxxx$$yyyy`).
>
> Il container gira volutamente come **root**: il bind-mount `./data` contiene il
> database SQLite creato dal container precedente e un UID non-root potrebbe non
> avere i permessi di scrittura. Rischio accettato su LAN.

Tutti i dati (utenti, portafoglio, storico) restano in `./data/` e sopravvivono
agli aggiornamenti dell'immagine.

### 💾 Backup & rollback

Prima di un deploy/update fai un backup del DB (SQLite è in modalità **WAL**:
va copiato a container fermo oppure con `.backup`):

```bash
# Backup "sicuro": ferma il container e copia DB + eventuali -wal/-shm
docker compose stop stock-monitor
cp -a data/stock_monitor.db "data/stock_monitor.db.bak-$(date +%Y%m%d-%H%M)"
# ripeti per data/stock_monitor.db-wal e -shm se presenti
docker compose start stock-monitor

# Alternativa senza fermare il container (se sqlite3 è installato)
sqlite3 data/stock_monitor.db ".backup 'data/stock_monitor.db.bak-$(date +%Y%m%d-%H%M%S)'"
```

**Rollback** alla versione precedente:

- `git revert <commit>` + push su `main`: WUD rileva il nuovo digest e riporta
  l'immagine precedente in ~2 minuti.
- Oppure usa il tag immutabile `sha-xxxxxxx` pubblicato da `docker-publish.yml`:
  imposta `image: ghcr.io/fabbro96/stockmonitor:sha-xxxxxxx` nel compose e lancia
  `docker compose up -d`; finché resta pinnato, WUD non lo aggiorna da solo.

Il primo avvio di una nuova versione applica sul DB migrazioni **additive**: il
backup è la via sicura per tornare indietro.

## 🧪 Test

```bash
# Backend (DB temporaneo in /tmp, non tocca i dati reali)
.venv/bin/python tests/e2e_test.py

# Client Flutter
cd app && flutter analyze && flutter test
```

La suite end-to-end (**oltre 300 check**) copre autenticazione, CRUD,
portafoglio/watchlist, metriche di rischio, benchmark, rebalancer, fallback
Yahoo, concorrenza SQLite/WAL, retention, contratti REST e serving della build web
Flutter.

I workflow GitHub Actions (`docker-publish.yml`, `android-release.yml`) eseguono i
check (`flutter analyze` + `flutter test` e suite backend) prima di pubblicare
l'immagine su GHCR e di produrre gli artifact **APK release** e **build web**.
