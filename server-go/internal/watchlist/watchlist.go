// Package watchlist implementa GET /api/watchlist/ in sola lettura
// (Fase-1) con lo stesso contratto JSON del backend Python
// (backend/routers/watchlist.py), SENZA deep-dive N x history 6mo:
//
// i prezzi sono batch leggeri da price_history (ultima chiusura DB per
// stock); i campi tecnici (rsi, 52w, pe, dividend) usano valori neutri o
// min/max DB quando disponibili.
package watchlist

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"stockmon/internal/auth"
)

const cacheTTL = 300 * time.Second

type cacheEntry struct {
	body    []byte
	etag    string
	expires time.Time
}

var (
	mu    sync.Mutex
	cache = map[string]cacheEntry{}
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func detectMarketCurrency(ticker string) (string, string) {
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

func strOr(ns sql.NullString, def string) string {
	if ns.Valid && ns.String != "" {
		return ns.String
	}
	return def
}

func floatOr(nf sql.NullFloat64, def float64) float64 {
	if nf.Valid {
		return nf.Float64
	}
	return def
}

// List GET /api/watchlist/ — solo lettura Fase-1.
func List(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		u := auth.FromContext(r.Context())
		if u == nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"detail": "Sessione non valida o scaduta. Effettua il login."})
			return
		}
		key := fmt.Sprintf("watch:%d", u.ID)

		now := time.Now()
		mu.Lock()
		if e, ok := cache[key]; ok && now.Before(e.expires) {
			mu.Unlock()
			if r.Header.Get("If-None-Match") == e.etag {
				w.WriteHeader(http.StatusNotModified)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("ETag", e.etag)
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(e.body)
			return
		}
		mu.Unlock()

		body, etag, err := build(db, u.ID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		mu.Lock()
		cache[key] = cacheEntry{body: body, etag: etag, expires: now.Add(cacheTTL)}
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

func build(db *sql.DB, userID int64) ([]byte, string, error) {
	rows, err := db.Query(`
		SELECT wi.id, wi.stock_id, wi.notes, wi.alert_above, wi.alert_below,
		       wi.added_at, s.ticker, s.name, s.market, s.currency,
		       (SELECT ph.close FROM price_history ph
		         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1),
		       (SELECT ph.close FROM price_history ph
		         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1 OFFSET 1),
		       (SELECT ph.high FROM price_history ph
		         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1),
		       (SELECT ph.low FROM price_history ph
		         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1),
		       (SELECT MAX(ph.close) FROM price_history ph WHERE ph.stock_id = s.id),
		       (SELECT MIN(ph.close) FROM price_history ph WHERE ph.stock_id = s.id),
		       EXISTS(SELECT 1 FROM holdings h WHERE h.stock_id = s.id AND h.user_id = ?)
		  FROM watchlist_items wi JOIN stocks s ON s.id = wi.stock_id
		 WHERE wi.user_id = ?`, userID, userID)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()

	out := []any{}
	for rows.Next() {
		var id, stockID int64
		var notes, addedAt sql.NullString
		var above, below sql.NullFloat64
		var ticker string
		var name, mkt, cur sql.NullString
		var last, prev, high, low, max52, min52 sql.NullFloat64
		var inPf any
		if err := rows.Scan(&id, &stockID, &notes, &above, &below, &addedAt,
			&ticker, &name, &mkt, &cur, &last, &prev, &high, &low,
			&max52, &min52, &inPf); err != nil {
			return nil, "", err
		}
		fbMkt, fbCur := detectMarketCurrency(ticker)
		price := 0.0
		if last.Valid && last.Float64 > 0 {
			price = last.Float64
		}
		chgAbs, chgPct := 0.0, 0.0
		if last.Valid && last.Float64 > 0 && prev.Valid && prev.Float64 > 0 {
			chgAbs = price - prev.Float64
			chgPct = (price - prev.Float64) / prev.Float64 * 100
		}
		triggered := false
		if above.Valid && price >= above.Float64 && price > 0 {
			triggered = true
		} else if below.Valid && price <= below.Float64 && price > 0 {
			triggered = true
		}
		hi52 := floatOr(max52, price)
		lo52 := floatOr(min52, price)
		pct52 := 50.0
		if hi52 > lo52 {
			pct52 = (price - lo52) / (hi52 - lo52) * 100
		}
		inPortfolio := false
		switch t := inPf.(type) {
		case int64:
			inPortfolio = t != 0
		case bool:
			inPortfolio = t
		}
		item := map[string]any{
			"id": id, "stock_id": stockID, "ticker": ticker,
			"name":   strOr(name, ticker),
			"market": strOr(mkt, fbMkt), "currency": strOr(cur, fbCur),
			"current_price": price,
			"change_abs":    chgAbs, "change_percent": chgPct,
			"day_high": floatOr(high, price), "day_low": floatOr(low, price),
			"fifty_two_week_high": hi52, "fifty_two_week_low": lo52,
			"fifty_two_week_pct": pct52,
			"pe_ratio":           nil, "dividend_yield": nil,
			// Fase-1: nessun deep-dive, indicatori neutri.
			"rsi": 50.0, "rsi_status": "Neutro", "rsi_badge": "badge-hold",
			"notes":       strOr(notes, ""),
			"alert_above": nil, "alert_below": nil,
			"alert_triggered": triggered,
			"is_in_portfolio": inPortfolio,
			"added_at":        strOr(addedAt, ""),
		}
		if above.Valid {
			item["alert_above"] = above.Float64
		}
		if below.Valid {
			item["alert_below"] = below.Float64
		}
		if !addedAt.Valid || addedAt.String == "" {
			item["added_at"] = nil
		}
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, "", err
	}
	body, err := json.Marshal(out)
	if err != nil {
		return nil, "", err
	}
	sum := sha256.Sum256(body)
	return body, `"` + hex.EncodeToString(sum[:]) + `"`, nil
}
