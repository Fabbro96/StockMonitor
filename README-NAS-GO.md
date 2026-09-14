# StockMon GO sul NAS (F2-212) — guida breve

Backend **Go read-only** + **SQLite** + **web embedded**, pensato per il
TerraMaster F2-212 (ARM64, 2 GB RAM).

## Perché Go + SQLite

- **RAM attesa 15–30 MB idle** (limite compose 64 MB): solo `net/http` stdlib,
  driver SQLite pure-Go (`modernc.org/sqlite`, niente CGO), cache in memoria
  con TTL + ETag. Niente interprete Python, niente worker Uvicorn.
- **Immagine `scratch` da ~20 MB**: binary statico 15 MB + CA certs + zoneinfo.
  Il Python era ~500 MB+ con dipendenze scientifiche.
- **Stesso file DB del Python**, aperto in `mode=ro`: il Python resta l'unico
  writer (alert, ingestione prezzi). Zero migrazioni, zero split-brain.
- **Web embedded** (`server-go/web/dist`, vanilla JS + canvas nativo, ~25 KB):
  la web Flutter è **dismessa** — si portava dietro ~37 MB di `canvaskit` WASM
  per una dashboard di cards e tabelle. Il JS qui fa login JWT, cards
  dashboard, watchlist, candele su canvas, refresh manuale + auto 300 s +
  `visibilitychange`, ETag/`If-None-Match`.

## Cutover dal Python (zero downtime)

Il Python oggi risponde su **:8000**. Il compose Go di default espone **:8001**
per il test parallelo (stesso `./data`, il Go legge in `ro`).

1. **Test parallelo** — Python invariato su :8000:
   `docker compose -f docker-compose.nas-go.yml up -d`
   Verifica `http://<IP-NAS>:8001/health` → `{"status":"ok"}`, login sulla
   dashboard `:8001/`, confronto dati con `:8000`.
2. **Cutover** — in `docker-compose.nas-go.yml` cambia la porta in
   `"8000:8000"`, poi `up -d`; ferma lo stack Python
   (`docker compose -f docker-compose.nas.yml stop stock-monitor` o `down`
   se non serve più). Stesso `SECRET_KEY` nei due compose: i JWT restano validi.
3. **Rollback** — riavvia il Python su :8000, riporta il Go su :8001 o
   spegnilo. Il DB non è mai scritto dal Go (`DB_MODE=ro`).

## Backup

`scripts/sqlite-backup.sh` fa checkpoint `PASSIVE` + `.backup` di sqlite3
(mai `cp` a caldo col WAL aperto) e tiene 7 giorni in `./data/backups`.
Schedulalo sul NAS (cron 03:00) **prima** del cutover e dopo.

## Nota mobile

L'**app Flutter resta** per l'APK Android (mobile nativo). Viene dismessa solo
la build **web** Flutter (niente più `canvaskit` 37 MB): da browser si usa la
dashboard Go embedded. Niente WUD sullo stack Go (RAM): update manuali via
`docker compose pull && up -d`.
