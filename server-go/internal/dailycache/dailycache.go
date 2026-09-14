// Package dailycache: serie giornaliera 90gg + metriche precomputate per il
// pack perf F2-212. Una riga al giorno (day PRIMARY KEY → rerun idempotente):
//
//	portfolio_daily_cache(day TEXT PRIMARY KEY, payload TEXT, updated_at TEXT)
//
// payload JSON: {"day","computed_at","fx_usd_eur","users":{"<id>":{"series":
// [{"date","value"}...],"metrics":{...}}}}. Endpoints risk-metrics /
// performance / history servono da qui se fresca (<24h), altrimenti
// calcolano on-demand (stesso codice, niente pandas).
package dailycache

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"
)

const (
	// TableDDL crea la cache (chiamata da db.Open in rw, mai in ro).
	TableDDL = `CREATE TABLE IF NOT EXISTS portfolio_daily_cache(
		day TEXT PRIMARY KEY, payload TEXT, updated_at TEXT)`
	// SeriesDays è la finestra precomputata.
	SeriesDays = 90
	// FreshFor è la freschezza: sotto questa soglia gli endpoint servono
	// dalla cache (X-Cache: HIT).
	FreshFor = 24 * time.Hour
	// usdToEurFallback allineato al resto del backend Go.
	usdToEurFallback = 0.9259
	// riskFreeAnnual mirror di settings.RISK_FREE_RATE (Sharpe).
	riskFreeAnnual = 0.02
)

// EnsureTable crea la tabella se assente (solo writer).
func EnsureTable(wdb *sql.DB) error {
	_, err := wdb.Exec(TableDDL)
	return err
}

// Payload è il contenuto di una riga cache.
type Payload struct {
	Day       string                `json:"day"`
	Computed  string                `json:"computed_at"`
	FxUsdEur  float64               `json:"fx_usd_eur"`
	Users     map[string]*UserCache `json:"users"`
	UpdatedAt string                `json:"-"`
}

// UserCache è serie + metriche di un utente.
type UserCache struct {
	Series  []DayValue         `json:"series"`
	Metrics map[string]float64 `json:"metrics"`
}

// DayValue è un punto {date,value} (stesso shape di performance).
type DayValue struct {
	Date  string  `json:"date"`
	Value float64 `json:"value"`
}

// ReadFresh ritorna il payload più recente se aggiornato da <24h.
func ReadFresh(read *sql.DB) (*Payload, bool) {
	var day, payload, updated string
	err := read.QueryRow(
		`SELECT day, payload, updated_at FROM portfolio_daily_cache ORDER BY day DESC LIMIT 1`,
	).Scan(&day, &payload, &updated)
	if err != nil {
		return nil, false
	}
	ts, err := time.Parse("2006-01-02 15:04:05", updated)
	if err != nil {
		if ts, err = time.Parse(time.RFC3339, updated); err != nil {
			return nil, false
		}
	}
	if time.Since(ts.UTC()) > FreshFor {
		return nil, false
	}
	var p Payload
	if err := json.Unmarshal([]byte(payload), &p); err != nil {
		return nil, false
	}
	p.UpdatedAt = updated
	if p.Users == nil {
		p.Users = map[string]*UserCache{}
	}
	return &p, true
}

// Write salva il payload del giorno (INSERT OR REPLACE: rerun idempotente).
func Write(wdb *sql.DB, day string, body []byte, now string) error {
	_, err := wdb.Exec(
		`INSERT OR REPLACE INTO portfolio_daily_cache(day, payload, updated_at) VALUES(?, ?, ?)`,
		day, string(body), now)
	return err
}

// Prune elimina le righe più vecchie di keepDays (tabella effimera).
func Prune(wdb *sql.DB, keepDays int) (int64, error) {
	cutoff := time.Now().UTC().AddDate(0, 0, -keepDays).Format("2006-01-02")
	res, err := wdb.Exec(`DELETE FROM portfolio_daily_cache WHERE day < ?`, cutoff)
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// ---------------------------------------------------------------------------
// Calcolo serie + metriche (SQL per le chiusure, Go stdlib per le metriche)
// ---------------------------------------------------------------------------

type holding struct {
	stockID int64
	ticker  string
	qty     float64
	avg     float64
	fxEUR   bool // true se valuta USD (conversione via EURUSD=X o fallback)
}

func round2(f float64) float64 { return math.Round(f*100) / 100 }
func round4(f float64) float64 { return math.Round(f*10000) / 10000 }

// ComputeUserSeries calcola serie giornaliera + metriche per un utente su
// `days` giorni (calendariali, fino a oggi UTC). Usata sia da PrecomputeOnce
// (90gg, tutti gli utenti) che dal fallback on-demand degli endpoint.
func ComputeUserSeries(read *sql.DB, userID int64, days int) ([]DayValue, map[string]float64, error) {
	if days < 1 {
		days = 1
	}
	// Holdings attive dell'utente (+ flag USD per FX).
	hrows, err := read.Query(`
		SELECT h.stock_id, s.ticker, h.quantity, h.avg_purchase_price, s.currency
		  FROM holdings h JOIN stocks s ON s.id = h.stock_id
		 WHERE h.user_id = ? AND s.is_active = 1`, userID)
	if err != nil {
		return nil, nil, err
	}
	var hs []holding
	for hrows.Next() {
		var h holding
		var cur sql.NullString
		if err := hrows.Scan(&h.stockID, &h.ticker, &h.qty, &h.avg, &cur); err != nil {
			hrows.Close()
			return nil, nil, err
		}
		c := strings.ToUpper(strings.TrimSpace(cur.String))
		if c == "" {
			_, c = detectMarketCurrency(h.ticker)
		}
		h.fxEUR = c == "USD"
		hs = append(hs, h)
	}
	hrows.Close()
	if err := hrows.Err(); err != nil {
		return nil, nil, err
	}

	today := time.Now().UTC().Truncate(24 * time.Hour)
	start := today.AddDate(0, 0, -(days - 1))
	startS := start.Format("2006-01-02")

	// Ultima chiusura per (stock, giorno) nella finestra: una sola query.
	type key struct {
		stock int64
		day   string
	}
	closes := map[key]float64{}
	if len(hs) > 0 {
		ids := make([]string, 0, len(hs)+1)
		args := make([]any, 0, len(hs)+2)
		for _, h := range hs {
			ids = append(ids, "?")
			args = append(args, h.stockID)
		}
		// ID EURUSD=X per il cambio storico (se censito).
		var fxID sql.NullInt64
		_ = read.QueryRow(`SELECT id FROM stocks WHERE ticker = 'EURUSD=X'`).Scan(&fxID)
		if fxID.Valid {
			ids = append(ids, "?")
			args = append(args, fxID.Int64)
		}
		args = append(args, startS)
		prows, err := read.Query(`
			SELECT stock_id, date(timestamp) AS d, close
			  FROM price_history
			 WHERE stock_id IN (`+strings.Join(ids, ",")+`) AND date(timestamp) >= ?
			 ORDER BY stock_id, timestamp`, args...)
		if err != nil {
			return nil, nil, err
		}
		var fxIDv int64
		if fxID.Valid {
			fxIDv = fxID.Int64
		}
		fxByDay := map[string]float64{}
		for prows.Next() {
			var sid int64
			var d string
			var c sql.NullFloat64
			if err := prows.Scan(&sid, &d, &c); err != nil {
				prows.Close()
				return nil, nil, err
			}
			if !c.Valid || c.Float64 <= 0 {
				continue
			}
			if sid == fxIDv {
				fxByDay[d] = c.Float64 // EURUSD=X: USD per 1 EUR
				continue
			}
			closes[key{sid, d}] = c.Float64 // ORDER BY → vince l'ultima
		}
		prows.Close()
		if err := prows.Err(); err != nil {
			return nil, nil, err
		}
		// FX giornaliero USD->EUR = 1/EURUSD, forward-fill, fallback costante.
		fxDaily := map[string]float64{}
		lastFx := 0.0
		for i := 0; i < days; i++ {
			d := start.AddDate(0, 0, i).Format("2006-01-02")
			if v, ok := fxByDay[d]; ok && v > 0 {
				lastFx = 1 / v
			}
			if lastFx > 0 {
				fxDaily[d] = lastFx
			} else {
				fxDaily[d] = usdToEurFallback
			}
		}
		// Serie: forward-fill chiusure, fallback avg se mai quotato.
		series := make([]DayValue, 0, days)
		lastClose := map[int64]float64{}
		for i := 0; i < days; i++ {
			d := start.AddDate(0, 0, i).Format("2006-01-02")
			total := 0.0
			for _, h := range hs {
				if c, ok := closes[key{h.stockID, d}]; ok {
					lastClose[h.stockID] = c
				}
				px, ok := lastClose[h.stockID]
				if !ok || px <= 0 {
					px = h.avg
				}
				fx := 1.0
				if h.fxEUR {
					fx = fxDaily[d]
				}
				total += h.qty * px * fx
			}
			series = append(series, DayValue{Date: d, Value: round2(total)})
		}
		return series, Metrics(series), nil
	}
	// Portafoglio vuoto: serie a zero (come il Python a holdings vuote).
	series := make([]DayValue, 0, days)
	for i := 0; i < days; i++ {
		series = append(series, DayValue{Date: start.AddDate(0, 0, i).Format("2006-01-02")})
	}
	return series, Metrics(series), nil
}

// Metrics calcola volatilità annua, Sharpe (rf 2%) e max drawdown dalla serie.
// Stdev di popolazione (deterministica); drawdown in % negativo (0 se mai).
func Metrics(series []DayValue) map[string]float64 {
	n := len(series)
	m := map[string]float64{"days": float64(n)}
	if n == 0 {
		m["volatility"] = 0
		m["sharpe_ratio"] = 0
		m["max_drawdown"] = 0
		m["total_return_pct"] = 0
		return m
	}
	start, end := series[0].Value, series[n-1].Value
	if start > 0 {
		m["total_return_pct"] = round2((end - start) / start * 100)
	} else {
		m["total_return_pct"] = 0
	}
	// Drawdown dal picco corrente.
	peak, maxDD := end, 0.0
	if n > 0 {
		peak = series[0].Value
		for _, p := range series {
			if p.Value > peak {
				peak = p.Value
			}
			if peak > 0 {
				if dd := (p.Value - peak) / peak * 100; dd < maxDD {
					maxDD = dd
				}
			}
		}
	}
	m["max_drawdown"] = round2(maxDD)
	// Returns giornalieri.
	rets := make([]float64, 0, n-1)
	for i := 1; i < n; i++ {
		prev := series[i-1].Value
		if prev > 0 {
			rets = append(rets, series[i].Value/prev-1)
		}
	}
	if len(rets) < 2 {
		m["volatility"] = 0
		m["sharpe_ratio"] = 0
		return m
	}
	mean := 0.0
	for _, r := range rets {
		mean += r
	}
	mean /= float64(len(rets))
	variance := 0.0
	for _, r := range rets {
		variance += (r - mean) * (r - mean)
	}
	variance /= float64(len(rets))
	stdev := math.Sqrt(variance)
	m["volatility"] = round4(stdev * math.Sqrt(252))
	if stdev > 0 {
		rfDaily := riskFreeAnnual / 252
		m["sharpe_ratio"] = round4((mean - rfDaily) / stdev * math.Sqrt(252))
	} else {
		m["sharpe_ratio"] = 0
	}
	return m
}

// UsersWithHoldings elenca gli user_id con almeno una holding attiva.
func UsersWithHoldings(read *sql.DB) ([]int64, error) {
	rows, err := read.Query(`
		SELECT DISTINCT h.user_id FROM holdings h
		  JOIN stocks s ON s.id = h.stock_id
		 WHERE h.user_id IS NOT NULL AND s.is_active = 1`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

func detectMarketCurrency(ticker string) (string, string) {
	t := strings.TrimSpace(strings.ToUpper(ticker))
	if strings.HasSuffix(t, ".MI") {
		return "IT", "EUR"
	}
	return "US", "USD"
}

// BuildPayload costruisce il payload completo per tutti gli utenti.
func BuildPayload(read *sql.DB, fxNow float64) ([]byte, string, error) {
	users, err := UsersWithHoldings(read)
	if err != nil {
		return nil, "", err
	}
	day := time.Now().UTC().Format("2006-01-02")
	p := Payload{
		Day:      day,
		Computed: time.Now().UTC().Format("2006-01-02 15:04:05"),
		FxUsdEur: fxNow,
		Users:    map[string]*UserCache{},
	}
	for _, uid := range users {
		series, metrics, err := ComputeUserSeries(read, uid, SeriesDays)
		if err != nil {
			return nil, "", fmt.Errorf("user %d: %w", uid, err)
		}
		p.Users[fmt.Sprintf("%d", uid)] = &UserCache{Series: series, Metrics: metrics}
	}
	body, err := json.Marshal(p)
	if err != nil {
		return nil, "", err
	}
	return body, day, nil
}
