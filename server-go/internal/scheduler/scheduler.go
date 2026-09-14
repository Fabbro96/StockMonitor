// Package scheduler: job minimi in-process Fase-2 + pack perf (una
// goroutine, niente APScheduler), mirror di backend/services/scheduler.py +
// alerting.py:
//
//   - collect hourly a minute=0: selettiva (skip prezzo fresco <1h in DB,
//     solo mercati aperti per gate statico) -> price_history;
//   - alerts ogni ALERT_CHECK_INTERVAL_MINUTES (default 60);
//   - cleanup giornaliera 03:00: retention price_history 400gg + tabelle
//     effimere, checkpoint WAL PASSIVE (mai VACUUM automatico);
//   - precompute serie 90gg + metriche in portfolio_daily_cache.
//
// Env: ENABLE_SCHEDULER=true/false, DB_MODE=rw per le scritture.
// Flag -scheduler-once=collect|alerts, -cleanup-once, -precompute-once (main).
package scheduler

import (
	"database/sql"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"stockmon/internal/dailycache"
	"stockmon/internal/db"
	"stockmon/internal/stocks"
)

// ---------------------------------------------------------------------------
// Gate mercati (statico, come dashboard.isOpen Fase-1)
// ---------------------------------------------------------------------------

func marketOpen(tz, open, close string) bool {
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return false
	}
	now := time.Now().In(loc)
	if now.Weekday() == time.Saturday || now.Weekday() == time.Sunday {
		return false
	}
	oh, om, _ := strings.Cut(open, ":")
	ch, cm, _ := strings.Cut(close, ":")
	oi, _ := strconv.Atoi(oh)
	omi, _ := strconv.Atoi(om)
	ci, _ := strconv.Atoi(ch)
	cmi, _ := strconv.Atoi(cm)
	openT := time.Date(now.Year(), now.Month(), now.Day(), oi, omi, 0, 0, loc)
	closeT := time.Date(now.Year(), now.Month(), now.Day(), ci, cmi, 0, 0, loc)
	return !now.Before(openT) && !now.After(closeT)
}

// AnyMarketsOpen mirror di MarketDataService.are_any_markets_open.
func AnyMarketsOpen() bool {
	return marketOpen("Europe/Rome", "09:00", "17:30") ||
		marketOpen("Europe/Paris", "09:00", "17:30") ||
		marketOpen("America/New_York", "09:30", "16:00")
}

// ---------------------------------------------------------------------------
// Collect: prezzi -> price_history (selettiva)
// ---------------------------------------------------------------------------

// freshFor è la soglia sotto cui un prezzo DB è considerato fresco.
const freshFor = time.Hour

// marketIsOpen applica il gate statico al mercato dello stock.
func marketIsOpen(market string) bool {
	switch strings.ToUpper(strings.TrimSpace(market)) {
	case "IT":
		return marketOpen("Europe/Rome", "09:00", "17:30")
	case "EU":
		return marketOpen("Europe/Paris", "09:00", "17:30")
	case "US":
		return marketOpen("America/New_York", "09:30", "16:00")
	case "FX", "CRYPTO", "COMMODITY":
		return true // quotazione (quasi) continua
	case "":
		return true // mercato ignoto: non affamare il titolo
	default:
		return true
	}
}

// CollectOnce scarica le ultime chiusure e ne persiste una riga
// price_history ciascuna. Selettiva: salta i ticker con prezzo DB fresco
// (<1h) e quelli a mercato chiuso (raggruppati per mercato nel log).
// Ritorna le righe scritte.
func CollectOnce(read, write *sql.DB) (int, error) {
	if !AnyMarketsOpen() {
		log.Printf("scheduler collect: tutti i mercati chiusi, collect leggero: skip, stop")
		return 0, nil
	}
	rows, err := read.Query(`SELECT id, ticker, market FROM stocks WHERE is_active = 1`)
	if err != nil {
		return 0, err
	}
	type stock struct {
		id     int64
		ticker string
		market string
	}
	var list []stock
	for rows.Next() {
		var s stock
		var mkt sql.NullString
		if err := rows.Scan(&s.id, &s.ticker, &mkt); err != nil {
			rows.Close()
			return 0, err
		}
		s.market = strings.ToUpper(strings.TrimSpace(mkt.String))
		if s.market == "" {
			m, _ := db.DetectMarketCurrency(s.ticker)
			s.market = m
		}
		list = append(list, s)
	}
	rows.Close()
	if len(list) == 0 {
		return 0, nil
	}
	// Freschezza DB: ultimo timestamp per stock (una sola query).
	freshCutoff := time.Now().UTC().Add(-freshFor).Format("2006-01-02 15:04:05")
	frows, err := read.Query(`
		SELECT stock_id, MAX(timestamp) FROM price_history GROUP BY stock_id`)
	if err != nil {
		return 0, err
	}
	fresh := map[int64]bool{}
	for frows.Next() {
		var sid int64
		var ts sql.NullString
		if err := frows.Scan(&sid, &ts); err != nil {
			frows.Close()
			return 0, err
		}
		if ts.Valid && ts.String >= freshCutoff {
			fresh[sid] = true
		}
	}
	frows.Close()

	byMarket := map[string]int{}
	var todo []stock
	skipFresh, skipClosed := 0, 0
	for _, s := range list {
		if fresh[s.id] {
			skipFresh++
			continue
		}
		if !marketIsOpen(s.market) {
			skipClosed++
			byMarket[s.market+"_closed"]++
			continue
		}
		byMarket[s.market]++
		todo = append(todo, s)
	}
	log.Printf("scheduler collect: %d da aggiornare %v (skip %d freschi <1h, %d mercato chiuso)",
		len(todo), byMarket, skipFresh, skipClosed)
	tickers := make([]string, 0, len(todo))
	for _, s := range todo {
		tickers = append(tickers, s.ticker)
	}
	quotes := stocks.FetchLastCloses(tickers)
	written := 0
	now := db.NowUTC()
	for _, s := range todo {
		q, ok := quotes[s.ticker]
		if !ok {
			continue
		}
		sid, qq := s.id, q
		if err := db.WithRetry(func() error {
			_, e := write.Exec(`INSERT INTO price_history(stock_id, timestamp, open, high, low, close, volume)
				VALUES(?, ?, ?, ?, ?, ?, ?)`,
				sid, now, qq.Open, qq.High, qq.Low, qq.Close, qq.Volume)
			return e
		}); err != nil {
			log.Printf("scheduler collect: insert %s fallito: %v", s.ticker, err)
			continue
		}
		written++
	}
	log.Printf("scheduler collect: scritte %d righe price_history su %d titoli", written, len(list))
	return written, nil
}

// ---------------------------------------------------------------------------
// Alerts: valutazione regole/watchlist/holdings (solo log, NO telegram)
// ---------------------------------------------------------------------------

var (
	throttleMu sync.Mutex
	lastFire   = map[string]time.Time{}
)

const refireAfter = 24 * time.Hour

func throttled(key string) bool {
	throttleMu.Lock()
	defer throttleMu.Unlock()
	if t, ok := lastFire[key]; ok && time.Since(t) < refireAfter {
		return true
	}
	lastFire[key] = time.Now()
	return false
}

func resolveAdmin(read *sql.DB) (int64, error) {
	want := strings.TrimSpace(os.Getenv("ADMIN_USERNAME"))
	if want == "" {
		want = "admin"
	}
	var id int64
	if err := read.QueryRow(`SELECT id FROM users WHERE username = ? ORDER BY id LIMIT 1`, want).Scan(&id); err == nil {
		return id, nil
	}
	if err := read.QueryRow(`SELECT MIN(id) FROM users`).Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}

type dbCloses struct {
	last, prev float64
	ok         bool
}

func lastTwoCloses(read *sql.DB, stockID int64) dbCloses {
	var last, prev sql.NullFloat64
	_ = read.QueryRow(`
		SELECT (SELECT close FROM price_history WHERE stock_id = ? ORDER BY timestamp DESC LIMIT 1),
		       (SELECT close FROM price_history WHERE stock_id = ? ORDER BY timestamp DESC LIMIT 1 OFFSET 1)`,
		stockID, stockID).Scan(&last, &prev)
	if !last.Valid || last.Float64 <= 0 {
		return dbCloses{}
	}
	out := dbCloses{last: last.Float64, ok: true}
	if prev.Valid && prev.Float64 > 0 {
		out.prev = prev.Float64
	} else {
		out.prev = last.Float64
	}
	return out
}

// AlertsOnce valuta regole/variazioni/soglie/SL-TP per l'admin e logga i
// trigger (throttle 24h per chiave). Ritorna il numero di trigger.
func AlertsOnce(read *sql.DB) (int, error) {
	if !AnyMarketsOpen() {
		log.Printf("scheduler alerts: borse chiuse, controllo saltato")
		return 0, nil
	}
	adminID, err := resolveAdmin(read)
	if err != nil {
		log.Printf("scheduler alerts: nessun utente, controllo saltato")
		return 0, nil
	}

	type rule struct {
		id        int64
		stockID   int64
		ticker    string
		threshold float64
		direction string
	}
	var rules []rule
	rrows, err := read.Query(`
		SELECT ar.id, ar.stock_id, s.ticker, ar.threshold_percent, ar.direction
		  FROM alert_rules ar JOIN stocks s ON s.id = ar.stock_id
		 WHERE ar.is_active = 1 AND ar.user_id = ? AND s.is_active = 1`, adminID)
	if err != nil {
		return 0, err
	}
	for rrows.Next() {
		var r rule
		var thr sql.NullFloat64
		var dir sql.NullString
		if err := rrows.Scan(&r.id, &r.stockID, &r.ticker, &thr, &dir); err != nil {
			rrows.Close()
			return 0, err
		}
		r.threshold = thr.Float64
		r.direction = strings.ToUpper(strings.TrimSpace(dir.String))
		rules = append(rules, r)
	}
	rrows.Close()

	type wl struct {
		id           int64
		stockID      int64
		ticker       string
		above, below sql.NullFloat64
	}
	var wls []wl
	wrows, err := read.Query(`
		SELECT wi.id, wi.stock_id, s.ticker, wi.alert_above, wi.alert_below
		  FROM watchlist_items wi JOIN stocks s ON s.id = wi.stock_id
		 WHERE wi.user_id = ? AND s.is_active = 1`, adminID)
	if err != nil {
		return 0, err
	}
	for wrows.Next() {
		var w wl
		if err := wrows.Scan(&w.id, &w.stockID, &w.ticker, &w.above, &w.below); err != nil {
			wrows.Close()
			return 0, err
		}
		wls = append(wls, w)
	}
	wrows.Close()

	type holding struct {
		id      int64
		stockID int64
		ticker  string
		avg     float64
	}
	var holds []holding
	hrows, err := read.Query(`
		SELECT h.id, h.stock_id, s.ticker, h.avg_purchase_price
		  FROM holdings h JOIN stocks s ON s.id = h.stock_id
		 WHERE h.user_id = ? AND s.is_active = 1`, adminID)
	if err != nil {
		return 0, err
	}
	for hrows.Next() {
		var h holding
		if err := hrows.Scan(&h.id, &h.stockID, &h.ticker, &h.avg); err != nil {
			hrows.Close()
			return 0, err
		}
		holds = append(holds, h)
	}
	hrows.Close()

	// Evict chiavi throttle obsolete (mirror L6 del Python).
	valid := map[string]bool{}
	for _, r := range rules {
		valid["rule_"+strconv.FormatInt(r.id, 10)] = true
	}
	for _, w := range wls {
		valid["wl_"+strconv.FormatInt(w.id, 10)] = true
	}
	for _, h := range holds {
		valid["sltp_"+strconv.FormatInt(h.id, 10)] = true
	}
	throttleMu.Lock()
	for k := range lastFire {
		if !valid[k] {
			delete(lastFire, k)
		}
	}
	throttleMu.Unlock()

	// Un solo batch prezzi per tutti i ticker della run.
	tickers := []string{}
	seen := map[string]bool{}
	for _, r := range rules {
		if !seen[r.ticker] {
			seen[r.ticker] = true
			tickers = append(tickers, r.ticker)
		}
	}
	for _, w := range wls {
		if !seen[w.ticker] {
			seen[w.ticker] = true
			tickers = append(tickers, w.ticker)
		}
	}
	for _, h := range holds {
		if !seen[h.ticker] {
			seen[h.ticker] = true
			tickers = append(tickers, h.ticker)
		}
	}
	quotes := stocks.FetchLastCloses(tickers)

	// Prezzo effettivo: live se fresco, altrimenti ultime chiusure DB reali
	// (mai sintetici); senza chiusure DB il titolo è escluso.
	priceOf := func(stockID int64, ticker string) (close, prev float64, ok bool) {
		if q, found := quotes[ticker]; found && q.Close > 0 {
			p := q.PrevClose
			if p <= 0 {
				p = q.Close
			}
			return q.Close, p, true
		}
		if dc := lastTwoCloses(read, stockID); dc.ok {
			return dc.last, dc.prev, true
		}
		return 0, 0, false
	}

	trig, nRule, nWl, nSlTp := 0, 0, 0, 0
	for _, r := range rules {
		close, prev, ok := priceOf(r.stockID, r.ticker)
		if !ok || prev <= 0 {
			continue
		}
		chg := (close - prev) / prev * 100
		fire := false
		switch r.direction {
		case "UP":
			fire = chg >= r.threshold
		case "DOWN":
			fire = chg <= -r.threshold
		default:
			fire = chg >= r.threshold || chg <= -r.threshold
		}
		if !fire || r.threshold <= 0 {
			continue
		}
		key := "rule_" + strconv.FormatInt(r.id, 10)
		if throttled(key) {
			continue
		}
		log.Printf("scheduler alerts: RULE #%d %s %+.2f%% soglia %.2f%% (%s) @ %.2f",
			r.id, r.ticker, chg, r.threshold, r.direction, close)
		trig++
		nRule++
	}
	for _, w := range wls {
		close, _, ok := priceOf(w.stockID, w.ticker)
		if !ok || close <= 0 {
			continue
		}
		hit := ""
		if w.above.Valid && close >= w.above.Float64 {
			hit = "sopra " + strconv.FormatFloat(w.above.Float64, 'f', 2, 64)
		} else if w.below.Valid && close <= w.below.Float64 {
			hit = "sotto " + strconv.FormatFloat(w.below.Float64, 'f', 2, 64)
		}
		if hit == "" {
			continue
		}
		key := "wl_" + strconv.FormatInt(w.id, 10)
		if throttled(key) {
			continue
		}
		log.Printf("scheduler alerts: WATCHLIST #%d %s @ %.2f %s soglia", w.id, w.ticker, close, hit)
		trig++
		nWl++
	}
	for _, h := range holds {
		close, _, ok := priceOf(h.stockID, h.ticker)
		if !ok || close <= 0 || h.avg <= 0 {
			continue
		}
		pnl := (close - h.avg) / h.avg * 100
		kind := ""
		if pnl <= -8 {
			kind = "STOP-LOSS"
		} else if pnl >= 15 {
			kind = "TAKE-PROFIT"
		}
		if kind == "" {
			continue
		}
		key := "sltp_" + strconv.FormatInt(h.id, 10)
		if throttled(key) {
			continue
		}
		log.Printf("scheduler alerts: %s holding #%d %s %+.2f%% @ %.2f (avg %.2f)",
			kind, h.id, h.ticker, pnl, close, h.avg)
		trig++
		nSlTp++
	}
	log.Printf("scheduler alerts: %d trigger (%d regole, %d watchlist, %d sl/tp)", trig, nRule, nWl, nSlTp)
	return trig, nil
}

// ---------------------------------------------------------------------------
// Cleanup: retention notturna (mai VACUUM automatico)
// ---------------------------------------------------------------------------

const (
	// priceRetentionDays mirror di PRICE_HISTORY_RETENTION_DAYS (Python).
	priceRetentionDays = 400
	// sentimentRetentionDays mirror di SENTIMENT_RETENTION_DAYS.
	sentimentRetentionDays = 30
	// dailyCacheKeepDays: la daily-cache oltre questa età è effimera.
	dailyCacheKeepDays = 7
)

func tableExists(read *sql.DB, name string) bool {
	var n string
	err := read.QueryRow(
		`SELECT name FROM sqlite_master WHERE type='table' AND name = ?`, name).Scan(&n)
	return err == nil && n == name
}

func hasColumn(read *sql.DB, table, col string) bool {
	rows, err := read.Query(`PRAGMA table_info(` + table + `)`)
	if err != nil {
		return false
	}
	defer rows.Close()
	for rows.Next() {
		var cid int
		var name, ctype string
		var notnull, pk int
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notnull, &dflt, &pk); err != nil {
			return false
		}
		if name == col {
			return true
		}
	}
	return false
}

// CleanupOnce applica la retention: price_history >400gg, sentiments >30gg
// (se la tabella esiste), righe portfolio_daily_cache >7gg; poi checkpoint
// WAL PASSIVE. Mai VACUUM. Ritorna le righe eliminate per tabella.
func CleanupOnce(read, write *sql.DB) (map[string]int64, error) {
	out := map[string]int64{}
	cutPrice := time.Now().UTC().AddDate(0, 0, -priceRetentionDays).Format("2006-01-02 15:04:05")
	var n int64
	err := db.WithRetry(func() error {
		res, e := write.Exec(`DELETE FROM price_history WHERE timestamp < ?`, cutPrice)
		if e != nil {
			return e
		}
		n, e = res.RowsAffected()
		return e
	})
	if err != nil {
		return out, err
	}
	out["price_history"] = n
	if tableExists(read, "sentiments") && hasColumn(read, "sentiments", "timestamp") {
		cutSent := time.Now().UTC().AddDate(0, 0, -sentimentRetentionDays).Format("2006-01-02 15:04:05")
		var ns int64
		if err := db.WithRetry(func() error {
			res, e := write.Exec(`DELETE FROM sentiments WHERE timestamp < ?`, cutSent)
			if e != nil {
				return e
			}
			ns, e = res.RowsAffected()
			return e
		}); err != nil {
			return out, err
		}
		out["sentiments"] = ns
	}
	if pruned, err := dailycache.Prune(write, dailyCacheKeepDays); err == nil {
		out["portfolio_daily_cache"] = pruned
	} else {
		return out, err
	}
	// Checkpoint leggero: rende le pagine WAL al DB senza bloccare i lettori.
	if _, err := write.Exec(`PRAGMA wal_checkpoint(PASSIVE)`); err != nil {
		log.Printf("scheduler cleanup: wal_checkpoint(PASSIVE) fallito: %v", err)
	} else {
		log.Printf("scheduler cleanup: wal_checkpoint(PASSIVE) ok")
	}
	log.Printf("scheduler cleanup: eliminate %+v (retention %dg prezzi, wal checkpoint, mai VACUUM)",
		out, priceRetentionDays)
	return out, nil
}

// ---------------------------------------------------------------------------
// Precompute: serie 90gg + metriche in portfolio_daily_cache
// ---------------------------------------------------------------------------

// PrecomputeOnce calcola serie giornaliera 90gg + metriche per tutti gli
// utenti con holdings e scrive la riga del giorno (idempotente).
func PrecomputeOnce(read, write *sql.DB) error {
	if err := dailycache.EnsureTable(write); err != nil {
		return err
	}
	// FX corrente per il payload: ultima EURUSD=X, fallback costante.
	fx := 0.9259
	var last sql.NullFloat64
	_ = read.QueryRow(`
		SELECT ph.close FROM price_history ph
		  JOIN stocks s ON s.id = ph.stock_id
		 WHERE s.ticker = 'EURUSD=X' ORDER BY ph.timestamp DESC LIMIT 1`).Scan(&last)
	if last.Valid && last.Float64 > 0 {
		fx = 1 / last.Float64
	}
	body, day, err := dailycache.BuildPayload(read, fx)
	if err != nil {
		return err
	}
	now := db.NowUTC()
	if err := db.WithRetry(func() error {
		return dailycache.Write(write, day, body, now)
	}); err != nil {
		return err
	}
	log.Printf("scheduler precompute: cache %s scritta (%d byte)", day, len(body))
	return nil
}

// Start lancia il loop in-process: collect allo scoccare dell'ora,
// alerts ogni alertsMin minuti, cleanup+precompute alle 03:00.
// Si ferma su stop.
func Start(read, write *sql.DB, alertsMin int, stop <-chan struct{}) {
	if alertsMin <= 0 {
		alertsMin = 60
	}
	log.Printf("scheduler: attivo (collect orario, alerts ogni %d min, cleanup 03:00)", alertsMin)
	go func() {
		tick := time.NewTicker(time.Minute)
		defer tick.Stop()
		lastHour := -1
		lastAlerts := time.Now()
		lastCleanupDay := ""
		for {
			select {
			case <-stop:
				return
			case now := <-tick.C:
				if now.Minute() == 0 && now.Hour() != lastHour {
					lastHour = now.Hour()
					if _, err := CollectOnce(read, write); err != nil {
						log.Printf("scheduler collect: errore: %v", err)
					}
				}
				if now.Sub(lastAlerts) >= time.Duration(alertsMin)*time.Minute {
					lastAlerts = now
					if _, err := AlertsOnce(read); err != nil {
						log.Printf("scheduler alerts: errore: %v", err)
					}
				}
				if now.Hour() == 3 && now.Minute() == 0 {
					today := now.Format("2006-01-02")
					if today != lastCleanupDay {
						lastCleanupDay = today
						if _, err := CleanupOnce(read, write); err != nil {
							log.Printf("scheduler cleanup: errore: %v", err)
						}
						if err := PrecomputeOnce(read, write); err != nil {
							log.Printf("scheduler precompute: errore: %v", err)
						}
					}
				}
			}
		}
	}()
}
