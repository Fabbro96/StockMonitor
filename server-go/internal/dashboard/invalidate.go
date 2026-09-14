package dashboard

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// InvalidateUser elimina le entry di cache per-utente (root + performance
// per ogni days). Chiamata dopo ogni scrittura holdings/watchlist/alerts.
func InvalidateUser(userID int64) {
	prefixes := []string{
		fmt.Sprintf("dash:root:%d", userID),
		fmt.Sprintf("dash:perf:%d:", userID),
	}
	mu.Lock()
	defer mu.Unlock()
	for k := range cache {
		for _, p := range prefixes {
			if strings.HasPrefix(k, p) {
				delete(cache, k)
				break
			}
		}
	}
}

// InvalidateDailyCache invalida la serie precomputata del giorno dopo
// scritture holdings/transactions (serie e metriche non più attendibili).
// Gli endpoint ricadono su on-demand (X-Cache: MISS) fino al prossimo
// PrecomputeOnce. No-op con writer nil (DB_MODE=ro).
func InvalidateDailyCache(wdb *sql.DB) {
	if wdb == nil {
		return
	}
	today := time.Now().UTC().Format("2006-01-02")
	_, _ = wdb.Exec(`DELETE FROM portfolio_daily_cache WHERE day = ?`, today)
	// Via anche tutte le mem-entry (potrebbero aver servito la serie vecchia).
	mu.Lock()
	cache = map[string]cacheEntry{}
	mu.Unlock()
}

// InvalidateAll elimina le entry globali (heatmap/indices). Chiamata dopo
// scritture che cambiano i prezzi o gli stock monitorati.
func InvalidateAll() {
	mu.Lock()
	defer mu.Unlock()
	delete(cache, "dash:heatmap")
	delete(cache, "dash:indices")
	delete(cache, "dash:market-status")
}
