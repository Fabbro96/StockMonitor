// Package stocks implementa GET /api/stocks/{ticker}/candles con lo stesso
// contratto del backend Python (backend/routers/stocks.py +
// MarketDataService.fetch_stock_candles):
//
//   - cache DB (price_history) con minimi per fascia;
//   - fallback Yahoo chart v8 https://query1.finance.yahoo.com/v8/finance/chart/{ticker}
//     con cookiejar, User-Agent fisso e singleflight (golang.org/x/sync);
//   - TTL memoria 180/300/900/1800s per fascia (1d/1w/1m/lunghi);
//   - su 429 (o errore upstream) ritorna l'ultimo prezzo DB;
//   - RSI-14/SMA in stdlib (niente pandas); di default la risposta resta la
//     lista candele {time,open,high,low,close,value,volume}, con
//     ?indicators=true si aggiunge l'envelope {candles, rsi_14, sma_20}.
package stocks

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"

	"golang.org/x/sync/singleflight"
)

const uaFixed = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

var validTF = regexp.MustCompile(`^(1d|1w|1m|6m|1y|5y)$`)

// fascia Yahoo + TTL memoria + finestra DB + minimo punti DB.
type band struct {
	yRange   string
	yInt     string
	ttl      time.Duration
	dbDays   int
	dbMin    int
	intraday bool
}

var bands = map[string]band{
	"1d": {"1d", "5m", 180 * time.Second, 2, 5, true},
	"1w": {"5d", "15m", 300 * time.Second, 7, 5, true},
	"1m": {"1mo", "1d", 900 * time.Second, 31, 10, false},
	"6m": {"6mo", "1d", 1800 * time.Second, 186, 20, false},
	"1y": {"1y", "1d", 1800 * time.Second, 370, 20, false},
	"5y": {"5y", "1wk", 1800 * time.Second, 1827, 20, false},
}

// fallbackTTL limita i retry upstream dopo un 429/errore (ultimo prezzo DB).
const fallbackTTL = 60 * time.Second

type cacheEntry struct {
	body    []byte
	etag    string
	expires time.Time
}

var (
	mu         sync.Mutex
	cache      = map[string]cacheEntry{}
	sf         singleflight.Group
	httpClient *http.Client
	once       sync.Once
)

func client() *http.Client {
	once.Do(func() {
		jar, _ := cookiejar.New(nil)
		httpClient = &http.Client{Timeout: 8 * time.Second, Jar: jar}
	})
	return httpClient
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// ---------------------------------------------------------------------------
// indicatori stdlib (~30 righe): RSI-14 Wilder + SMA
// ---------------------------------------------------------------------------

func rsi14(closes []float64) float64 {
	if len(closes) < 15 {
		return 50.0
	}
	gain, loss := 0.0, 0.0
	for i := 1; i < 15; i++ {
		if d := closes[i] - closes[i-1]; d > 0 {
			gain += d
		} else {
			loss -= d
		}
	}
	gain, loss = gain/14, loss/14
	for _, i := range idxFrom(closes, 15) {
		d := closes[i] - closes[i-1]
		if d > 0 {
			gain = (gain*13 + d) / 14
		} else {
			loss = (loss*13 - d) / 14
		}
	}
	if loss == 0 {
		return 100.0
	}
	return 100 - 100/(1+gain/loss)
}

func idxFrom(closes []float64, from int) []int {
	out := []int{}
	for i := from; i < len(closes); i++ {
		out = append(out, i)
	}
	return out
}

func sma(closes []float64, n int) float64 {
	if len(closes) < n || n <= 0 {
		return 0
	}
	sum := 0.0
	for _, v := range closes[len(closes)-n:] {
		sum += v
	}
	return sum / float64(n)
}

// ---------------------------------------------------------------------------
// handler
// ---------------------------------------------------------------------------

// Candles GET /api/stocks/{ticker}/candles?timeframe=1m[&indicators=true].
func Candles(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		ticker := strings.TrimSpace(strings.ToUpper(r.PathValue("ticker")))
		if ticker == "" {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Titolo non trovato."})
			return
		}
		tf := strings.TrimSpace(strings.ToLower(r.URL.Query().Get("timeframe")))
		if tf == "" {
			tf = "1m"
		}
		if !validTF.MatchString(tf) {
			writeJSON(w, http.StatusUnprocessableEntity, map[string]any{
				"detail": "timeframe deve essere uno di: 1d, 1w, 1m, 6m, 1y, 5y.",
			})
			return
		}
		withInd := strings.TrimSpace(r.URL.Query().Get("indicators")) == "true"
		b := bands[tf]
		key := "candles:" + ticker + ":" + tf + fmt.Sprintf(":%v", withInd)

		now := time.Now()
		mu.Lock()
		if e, ok := cache[key]; ok && now.Before(e.expires) {
			mu.Unlock()
			serveCached(w, r, e)
			return
		}
		mu.Unlock()

		candles, stale := load(db, ticker, b)

		var payload any = candles
		if withInd {
			closes := make([]float64, 0, len(candles))
			for _, c := range candles {
				closes = append(closes, c["close"].(float64))
			}
			payload = map[string]any{
				"candles": candles,
				"rsi_14":  rsi14(closes),
				"sma_20":  sma(closes, 20),
				"stale":   stale,
			}
		}
		body, err := json.Marshal(payload)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		sum := sha256.Sum256(body)
		etag := `"` + hex.EncodeToString(sum[:]) + `"`
		ttl := b.ttl
		if stale {
			ttl = fallbackTTL
		}
		mu.Lock()
		cache[key] = cacheEntry{body: body, etag: etag, expires: now.Add(ttl)}
		mu.Unlock()

		if stale {
			w.Header().Set("X-Data-Stale", "true")
		}
		if r.Header.Get("If-None-Match") == etag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("ETag", etag)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	}
}

func serveCached(w http.ResponseWriter, r *http.Request, e cacheEntry) {
	if r.Header.Get("If-None-Match") == e.etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("ETag", e.etag)
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(e.body)
}

// load: cache DB, senno Yahoo v8, senno ultimo prezzo DB. Ritorna (candele, stale).
func load(db *sql.DB, ticker string, b band) ([]map[string]any, bool) {
	if out := fromDB(db, ticker, b); len(out) >= b.dbMin {
		return out, false
	}
	if out, ok := fromYahoo(ticker, b); ok {
		return out, false
	}
	if last := lastDBPrice(db, ticker); last != nil {
		return last, true
	}
	return []map[string]any{}, true
}

func fromDB(db *sql.DB, ticker string, b band) []map[string]any {
	var stockID int64
	if err := db.QueryRow(`SELECT id FROM stocks WHERE ticker = ?`, ticker).Scan(&stockID); err != nil {
		return nil
	}
	cutoff := time.Now().UTC().AddDate(0, 0, -b.dbDays).Format("2006-01-02 15:04:05")
	rows, err := db.Query(`
		SELECT timestamp, open, high, low, close, volume
		  FROM price_history WHERE stock_id = ? AND timestamp >= ?
		 ORDER BY timestamp`, stockID, cutoff)
	if err != nil {
		return nil
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var ts string
		var o, h, l, c sql.NullFloat64
		var v sql.NullInt64
		if err := rows.Scan(&ts, &o, &h, &l, &c, &v); err != nil {
			return nil
		}
		if !c.Valid || c.Float64 <= 0 {
			continue
		}
		var t any = ts
		if parsed, err := time.Parse("2006-01-02 15:04:05", ts); err == nil {
			if b.intraday {
				t = parsed.Unix()
			} else {
				t = parsed.Format("2006-01-02")
			}
		} else if parsed, err := time.Parse(time.RFC3339, ts); err == nil {
			if b.intraday {
				t = parsed.Unix()
			} else {
				t = parsed.Format("2006-01-02")
			}
		}
		close := c.Float64
		vol := int64(0)
		if v.Valid {
			vol = v.Int64
		}
		out = append(out, map[string]any{
			"time": t, "open": fOr(o, close), "high": fOr(h, close),
			"low": fOr(l, close), "close": close, "value": close, "volume": vol,
		})
	}
	return out
}

func round2(f float64) float64 {
	if f >= 0 {
		return float64(int64(f*100+0.5)) / 100
	}
	return float64(int64(f*100-0.5)) / 100
}

func fOr(f sql.NullFloat64, def float64) float64 {
	if f.Valid && f.Float64 > 0 {
		return f.Float64
	}
	return def
}

type yahooResp struct {
	Chart struct {
		Result []struct {
			Timestamp  []int64 `json:"timestamp"`
			Indicators struct {
				Quote []struct {
					Open   []*float64 `json:"open"`
					High   []*float64 `json:"high"`
					Low    []*float64 `json:"low"`
					Close  []*float64 `json:"close"`
					Volume []*float64 `json:"volume"`
				} `json:"quote"`
			} `json:"indicators"`
		} `json:"result"`
		Error *struct {
			Code        string `json:"code"`
			Description string `json:"description"`
		} `json:"error"`
	} `json:"chart"`
}

func fromYahoo(ticker string, b band) ([]map[string]any, bool) {
	v, err, _ := sf.Do("yahoo:"+ticker+":"+b.yRange+":"+b.yInt, func() (any, error) {
		u := "https://query1.finance.yahoo.com/v8/finance/chart/" + url.PathEscape(ticker) +
			"?range=" + url.QueryEscape(b.yRange) + "&interval=" + url.QueryEscape(b.yInt)
		req, err := http.NewRequest(http.MethodGet, u, nil)
		if err != nil {
			return nil, err
		}
		req.Header.Set("User-Agent", uaFixed)
		req.Header.Set("Accept", "application/json")
		resp, err := client().Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode == http.StatusTooManyRequests {
			return nil, fmt.Errorf("yahoo 429")
		}
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("yahoo %d", resp.StatusCode)
		}
		var yr yahooResp
		if err := json.NewDecoder(resp.Body).Decode(&yr); err != nil {
			return nil, err
		}
		if len(yr.Chart.Result) == 0 || len(yr.Chart.Result[0].Indicators.Quote) == 0 {
			return nil, fmt.Errorf("yahoo empty")
		}
		res := yr.Chart.Result[0]
		q := res.Indicators.Quote[0]
		out := []map[string]any{}
		for i, ts := range res.Timestamp {
			if i >= len(q.Close) || q.Close[i] == nil || *q.Close[i] <= 0 {
				continue
			}
			c := *q.Close[i]
			val := func(p []*float64, def float64) float64 {
				if i < len(p) && p[i] != nil && *p[i] > 0 {
					return *p[i]
				}
				return def
			}
			var t any
			if b.intraday {
				t = ts
			} else {
				t = time.Unix(ts, 0).UTC().Format("2006-01-02")
			}
			vol := int64(0)
			if i < len(q.Volume) && q.Volume[i] != nil && *q.Volume[i] > 0 {
				vol = int64(*q.Volume[i])
			}
			// Round a 2 decimali come il Python (round(..., 2)).
			o, h, l := round2(val(q.Open, c)), round2(val(q.High, c)), round2(val(q.Low, c))
			c = round2(c)
			out = append(out, map[string]any{
				"time": t, "open": o, "high": h,
				"low": l, "close": c, "value": c, "volume": vol,
			})
		}
		if len(out) == 0 {
			return nil, fmt.Errorf("yahoo empty")
		}
		return out, nil
	})
	if err != nil {
		return nil, false
	}
	out, _ := v.([]map[string]any)
	return out, true
}

// lastDBPrice ritorna l'ultimo prezzo DB come candela singola (fallback su 429).
func lastDBPrice(db *sql.DB, ticker string) []map[string]any {
	var o, h, l, c sql.NullFloat64
	var v sql.NullInt64
	var ts string
	err := db.QueryRow(`
		SELECT ph.open, ph.high, ph.low, ph.close, ph.volume, ph.timestamp
		  FROM price_history ph JOIN stocks s ON s.id = ph.stock_id
		 WHERE s.ticker = ? ORDER BY ph.timestamp DESC LIMIT 1`, ticker,
	).Scan(&o, &h, &l, &c, &v, &ts)
	if err != nil || !c.Valid || c.Float64 <= 0 {
		return nil
	}
	close := c.Float64
	day := time.Now().UTC().Format("2006-01-02")
	if parsed, err := time.Parse("2006-01-02 15:04:05", ts); err == nil {
		day = parsed.Format("2006-01-02")
	}
	vol := int64(0)
	if v.Valid {
		vol = v.Int64
	}
	return []map[string]any{{
		"time": day, "open": fOr(o, close), "high": fOr(h, close),
		"low": fOr(l, close), "close": close, "value": close, "volume": vol,
	}}
}
