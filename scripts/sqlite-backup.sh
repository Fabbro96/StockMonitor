#!/usr/bin/env bash
# sqlite-backup.sh — backup online di SQLite SENZA cp a caldo.
#
# Uso:
#   ./scripts/sqlite-backup.sh [DB_PATH]
#
# Env override: DB_PATH (default ./data/stock_monitor.db),
#   BACKUP_DIR (default ./data/backups), RETENTION_DAYS (default 7).
#
# Strategia: checkpoint PASSIVE (riversa il WAL senza bloccare il writer)
# + API .backup di sqlite3 (copia transazionale consistente) + retention 7gg.
# Da schedulare sul NAS (cron giornaliero 03:00) o come job manuale.
set -euo pipefail

DB="${1:-${DB_PATH:-./data/stock_monitor.db}}"
BACKUP_DIR="${BACKUP_DIR:-./data/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

command -v sqlite3 >/dev/null 2>&1 || { echo "ERRORE: sqlite3 non installato" >&2; exit 1; }
[ -f "$DB" ] || { echo "ERRORE: DB non trovato: $DB" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
DST="$BACKUP_DIR/stock_monitor-$TS.db"

echo "Checkpoint PASSIVE su $DB ..."
sqlite3 "$DB" "PRAGMA wal_checkpoint(PASSIVE);"

echo "Backup online -> $DST ..."
sqlite3 "$DB" ".backup '$DST'"

echo "Verifica integrità backup ..."
CHECK="$(sqlite3 "$DST" "PRAGMA integrity_check;")"
if [ "$CHECK" != "ok" ]; then
  echo "ERRORE: integrity_check fallito: $CHECK" >&2
  rm -f "$DST"
  exit 1
fi

echo "Retention: tengo ultimi $RETENTION_DAYS giorni in $BACKUP_DIR ..."
find "$BACKUP_DIR" -maxdepth 1 -name 'stock_monitor-*.db' -mtime +"$RETENTION_DAYS" -print -delete

ls -lh "$DST"
echo "OK: backup completato."
