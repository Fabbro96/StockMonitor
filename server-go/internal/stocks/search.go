// Suggerimenti ticker all'aggiunta titolo: GET /api/stocks/search?q=
// (contratto Flutter: array {ticker,name,market}, max ~8).
//
// Yahoo v1/finance/search con stesso client del package (cookiejar, UA
// Chrome/124 fisso), timeout ~5s, singleflight per q normalizzata, cache
// memoria TTL 10min + ETag/304 come dashboard. Su errore Yahoo/429: 200 con
// array vuoto (mai 500). La query non viene mai loggata oltre 32 char.

package stocks

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// SearchResult è un suggerimento {ticker,name,market} (snake_case JSON).
type SearchResult struct {
	Ticker string `json:"ticker"`
	Name   string `json:"name"`
	Market string `json:"market"`
}

// searchTTL è la cache memoria dei suggerimenti (10min).
const searchTTL = 10 * time.Minute

// searchMax è il tetto risultati (contratto Flutter ~8).
const searchMax = 8

// searchBaseURL è overridabile nei test (mock httptest).
var searchBaseURL = "https://query1.finance.yahoo.com/v1/finance/search"

// shortQ tronca la query per i log (mai oltre 32 char).
func shortQ(q string) string {
	if len([]rune(q)) > 32 {
		return string([]rune(q)[:32]) + "…"
	}
	return q
}

type yahooSearchResp struct {
	Quotes []struct {
		Symbol    string `json:"symbol"`
		ShortName string `json:"shortname"`
		LongName  string `json:"longname"`
	} `json:"quotes"`
}

// fetchSearchResults interroga Yahoo (singleflight per q normalizzata).
// Ritorna errore su 429/rete/parse: il chiamante ricade su [] (mai 500).
func fetchSearchResults(qNorm, qRaw string) ([]SearchResult, error) {
	v, err, _ := sf.Do("search:"+qNorm, func() (any, error) {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		u := searchBaseURL + "?q=" + url.QueryEscape(qRaw) + "&quotesCount=8&newsCount=0"
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
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
			return nil, fmt.Errorf("yahoo search %d", resp.StatusCode)
		}
		var yr yahooSearchResp
		if err := json.NewDecoder(resp.Body).Decode(&yr); err != nil {
			return nil, err
		}
		out := make([]SearchResult, 0, searchMax)
		for _, qt := range yr.Quotes {
			sym := strings.TrimSpace(strings.ToUpper(qt.Symbol))
			if sym == "" {
				continue // scarta quote senza symbol
			}
			name := strings.TrimSpace(qt.ShortName)
			if name == "" {
				name = strings.TrimSpace(qt.LongName)
			}
			if name == "" {
				name = sym
			}
			mkt, _ := detectMarket(sym)
			out = append(out, SearchResult{Ticker: sym, Name: name, Market: mkt})
			if len(out) >= searchMax {
				break
			}
		}
		return out, nil
	})
	if err != nil {
		return nil, err
	}
	out, _ := v.([]SearchResult)
	if out == nil {
		return []SearchResult{}, nil
	}
	return out, nil
}

// detectMarket riusa DetectMarketCurrency di db senza import cycle
// (stocks non importa internal/db): replica minimale per suffissi.
func detectMarket(symbol string) (string, string) {
	t := strings.TrimSpace(strings.ToUpper(symbol))
	switch {
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

// ResolveTicker risolve un testo libero nel miglior symbol Yahoo (1 chiamata,
// via stessa fetch+singleflight dell'endpoint): match esatto su symbol upper,
// altrimenti primo risultato il cui symbol contiene q. Ritorna ok=false se
// Yahoo non risolve (il chiamante salva testo libero, mai 422).
func ResolveTicker(query string) (ticker, name string, ok bool) {
	qRaw := strings.TrimSpace(query)
	if qRaw == "" {
		return "", "", false
	}
	qNorm := strings.ToUpper(qRaw)
	results, err := fetchSearchResults(qNorm, qRaw)
	if err != nil || len(results) == 0 {
		log.Printf("search resolve %q: nessun match (%v)", shortQ(qRaw), err != nil)
		return "", "", false
	}
	for _, r := range results {
		if r.Ticker == qNorm {
			return r.Ticker, r.Name, true
		}
	}
	for _, r := range results {
		// MEDIOLANUM→MED.MI: vale il contains in entrambi i versi.
		if strings.Contains(r.Ticker, qNorm) || strings.Contains(qNorm, r.Ticker) {
			log.Printf("search resolve %q → %s", shortQ(qRaw), r.Ticker)
			return r.Ticker, r.Name, true
		}
	}
	// Ultima spiaggia: top-1 di Yahoo (è comunque un symbol reale, meglio
	// del testo libero zombie).
	log.Printf("search resolve %q → top-1 %s", shortQ(qRaw), results[0].Ticker)
	return results[0].Ticker, results[0].Name, true
}

// Search GET /api/stocks/search?q= — q min 2 char (400), max ~8 risultati.
func Search() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		qRaw := strings.TrimSpace(r.URL.Query().Get("q"))
		if len([]rune(qRaw)) < 2 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Parametro q minimo 2 caratteri."})
			return
		}
		qNorm := strings.ToUpper(qRaw)
		key := "search:" + qNorm

		now := time.Now()
		mu.Lock()
		if e, ok := cache[key]; ok && now.Before(e.expires) {
			mu.Unlock()
			serveCached(w, r, e)
			return
		}
		mu.Unlock()

		results, err := fetchSearchResults(qNorm, qRaw)
		if err != nil {
			// Fallback: nessuna lista nota in codice → array vuoto 200.
			log.Printf("search %q: yahoo ko, fallback vuoto", shortQ(qRaw))
			results = []SearchResult{}
		}
		body, err := json.Marshal(results)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		sum := sha256.Sum256(body)
		etag := `"` + hex.EncodeToString(sum[:]) + `"`
		mu.Lock()
		cache[key] = cacheEntry{body: body, etag: etag, expires: now.Add(searchTTL)}
		mu.Unlock()

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
