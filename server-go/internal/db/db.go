// Package db apre il database SQLite (plaintext, WAL tuned) in sola
// lettura (Fase-1) o lettura/scrittura, con i PRAGMA esatti dell'oracle
// Python e driver pure-Go modernc.org/sqlite (no CGO).
package db

import (
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// Pragmas oracle: devono restare allineati a backend/database.py (init_db)
// + specifica Fase-1. L'ordine di applicazione è quello sotto.
var pragmas = []string{
	"PRAGMA journal_mode=WAL",
	"PRAGMA synchronous=NORMAL",
	"PRAGMA cache_size=-2048",
	"PRAGMA temp_store=MEMORY",
	"PRAGMA busy_timeout=5000",
	"PRAGMA foreign_keys=ON",
	"PRAGMA mmap_size=0",
	"PRAGMA journal_size_limit=8388608",
	"PRAGMA wal_autocheckpoint=1000",
	"PRAGMA secure_delete=OFF",
	"PRAGMA locking_mode=NORMAL",
}

// roSkip contiene i PRAGMA che in mode=ro non possono essere modificati:
// il driver li rifiuta con "unable to open database file" / "read-only".
// Vengono skippati best-effort (log debug), gli altri applicati comunque.
var roSkip = map[string]bool{
	"PRAGMA journal_mode=WAL":           true,
	"PRAGMA journal_size_limit=8388608": true,
	"PRAGMA wal_autocheckpoint=1000":    true,
	"PRAGMA locking_mode=NORMAL":        true,
}

// Open apre il file SQLite. Con readOnly=true usa mode=ro (condivisibile
// con il backend Python che resta writer unico) e applica solo i PRAGMA
// compatibili con la modalità read-only.
func Open(path string, readOnly bool) (*sql.DB, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		return nil, fmt.Errorf("db: percorso vuoto")
	}
	// DSN modernc.org/sqlite: file:<path>?mode=ro&_pragma=...
	// I PRAGMA sono applicati a mano (vedi sotto) per controllare errori/ro-skip.
	dsn := "file:" + path
	if readOnly {
		dsn += "?mode=ro"
	}
	conn, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("db: open %s: %w", path, err)
	}
	// Pool: scritture serializzate (single-writer come Python), letture su
	// pool separato. In Fase-1 ro il pool di lettura resta piccolo per
	// restare nei 15-30MB idle su ARM64/2GB.
	if readOnly {
		conn.SetMaxOpenConns(4)
		conn.SetMaxIdleConns(2)
	} else {
		conn.SetMaxOpenConns(1)
		conn.SetMaxIdleConns(1)
	}

	for _, p := range pragmas {
		if readOnly && roSkip[p] {
			continue
		}
		if _, err := conn.Exec(p); err != nil {
			if readOnly {
				// Best-effort in ro (es. mmap_size su alcuni kernel): log e avanti.
				log.Printf("db: pragma ro ignorato %q: %v", p, err)
				continue
			}
			conn.Close()
			return nil, fmt.Errorf("db: %s: %w", p, err)
		}
	}
	if err := conn.Ping(); err != nil {
		conn.Close()
		return nil, fmt.Errorf("db: ping %s: %w", path, err)
	}
	if !readOnly {
		// Tabella effimera pack-perf (solo writer; in ro la lettura gestisce
		// l'assenza come cache-MISS).
		if _, err := conn.Exec(`CREATE TABLE IF NOT EXISTS portfolio_daily_cache(
			day TEXT PRIMARY KEY, payload TEXT, updated_at TEXT)`); err != nil {
			conn.Close()
			return nil, fmt.Errorf("db: portfolio_daily_cache: %w", err)
		}
	}
	return conn, nil
}

// ---------------------------------------------------------------------------
// Scritture Fase-2: retry con jitter su SQLITE_BUSY, mapping conflitti,
// ensure-stock. Il writer è UN solo *sql.DB con SetMaxOpenConns(1);
// busy_timeout=5000 è già nei PRAGMA: il retry copre solo il residuo
// (writer esterno Python). Mai attese da 30s: max 3 retry, 50/200/800ms.
// ---------------------------------------------------------------------------

// writeBackoffs è il backoff tra retry (jitter aggiunto fino a metà).
var writeBackoffs = []time.Duration{
	50 * time.Millisecond,
	200 * time.Millisecond,
	800 * time.Millisecond,
}

// IsBusy riporta true per SQLITE_BUSY/lock residui dopo busy_timeout.
func IsBusy(err error) bool {
	if err == nil {
		return false
	}
	s := strings.ToLower(err.Error())
	return strings.Contains(s, "database is locked") ||
		strings.Contains(s, "database table is locked") ||
		strings.Contains(s, "sqlite_busy") ||
		strings.Contains(s, "database is busy")
}

// IsConflict riporta true per violazioni UNIQUE (mapping -> HTTP 409,
// come _commit_write del Python che mappa IntegrityError -> 409).
func IsConflict(err error) bool {
	if err == nil {
		return false
	}
	s := strings.ToLower(err.Error())
	return strings.Contains(s, "unique constraint failed") ||
		strings.Contains(s, "unique_constraint")
}

// WithRetry esegue op fino a 3 retry solo su IsBusy, con jitter.
// Errori non-busy (inclusi i conflitti UNIQUE) tornano subito.
func WithRetry(op func() error) error {
	var err error
	for attempt := 0; ; attempt++ {
		if err = op(); err == nil || !IsBusy(err) {
			return err
		}
		if attempt >= len(writeBackoffs) {
			return err
		}
		b := writeBackoffs[attempt]
		jitter := time.Duration(0)
		if n := time.Now().UnixNano(); n != 0 {
			if n < 0 {
				n = -n
			}
			jitter = time.Duration(n % int64(b/2+1))
		}
		time.Sleep(b + jitter)
	}
}

// NowUTC rende il timestamp UTC nel formato usato dal DB Python.
func NowUTC() string {
	return time.Now().UTC().Format("2006-01-02 15:04:05")
}

// DetectMarketCurrency duplica backend/utils/helpers.py (suffisso autoritario).
func DetectMarketCurrency(ticker string) (string, string) {
	t := strings.TrimSpace(strings.ToUpper(ticker))
	switch {
	case t == "":
		return "US", "USD"
	case strings.HasSuffix(t, ".MI"):
		return "IT", "EUR"
	case strings.HasSuffix(t, ".DE"), strings.HasSuffix(t, ".PA"),
		strings.HasSuffix(t, ".AS"), strings.HasSuffix(t, ".MC"),
		strings.HasSuffix(t, ".LS"), strings.HasSuffix(t, ".BR"),
		strings.HasSuffix(t, ".VI"):
		return "EU", "EUR"
	case strings.HasSuffix(t, "=X"):
		return "FX", "USD"
	case strings.HasSuffix(t, "=F"):
		return "COMMODITY", "USD"
	case strings.HasSuffix(t, "-USD"):
		return "CRYPTO", "USD"
	case strings.HasSuffix(t, "-EUR"):
		return "CRYPTO", "EUR"
	case strings.HasSuffix(t, "-GBP"):
		return "CRYPTO", "GBP"
	}
	return "US", "USD"
}

// EnsureStock risolve l'id dello stock, creandolo se assente (nome = ticker:
// il Python arricchisce via Yahoo, Fase-2 resta leggera). Race-safe su
// UNIQUE(stocks.ticker): su conflitto ri-seleziona.
func EnsureStock(wdb *sql.DB, ticker string) (int64, error) {
	ticker = strings.TrimSpace(strings.ToUpper(ticker))
	if ticker == "" {
		return 0, fmt.Errorf("db: ticker vuoto")
	}
	var id int64
	err := wdb.QueryRow(`SELECT id FROM stocks WHERE ticker = ?`, ticker).Scan(&id)
	if err == nil {
		return id, nil
	}
	if err != sql.ErrNoRows {
		return 0, err
	}
	mkt, cur := DetectMarketCurrency(ticker)
	return EnsureStockNamed(wdb, ticker, ticker, mkt, cur)
}

// EnsureStockNamed come EnsureStock ma con nome/market/currency espliciti
// (usato dal resolve Yahoo anti-zombie: salva symbol+nome reali).
func EnsureStockNamed(wdb *sql.DB, ticker, name, market, currency string) (int64, error) {
	ticker = strings.TrimSpace(strings.ToUpper(ticker))
	if ticker == "" {
		return 0, fmt.Errorf("db: ticker vuoto")
	}
	var id int64
	if err := wdb.QueryRow(`SELECT id FROM stocks WHERE ticker = ?`, ticker).Scan(&id); err == nil {
		return id, nil
	} else if err != sql.ErrNoRows {
		return 0, err
	}
	if strings.TrimSpace(name) == "" {
		name = ticker
	}
	err := WithRetry(func() error {
		res, e := wdb.Exec(
			`INSERT INTO stocks(ticker, name, market, currency, is_active, created_at)
			 VALUES(?, ?, ?, ?, 1, ?)`, ticker, name, market, currency, NowUTC())
		if e != nil {
			return e
		}
		id, e = res.LastInsertId()
		return e
	})
	if err != nil {
		if IsConflict(err) {
			// Race con un writer concorrente: ri-seleziona.
			if e := wdb.QueryRow(`SELECT id FROM stocks WHERE ticker = ?`, ticker).Scan(&id); e == nil {
				return id, nil
			}
		}
		return 0, err
	}
	return id, nil
}
