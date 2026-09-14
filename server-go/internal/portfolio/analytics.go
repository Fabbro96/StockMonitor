// Endpoint analytics Fase-2 pack-perf (GET /api/portfolio/risk-metrics e
// GET /api/portfolio/history): serie/metriche dalla daily-cache fresca
// (<24h, X-Cache HIT alla seconda chiamata via mem-cache 300s), altrimenti
// calcolo on-demand dallo stesso codice (X-Cache MISS). Shape snake_case.

package portfolio

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"stockmon/internal/dailycache"
)

const analyticsMemTTL = 300 * time.Second

type memEntry struct {
	body    []byte
	etag    string
	expires time.Time
}

var (
	analyticsMu    sync.Mutex
	analyticsCache = map[string]memEntry{}
)

// analyticsCached serve build() con mem-cache 300s + ETag + X-Cache,
// stessa semantica di dashboard.cached.
func analyticsCached(w http.ResponseWriter, r *http.Request, key string, build func() (any, error)) {
	now := time.Now()
	analyticsMu.Lock()
	if e, ok := analyticsCache[key]; ok && now.Before(e.expires) {
		analyticsMu.Unlock()
		if r.Header.Get("If-None-Match") == e.etag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("ETag", e.etag)
		w.Header().Set("X-Cache", "HIT")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(e.body)
		return
	}
	analyticsMu.Unlock()

	v, err := build()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
		return
	}
	body, err := json.Marshal(v)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
		return
	}
	sum := sha256.Sum256(body)
	etag := `"` + hex.EncodeToString(sum[:]) + `"`
	analyticsMu.Lock()
	analyticsCache[key] = memEntry{body: body, etag: etag, expires: now.Add(analyticsMemTTL)}
	analyticsMu.Unlock()

	if r.Header.Get("If-None-Match") == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("ETag", etag)
	w.Header().Set("X-Cache", "MISS")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}

// InvalidateAnalytics elimina le mem-entry analytics dell'utente.
func InvalidateAnalytics(userID int64) {
	p := fmt.Sprintf("analytics:%d:", userID)
	analyticsMu.Lock()
	defer analyticsMu.Unlock()
	for k := range analyticsCache {
		if strings.HasPrefix(k, p) {
			delete(analyticsCache, k)
		}
	}
}

// userSeriesAndMetrics ritorna serie+metriche: da daily-cache fresca se
// disponibile, altrimenti on-demand. Riporta la sorgente per log/source.
func userSeriesAndMetrics(read *sql.DB, userID int64, days int) ([]dailycache.DayValue, map[string]float64, string) {
	if p, ok := dailycache.ReadFresh(read); ok {
		if uc, found := p.Users[fmt.Sprintf("%d", userID)]; found && len(uc.Series) > 0 {
			log.Printf("analytics user %d: daily-cache HIT (%s)", userID, p.Day)
			n := days
			if n > len(uc.Series) {
				n = len(uc.Series)
			}
			return uc.Series[len(uc.Series)-n:], uc.Metrics, "cache"
		}
		log.Printf("analytics user %d: daily-cache MISS (utente assente)", userID)
	} else {
		log.Printf("analytics user %d: daily-cache MISS (on-demand)", userID)
	}
	series, metrics, err := dailycache.ComputeUserSeries(read, userID, days)
	if err != nil {
		return nil, map[string]float64{"days": float64(days)}, "fallback"
	}
	return series, metrics, "live"
}

func clampDays(r *http.Request, def, max int) int {
	days := def
	if s := strings.TrimSpace(r.URL.Query().Get("days")); s != "" {
		if n, err := strconv.Atoi(s); err == nil {
			days = n
		}
	}
	if days < 1 {
		days = 1
	}
	if days > max {
		days = max
	}
	return days
}

// RiskMetrics GET /api/portfolio/risk-metrics?days=90.
func RiskMetrics(read, _ *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		u := userOr401(w, r)
		if u == nil {
			return
		}
		days := clampDays(r, 90, 365)
		analyticsCached(w, r, fmt.Sprintf("analytics:%d:risk:%d", u.ID, days), func() (any, error) {
			_, metrics, source := userSeriesAndMetrics(read, u.ID, days)
			out := map[string]any{"days": days, "source": source}
			for k, v := range metrics {
				out[k] = v
			}
			return out, nil
		})
	}
}

// History GET /api/portfolio/history?days=90 (serie valore portafoglio).
func History(read, _ *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		u := userOr401(w, r)
		if u == nil {
			return
		}
		days := clampDays(r, 90, 365)
		analyticsCached(w, r, fmt.Sprintf("analytics:%d:hist:%d", u.ID, days), func() (any, error) {
			series, _, source := userSeriesAndMetrics(read, u.ID, days)
			data := make([]any, 0, len(series))
			for _, dv := range series {
				data = append(data, map[string]any{"date": dv.Date, "value": dv.Value})
			}
			return map[string]any{"data": data, "source": source, "points": len(data)}, nil
		})
	}
}
