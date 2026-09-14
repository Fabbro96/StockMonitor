// Batch prezzi per lo scheduler Fase-2: ultime 2 chiusure giornaliere via
// Yahoo chart v8 (range=2d), riusando client cookiejar + UA fisso +
// singleflight del package. Solo prezzi reali: errori/429/vuoti -> assenti
// (mai fallback sintetici, come fetch_all_prices del Python che scarta gli
// stale prima di persistere).

package stocks

import (
	"encoding/json"
	"net/http"
	"net/url"
	"sync"
	"time"
)

// Quote è l'ultima barra giornaliera reale con la chiusura precedente.
type Quote struct {
	Open      float64
	High      float64
	Low       float64
	Close     float64
	PrevClose float64
	Volume    int64
	OK        bool
}

func fetchDaily(ticker string) (Quote, error) {
	v, err, _ := sf.Do("daily:"+ticker, func() (any, error) {
		u := "https://query1.finance.yahoo.com/v8/finance/chart/" + url.PathEscape(ticker) +
			"?range=2d&interval=1d"
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
		if resp.StatusCode != http.StatusOK {
			return nil, &httpError{status: resp.StatusCode}
		}
		var yr yahooResp
		if err := json.NewDecoder(resp.Body).Decode(&yr); err != nil {
			return nil, err
		}
		if len(yr.Chart.Result) == 0 || len(yr.Chart.Result[0].Indicators.Quote) == 0 {
			return nil, errEmpty
		}
		res := yr.Chart.Result[0]
		q := res.Indicators.Quote[0]
		// Ultima chiusura valida (dalla fine) + precedente valida.
		i := -1
		for k := len(q.Close) - 1; k >= 0; k-- {
			if q.Close[k] != nil && *q.Close[k] > 0 {
				i = k
				break
			}
		}
		if i < 0 {
			return nil, errEmpty
		}
		val := func(p []*float64, def float64) float64 {
			if i < len(p) && p[i] != nil && *p[i] > 0 {
				return *p[i]
			}
			return def
		}
		c := round2(*q.Close[i])
		prev := c
		for k := i - 1; k >= 0; k-- {
			if q.Close[k] != nil && *q.Close[k] > 0 {
				prev = round2(*q.Close[k])
				break
			}
		}
		vol := int64(0)
		if i < len(q.Volume) && q.Volume[i] != nil && *q.Volume[i] > 0 {
			vol = int64(*q.Volume[i])
		}
		return Quote{
			Open: round2(val(q.Open, c)), High: round2(val(q.High, c)),
			Low: round2(val(q.Low, c)), Close: c, PrevClose: prev,
			Volume: vol, OK: true,
		}, nil
	})
	if err != nil {
		return Quote{}, err
	}
	qt, _ := v.(Quote)
	return qt, nil
}

type httpError struct{ status int }

func (e *httpError) Error() string {
	return "yahoo status " + http.StatusText(e.status)
}

var errEmpty = &httpError{status: -1}

// FetchLastCloses scarica le ultime chiusure per i ticker (concorrenza
// limitata a 4, budget totale ~15s come BATCH_FETCH_TIMEOUT_BACKGROUND).
// Ritorna solo i ticker con prezzo reale.
func FetchLastCloses(tickers []string) map[string]Quote {
	out := map[string]Quote{}
	if len(tickers) == 0 {
		return out
	}
	type res struct {
		ticker string
		q      Quote
	}
	sem := make(chan struct{}, 4)
	ch := make(chan res, len(tickers))
	var wg sync.WaitGroup
	for _, t := range tickers {
		t := t
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if q, err := fetchDaily(t); err == nil && q.OK {
				ch <- res{t, q}
			}
		}()
	}
	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	timeout := time.After(15 * time.Second)
loop:
	for {
		select {
		case r, ok := <-ch:
			if !ok {
				break loop
			}
			out[r.ticker] = r.q
		case <-done:
			// Svuota eventuali risultati già pronti, poi esci.
			for {
				select {
				case r := <-ch:
					out[r.ticker] = r.q
				default:
					break loop
				}
			}
		case <-timeout:
			break loop
		}
	}
	return out
}
