// Package dashboard implementa le route GET /api/dashboard/* in sola
// lettura (Fase-1), con lo stesso contratto JSON del backend Python
// (backend/routers/dashboard.py):
//
//   - GET /api/dashboard/              portfolio_summary + recent_advices +
//     active_alerts_count + market_status
//   - GET /api/dashboard/market-status blocco orologi statico (nessuna
//     chiamata Yahoo live: calcolo su orari Europe/Rome, Europe/Paris,
//     America/New_York)
//   - GET /api/dashboard/indices      ultime chiusure DB per gli 8 indici
//     globali (fallback statico, stale=true se assenti)
//   - GET /api/dashboard/heatmap      titoli attivi + ultime 2 chiusure DB
//   - GET /api/dashboard/performance  serie piatta di fallback dal totale
//     corrente (source=fallback)
//
// Tutte le risposte sono cachate in memoria 300s con ETag/If-None-Match.
// Prezzi e FX sono SOLO da DB: tasso USD->EUR fisso di fallback (0.9259,
// stesso del Python) perché Fase-1 non chiama Yahoo.
package dashboard

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

	"stockmon/internal/auth"
	"stockmon/internal/dailycache"
)

// usdToEurFallback allineato al fallback di MarketDataService.get_fx_rate.
const usdToEurFallback = 0.9259

// cacheTTL è il TTL unico Fase-1 per tutte le dashboard (300s).
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

// cached serve build() con cache in memoria + ETag/If-None-Match.
func cached(w http.ResponseWriter, r *http.Request, key string, build func() (any, error)) {
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
		w.Header().Set("X-Cache", "HIT")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(e.body)
		return
	}
	mu.Unlock()

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
	mu.Lock()
	cache[key] = cacheEntry{body: body, etag: etag, expires: now.Add(cacheTTL)}
	mu.Unlock()

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

// ---------------------------------------------------------------------------
// market status statico (stesso shape di build_market_status in Python)
// ---------------------------------------------------------------------------

func isOpen(tz, open, close string) bool {
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

// MarketStatus ricalca build_market_status() del Python senza toccare il DB.
func MarketStatus() map[string]any {
	it := isOpen("Europe/Rome", "09:00", "17:30")
	eu := isOpen("Europe/Paris", "09:00", "17:30")
	us := isOpen("America/New_York", "09:30", "16:00")
	anyOpen := it || eu || us
	st := func(b bool) string {
		if b {
			return "OPEN"
		}
		return "CLOSED"
	}
	return map[string]any{
		"IT": st(it), "US": st(us), "EU": st(eu), "ANY_OPEN": st(anyOpen),
		"details": map[string]any{
			"IT": map[string]any{"name": "Borsa Italiana (Milano)", "flag": "🇮🇹", "status": st(it), "hours": "09:00 - 17:30"},
			"US": map[string]any{"name": "Wall Street (New York)", "flag": "🇺🇸", "status": st(us), "hours": "15:30 - 22:00"},
		},
	}
}

// ---------------------------------------------------------------------------
// helpers DB (solo letture)
// ---------------------------------------------------------------------------

// detectMarketCurrency porta di backend/utils/helpers.py.
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

type holding struct {
	ID         int64
	StockID    int64
	Ticker     string
	Name       sql.NullString
	Market     sql.NullString
	Currency   sql.NullString
	Qty        float64
	AvgPrice   float64
	LastClose  sql.NullFloat64
	PrevClose  sql.NullFloat64
	PurchaseDt sql.NullString
	Notes      sql.NullString
}

func loadHoldings(db *sql.DB, userID int64) ([]holding, error) {
	rows, err := db.Query(`
		SELECT h.id, h.stock_id, s.ticker, s.name, s.market, s.currency,
		       h.quantity, h.avg_purchase_price, h.purchase_date, h.notes,
		       (SELECT ph.close FROM price_history ph
		         WHERE ph.stock_id = h.stock_id ORDER BY ph.timestamp DESC LIMIT 1),
		       (SELECT ph.close FROM price_history ph
		         WHERE ph.stock_id = h.stock_id ORDER BY ph.timestamp DESC LIMIT 1 OFFSET 1)
		  FROM holdings h JOIN stocks s ON s.id = h.stock_id
		 WHERE h.user_id = ? AND s.is_active = 1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []holding
	for rows.Next() {
		var h holding
		if err := rows.Scan(&h.ID, &h.StockID, &h.Ticker, &h.Name, &h.Market,
			&h.Currency, &h.Qty, &h.AvgPrice, &h.PurchaseDt, &h.Notes,
			&h.LastClose, &h.PrevClose); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}

func round2(f float64) float64 {
	if f >= 0 {
		return float64(int64(f*100+0.5)) / 100
	}
	return float64(int64(f*100-0.5)) / 100
}

func strOr(ns sql.NullString, def string) string {
	if ns.Valid && ns.String != "" {
		return ns.String
	}
	return def
}

// portfolioSummary replica build_portfolio_summary (solo prezzi DB; le righe
// senza chiusura DB usano avg_purchase_price come prezzo corrente).
func portfolioSummary(db *sql.DB, userID int64) (map[string]any, error) {
	hs, err := loadHoldings(db, userID)
	if err != nil {
		return nil, err
	}
	type row struct {
		m    map[string]any
		pct  float64
		mkt  string
		val  float64
		inv  float64
		dPNL float64
		prev float64
	}
	var rows []row
	var totalVal, totalInv, dailyPNL, prevBase float64
	alloc := map[string]float64{"IT": 0, "US": 0, "EU": 0}
	hasDaily := false
	for _, h := range hs {
		fbMkt, fbCur := detectMarketCurrency(h.Ticker)
		mkt := strOr(h.Market, fbMkt)
		cur := strOr(h.Currency, fbCur)
		fx := 1.0
		if cur == "USD" {
			fx = usdToEurFallback
		}
		price := h.AvgPrice
		stale := true
		if h.LastClose.Valid && h.LastClose.Float64 > 0 {
			price = h.LastClose.Float64
			stale = false
		}
		var prev any
		var prevF float64
		var dPNL *float64
		if h.PrevClose.Valid && h.PrevClose.Float64 > 0 {
			prevF = h.PrevClose.Float64
			prev = prevF
			d := round2((price - prevF) * h.Qty)
			dPNL = &d
			dailyPNL += (price - prevF) * h.Qty * fx
			prevBase += prevF * h.Qty * fx
			hasDaily = true
		}
		invested := h.Qty * h.AvgPrice
		value := h.Qty * price
		pnlAbs := round2(value - invested)
		var pnlPct float64
		if invested > 0 {
			pnlPct = round2((value - invested) / invested * 100)
		}
		m := map[string]any{
			"id": h.ID, "stock_id": h.StockID, "ticker": h.Ticker,
			"name": strOr(h.Name, h.Ticker), "market": mkt, "currency": cur,
			"quantity": h.Qty, "avg_purchase_price": h.AvgPrice,
			"current_price": price, "previous_close": prev,
			"price_stale": stale,
			"total_value": round2(value), "total_invested": round2(invested),
			"total_value_eur": round2(value * fx), "total_invested_eur": round2(invested * fx),
			"fx_rate_to_eur": fx,
			"pnl_absolute":   pnlAbs, "pnl_percent": pnlPct,
			"daily_pnl": nil, "purchase_date": nil, "notes": strOr(h.Notes, ""),
		}
		if dPNL != nil {
			m["daily_pnl"] = *dPNL
		}
		if h.PurchaseDt.Valid {
			m["purchase_date"] = h.PurchaseDt.String
		}
		rows = append(rows, row{m: m, pct: pnlPct, mkt: mkt, val: value * fx, inv: invested * fx})
		totalVal += value * fx
		totalInv += invested * fx
		mu2 := strings.ToUpper(mkt)
		if _, ok := alloc[mu2]; ok {
			alloc[mu2] += value * fx
		} else {
			alloc["US"] += value * fx
		}
	}
	pnl := totalVal - totalInv
	var pnlPct float64
	if totalInv > 0 {
		pnlPct = pnl / totalInv * 100
	}
	var dPct float64
	if prevBase > 0 {
		dPct = dailyPNL / prevBase * 100
	}
	var gainer, loser any
	if len(rows) > 0 {
		best, worst := rows[0], rows[0]
		for _, r := range rows[1:] {
			if r.pct > best.pct {
				best = r
			}
			if r.pct < worst.pct {
				worst = r
			}
		}
		if best.pct > 0 {
			gainer = best.m
		}
		if worst.pct < 0 {
			loser = worst.m
		}
	}
	if !hasDaily {
		dailyPNL = 0
	}
	return map[string]any{
		"total_value": round2(totalVal), "total_invested": round2(totalInv),
		"total_pnl": round2(pnl), "total_pnl_percent": round2(pnlPct),
		"daily_pnl": round2(dailyPNL), "daily_pnl_percent": round2(dPct),
		"holdings_count": len(rows),
		"top_gainer":     gainer, "top_loser": loser,
		"market_allocation": map[string]any{
			"IT": round2(alloc["IT"]), "US": round2(alloc["US"]), "EU": round2(alloc["EU"])},
		// Fase-1: rese dividendi non calcolate (servirebbe cache deep-dive).
		"estimated_annual_dividends": 0.0,
		"estimated_dividend_yield":   0.0,
		"fx_usd_eur":                 usdToEurFallback,
	}, nil
}

// hasAdviceUserID rileva una volta se la colonna advices.user_id esiste
// (DB antecedenti alla migrazione multi-utente non ce l'hanno: il backend
// Python la crea all'avvio via init_db; qui fallback senza filtro utente).
var (
	hasAdviceUserIDOnce sync.Once
	hasAdviceUserIDVal  bool
)

func hasAdviceUserID(db *sql.DB) bool {
	hasAdviceUserIDOnce.Do(func() {
		rows, err := db.Query(`SELECT user_id FROM advices LIMIT 0`)
		if err != nil {
			hasAdviceUserIDVal = false
			return
		}
		rows.Close()
		hasAdviceUserIDVal = true
	})
	return hasAdviceUserIDVal
}

// recentAdvices replica user_advice_filter + serialize_advice(short_titles)
// del Python (chiavi camelCase dove il Python le usa: targetPrice,
// suggestedQuantity).
func recentAdvices(db *sql.DB, u *auth.User) ([]any, error) {
	base := `
		SELECT a.id, a.market, a.title, a.action, a.overview, a.reasoning,
		       a.stocks_json, a.risks, a.confidence, a.timeframe,
		       a.target_price, a.suggested_quantity, a.followed,
		       a.timestamp, a.created_at, s.ticker, s.name
		  FROM advices a LEFT JOIN stocks s ON s.id = a.stock_id`
	var rows *sql.Rows
	var err error
	switch {
	case !hasAdviceUserID(db) && u.IsAdmin:
		// DB pre-migrazione: nessun filtro possibile, ultimi 4 globali.
		rows, err = db.Query(base + ` ORDER BY a.timestamp DESC LIMIT 4`)
	case !hasAdviceUserID(db):
		return []any{}, nil
	case u.IsAdmin:
		rows, err = db.Query(base+` WHERE (a.user_id = ? OR a.user_id IS NULL)
			 ORDER BY a.timestamp DESC LIMIT 4`, u.ID)
	default:
		rows, err = db.Query(base+` WHERE a.user_id = ?
			 ORDER BY a.timestamp DESC LIMIT 4`, u.ID)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []any{}
	for rows.Next() {
		var id int64
		var market, title, action, overview, reasoning, stocksJSON, risks,
			confidence, timeframe, ts, createdAt, ticker, name sql.NullString
		var target sql.NullFloat64
		var qty sql.NullInt64
		var followed sql.NullBool
		if err := rows.Scan(&id, &market, &title, &action, &overview, &reasoning,
			&stocksJSON, &risks, &confidence, &timeframe, &target, &qty,
			&followed, &ts, &createdAt, &ticker, &name); err != nil {
			return nil, err
		}
		mkt := strOr(market, "ALL")
		defTitle := "Wall Street"
		if mkt == "IT" {
			defTitle = "Borsa Italiana"
		}
		var analysis any = []any{}
		if stocksJSON.Valid && strings.TrimSpace(stocksJSON.String) != "" {
			var parsed any
			if err := json.Unmarshal([]byte(stocksJSON.String), &parsed); err == nil {
				analysis = parsed
			}
		}
		stamp := strOr(ts, "")
		if stamp == "" {
			stamp = strOr(createdAt, "")
		}
		item := map[string]any{
			"id": id, "market": mkt, "title": strOr(title, defTitle),
			"action": strOr(action, ""), "overview": strOr(overview, ""),
			"strategy": strOr(reasoning, ""), "stocks_analysis": analysis,
			"risks": strOr(risks, ""), "confidence": strOr(confidence, ""),
			"timeframe":   strOr(timeframe, ""),
			"targetPrice": nil, "suggestedQuantity": nil,
			"followed":  followed.Valid && followed.Bool,
			"timestamp": stamp,
			"ticker":    strOr(ticker, ""), "name": strOr(name, ""),
		}
		if target.Valid {
			item["targetPrice"] = target.Float64
		}
		if qty.Valid {
			item["suggestedQuantity"] = qty.Int64
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func activeAlertsCount(db *sql.DB, userID int64) (int64, error) {
	var n int64
	err := db.QueryRow(`SELECT COUNT(*) FROM alert_rules WHERE is_active = 1 AND user_id = ?`, userID).Scan(&n)
	return n, err
}

// ---------------------------------------------------------------------------
// handlers
// ---------------------------------------------------------------------------

// Root GET /api/dashboard/ (auth via middleware, utente dal context).
func Root(db *sql.DB) http.HandlerFunc {
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
		cached(w, r, fmt.Sprintf("dash:root:%d", u.ID), func() (any, error) {
			summary, err := portfolioSummary(db, u.ID)
			if err != nil {
				return nil, err
			}
			adv, err := recentAdvices(db, u)
			if err != nil {
				return nil, err
			}
			n, err := activeAlertsCount(db, u.ID)
			if err != nil {
				return nil, err
			}
			return map[string]any{
				"portfolio_summary":   summary,
				"recent_advices":      adv,
				"active_alerts_count": n,
				"market_status":       MarketStatus(),
			}, nil
		})
	}
}

// MarketStatusHandler GET /api/dashboard/market-status.
func MarketStatusHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		cached(w, r, "dash:market-status", func() (any, error) { return MarketStatus(), nil })
	}
}

var globalIndices = []struct {
	ticker, name, flag, typ string
}{
	{"FTSEMIB.MI", "FTSE MIB", "🇮🇹", "index"},
	{"^GSPC", "S&P 500", "🇺🇸", "index"},
	{"^IXIC", "NASDAQ", "🇺🇸", "index"},
	{"^GDAXI", "DAX 40", "🇩🇪", "index"},
	{"EURUSD=X", "EUR/USD", "💱", "forex"},
	{"BTC-USD", "Bitcoin", "🪙", "crypto"},
	{"GC=F", "Oro", "🥇", "commodity"},
	{"CL=F", "Petrolio WTI", "🛢️", "commodity"},
}

// Indices GET /api/dashboard/indices (DB-only + fallback statici stale).
func Indices(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		cached(w, r, "dash:indices", func() (any, error) {
			out := []any{}
			for _, g := range globalIndices {
				var last, prev sql.NullFloat64
				_ = db.QueryRow(`
					SELECT (SELECT ph.close FROM price_history ph
					         JOIN stocks s ON s.id = ph.stock_id
					        WHERE s.ticker = ? ORDER BY ph.timestamp DESC LIMIT 1),
					       (SELECT ph.close FROM price_history ph
					         JOIN stocks s ON s.id = ph.stock_id
					        WHERE s.ticker = ? ORDER BY ph.timestamp DESC LIMIT 1 OFFSET 1)`,
					g.ticker, g.ticker).Scan(&last, &prev)
				price, chgAbs, chgPct, stale := 0.0, 0.0, 0.0, true
				if last.Valid && last.Float64 > 0 {
					price = last.Float64
					stale = false
					if prev.Valid && prev.Float64 > 0 {
						chgAbs = round2(price - prev.Float64)
						chgPct = round2((price - prev.Float64) / prev.Float64 * 100)
					}
				}
				out = append(out, map[string]any{
					"ticker": g.ticker, "name": g.name, "flag": g.flag, "type": g.typ,
					"price": price, "change_abs": chgAbs, "change_percent": chgPct,
					"stale": stale,
				})
			}
			return out, nil
		})
	}
}

// Heatmap GET /api/dashboard/heatmap (titoli attivi + ultime 2 chiusure DB).
func Heatmap(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		cached(w, r, "dash:heatmap", func() (any, error) {
			rows, err := db.Query(`
				SELECT s.ticker, s.name, s.market, s.currency,
				       (SELECT ph.close FROM price_history ph
				         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1),
				       (SELECT ph.close FROM price_history ph
				         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1 OFFSET 1),
				       (SELECT ph.high FROM price_history ph
				         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1),
				       (SELECT ph.low FROM price_history ph
				         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1),
				       (SELECT ph.volume FROM price_history ph
				         WHERE ph.stock_id = s.id ORDER BY ph.timestamp DESC LIMIT 1)
				  FROM stocks s WHERE s.is_active = 1`)
			if err != nil {
				return nil, err
			}
			defer rows.Close()
			out := []any{}
			for rows.Next() {
				var ticker string
				var name, mkt, cur sql.NullString
				var last, prev, high, low sql.NullFloat64
				var vol sql.NullInt64
				if err := rows.Scan(&ticker, &name, &mkt, &cur, &last, &prev, &high, &low, &vol); err != nil {
					return nil, err
				}
				fbMkt, fbCur := detectMarketCurrency(ticker)
				price := 0.0
				stale := true
				if last.Valid && last.Float64 > 0 {
					price = last.Float64
					stale = false
				}
				chgAbs, chgPct := 0.0, 0.0
				if !stale && prev.Valid && prev.Float64 > 0 {
					chgAbs = round2(price - prev.Float64)
					chgPct = round2((price - prev.Float64) / prev.Float64 * 100)
				}
				out = append(out, map[string]any{
					"ticker": ticker, "name": strOr(name, ticker),
					"market": strOr(mkt, fbMkt), "currency": strOr(cur, fbCur),
					"current_price": price, "change_percent": chgPct, "change_abs": chgAbs,
					"day_high": floatOr(high, price), "day_low": floatOr(low, price),
					"volume": intOr(vol, 0), "stale": stale,
				})
			}
			if err := rows.Err(); err != nil {
				return nil, err
			}
			return out, nil
		})
	}
}

func floatOr(f sql.NullFloat64, def float64) float64 {
	if f.Valid {
		return f.Float64
	}
	return def
}

func intOr(i sql.NullInt64, def int64) int64 {
	if i.Valid {
		return i.Int64
	}
	return def
}

// Performance GET /api/dashboard/performance?days=30.
// Pack perf: serie precomputata 90gg se fresca (source=cache), altrimenti
// fallback piatto Fase-1 (source=fallback). Shape invariato.
func Performance(db *sql.DB) http.HandlerFunc {
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
		days := 30
		if s := strings.TrimSpace(r.URL.Query().Get("days")); s != "" {
			if n, err := strconv.Atoi(s); err == nil {
				days = n
			}
		}
		if days < 1 {
			days = 1
		}
		if days > 3650 {
			days = 3650
		}
		cached(w, r, fmt.Sprintf("dash:perf:%d:%d", u.ID, days), func() (any, error) {
			if data, ok := cachedSeries(db, u.ID, days); ok {
				return map[string]any{"data": data, "source": "cache", "points": len(data)}, nil
			}
			hs, err := loadHoldings(db, u.ID)
			if err != nil {
				return nil, err
			}
			total := 0.0
			for _, h := range hs {
				p := h.AvgPrice
				if h.LastClose.Valid && h.LastClose.Float64 > 0 {
					p = h.LastClose.Float64
				}
				fx := 1.0
				_, cur := detectMarketCurrency(h.Ticker)
				if c := strOr(h.Currency, cur); c == "USD" {
					fx = usdToEurFallback
				}
				total += h.Qty * p * fx
			}
			// Serie piatta di fallback (source=fallback come il Python a
			// portafoglio vuoto / cache assente o stale).
			cutoff := time.Now().UTC().AddDate(0, 0, -days)
			data := make([]any, 0, days)
			for i := 0; i < days; i++ {
				data = append(data, map[string]any{
					"date":  cutoff.AddDate(0, 0, i).Format("2006-01-02"),
					"value": round2(total),
				})
			}
			return map[string]any{"data": data, "source": "fallback", "points": len(data)}, nil
		})
	}
}

// cachedSeries legge la serie dell'utente dalla daily-cache fresca
// (ultimi `days` punti). Ritorna ok=false se assente/stale/vuota.
func cachedSeries(db *sql.DB, userID int64, days int) ([]any, bool) {
	p, ok := dailycache.ReadFresh(db)
	if !ok {
		log.Printf("performance user %d: daily-cache MISS (on-demand)", userID)
		return nil, false
	}
	uc, ok := p.Users[fmt.Sprintf("%d", userID)]
	if !ok || len(uc.Series) == 0 {
		log.Printf("performance user %d: daily-cache MISS (utente assente)", userID)
		return nil, false
	}
	log.Printf("performance user %d: daily-cache HIT (%s)", userID, p.Day)
	n := days
	if n > len(uc.Series) {
		n = len(uc.Series)
	}
	tail := uc.Series[len(uc.Series)-n:]
	data := make([]any, 0, n)
	for _, dv := range tail {
		data = append(data, map[string]any{"date": dv.Date, "value": dv.Value})
	}
	return data, true
}
