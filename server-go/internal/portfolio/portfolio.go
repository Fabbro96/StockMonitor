// Package portfolio implementa le scritture Fase-2 di
// backend/routers/portfolio.py: CRUD holdings + transactions
// (la lettura summary resta in dashboard). Validazione minima lato Go,
// FK ON, upsert con media ponderata come il Python.
package portfolio

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"stockmon/internal/auth"
	"stockmon/internal/dashboard"
	"stockmon/internal/db"
	"stockmon/internal/writelock"
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func needWriter(w http.ResponseWriter, wdb *sql.DB) bool {
	if wdb == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"detail": "Database in sola lettura (DB_MODE=ro): scritture disabilitate.",
		})
		return false
	}
	return true
}

func userOr401(w http.ResponseWriter, r *http.Request) *auth.User {
	u := auth.FromContext(r.Context())
	if u == nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{
			"detail": "Sessione non valida o scaduta. Effettua il login.",
		})
		return nil
	}
	return u
}

// canAccess mirror di _can_access_holding/_can_access_transaction.
func canAccess(owner sql.NullInt64, u *auth.User) bool {
	if !owner.Valid {
		return u.IsAdmin
	}
	return owner.Int64 == u.ID
}

func round4(f float64) float64 { return math.Round(f*10000) / 10000 }
func round2(f float64) float64 { return math.Round(f*100) / 100 }

// parseDate accetta "2006-01-02" (e prefissi di RFC3339/datetime).
func parseDate(s string) (string, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", false
	}
	for _, layout := range []string{"2006-01-02", "2006-01-02 15:04:05", time.RFC3339} {
		if t, err := time.Parse(layout, s); err == nil {
			return t.Format("2006-01-02"), true
		}
	}
	if len(s) >= 10 {
		if _, err := time.Parse("2006-01-02", s[:10]); err == nil {
			return s[:10], true
		}
	}
	return "", false
}

// parseDateTime accetta datetime, RFC3339 o data sola (mezzanotte UTC).
func parseDateTime(s string) (string, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", false
	}
	for _, layout := range []string{"2006-01-02 15:04:05", time.RFC3339, "2006-01-02"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t.UTC().Format("2006-01-02 15:04:05"), true
		}
	}
	return "", false
}

type holdingRow struct {
	ID        int64
	Owner     sql.NullInt64
	StockID   int64
	Qty       float64
	Avg       float64
	PurchDate sql.NullString
	Notes     sql.NullString
	Created   sql.NullString
	Updated   sql.NullString
}

func scanHolding(rows *sql.Rows) (holdingRow, error) {
	var h holdingRow
	err := rows.Scan(&h.ID, &h.Owner, &h.StockID, &h.Qty, &h.Avg,
		&h.PurchDate, &h.Notes, &h.Created, &h.Updated)
	return h, err
}

// dateOnly normalizza le DATE lette dal driver (che le rende time.Time ->
// RFC3339) al formato "YYYY-MM-DD" di str(date) del Python.
func dateOnly(s string) string {
	if len(s) >= 10 {
		return s[:10]
	}
	return s
}

func holdingMap(h holdingRow) map[string]any {
	m := map[string]any{
		"id": h.ID, "stock_id": h.StockID, "quantity": h.Qty,
		"avg_purchase_price": h.Avg,
		"purchase_date":      nil,
		"notes":              nil,
		"created_at":         nil,
		"updated_at":         nil,
	}
	if h.Owner.Valid {
		m["user_id"] = h.Owner.Int64
	} else {
		m["user_id"] = nil
	}
	if h.PurchDate.Valid {
		m["purchase_date"] = dateOnly(h.PurchDate.String)
	}
	if h.Notes.Valid {
		m["notes"] = h.Notes.String
	}
	if h.Created.Valid {
		m["created_at"] = h.Created.String
	}
	if h.Updated.Valid {
		m["updated_at"] = h.Updated.String
	}
	return m
}

const holdingCols = `id, user_id, stock_id, quantity, avg_purchase_price,
	purchase_date, notes, created_at, updated_at`

// List GET /api/portfolio/ — posizioni con ultimo prezzo DB (no live).
func List(read, _ *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil {
			return
		}
		rows, err := read.Query(`
			SELECT h.id, h.stock_id, s.ticker, s.name, s.market, s.currency,
			       h.quantity, h.avg_purchase_price, h.purchase_date, h.notes,
			       (SELECT ph.close FROM price_history ph
			         WHERE ph.stock_id = h.stock_id ORDER BY ph.timestamp DESC LIMIT 1),
			       (SELECT ph.close FROM price_history ph
			         WHERE ph.stock_id = h.stock_id ORDER BY ph.timestamp DESC LIMIT 1 OFFSET 1)
			  FROM holdings h JOIN stocks s ON s.id = h.stock_id
			 WHERE h.user_id = ? AND s.is_active = 1`, u.ID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		defer rows.Close()
		out := []any{}
		for rows.Next() {
			var id, stockID int64
			var ticker string
			var name, mkt, cur, purch, notes sql.NullString
			var qty, avg float64
			var last, prev sql.NullFloat64
			if err := rows.Scan(&id, &stockID, &ticker, &name, &mkt, &cur,
				&qty, &avg, &purch, &notes, &last, &prev); err != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
			fbMkt, fbCur := db.DetectMarketCurrency(ticker)
			price := avg
			stale := true
			if last.Valid && last.Float64 > 0 {
				price = last.Float64
				stale = false
			}
			mktS, curS := mkt.String, cur.String
			if !mkt.Valid || mktS == "" {
				mktS = fbMkt
			}
			if !cur.Valid || curS == "" {
				curS = fbCur
			}
			item := map[string]any{
				"id": id, "stock_id": stockID, "ticker": ticker,
				"name": name.String, "market": mktS, "currency": curS,
				"quantity": qty, "avg_purchase_price": avg,
				"current_price": price, "price_stale": stale,
				"previous_close": nil,
				"total_value":    round2(qty * price),
				"total_invested": round2(qty * avg),
				"purchase_date":  nil, "notes": "",
			}
			if name.String == "" {
				item["name"] = ticker
			}
			if prev.Valid && prev.Float64 > 0 {
				item["previous_close"] = prev.Float64
			}
			if purch.Valid {
				item["purchase_date"] = dateOnly(purch.String)
			}
			if notes.Valid {
				item["notes"] = notes.String
			}
			out = append(out, item)
		}
		writeJSON(w, http.StatusOK, out)
	}
}

// CreateHolding POST /api/portfolio/holdings — upsert con fusione media.
func CreateHolding(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		var req struct {
			Ticker       *string  `json:"ticker"`
			StockID      *int64   `json:"stock_id"`
			Quantity     *float64 `json:"quantity"`
			AvgPrice     *float64 `json:"avg_purchase_price"`
			PurchaseDate *string  `json:"purchase_date"`
			Notes        *string  `json:"notes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Body JSON non valido."})
			return
		}
		if req.Quantity == nil || *req.Quantity <= 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Quantità deve essere > 0."})
			return
		}
		if req.AvgPrice == nil || *req.AvgPrice <= 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Prezzo medio deve essere > 0."})
			return
		}
		lk := writelock.For(u.ID)
		lk.Lock()
		defer lk.Unlock()

		var stockID int64
		if req.StockID != nil {
			if err := wdb.QueryRow(`SELECT id FROM stocks WHERE id = ?`, *req.StockID).Scan(&stockID); err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{
					"detail": fmt.Sprintf("Stock id %d inesistente.", *req.StockID),
				})
				return
			}
		} else {
			ticker := ""
			if req.Ticker != nil {
				ticker = strings.TrimSpace(strings.ToUpper(*req.Ticker))
			}
			if ticker == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Specificare stock_id o ticker valido."})
				return
			}
			var err error
			if stockID, err = db.EnsureStock(wdb, ticker); err != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
		}

		purchDate := time.Now().UTC().Format("2006-01-02")
		if req.PurchaseDate != nil {
			if d, ok := parseDate(*req.PurchaseDate); ok {
				purchDate = d
			}
		}

		// Upsert sotto lock (max 3 tentativi su race DB).
		for attempt := 0; attempt < 3; attempt++ {
			var h holdingRow
			err := wdb.QueryRow(`SELECT `+holdingCols+` FROM holdings WHERE stock_id = ? AND user_id = ?`,
				stockID, u.ID).Scan(&h.ID, &h.Owner, &h.StockID, &h.Qty, &h.Avg,
				&h.PurchDate, &h.Notes, &h.Created, &h.Updated)
			if err == nil {
				totalQty := h.Qty + *req.Quantity
				newAvg := (h.Qty*h.Avg + *req.Quantity**req.AvgPrice) / totalQty
				notes := h.Notes.String
				if req.Notes != nil && *req.Notes != "" {
					notes = strings.Trim(strings.TrimSpace(notes+"; "+*req.Notes), "; ")
				}
				err = db.WithRetry(func() error {
					_, e := wdb.Exec(`UPDATE holdings SET quantity = ?, avg_purchase_price = ?, notes = ?,
						updated_at = ? WHERE id = ?`,
						round4(totalQty), round4(newAvg), notes, db.NowUTC(), h.ID)
					return e
				})
				if err != nil {
					if db.IsBusy(err) {
						writeJSON(w, http.StatusServiceUnavailable, map[string]string{
							"detail": "database temporaneamente occupato, riprova",
						})
						return
					}
					writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
					return
				}
				h.Qty, h.Avg = round4(totalQty), round4(newAvg)
				h.Notes = sql.NullString{String: notes, Valid: true}
				dashboard.InvalidateUser(u.ID)
				dashboard.InvalidateDailyCache(wdb)
				InvalidateAnalytics(u.ID)
				InvalidateAnalytics(u.ID)
				dashboard.InvalidateDailyCache(wdb)
				writeJSON(w, http.StatusOK, holdingMap(h))
				return
			}
			if err != sql.ErrNoRows {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
			var notes any
			if req.Notes != nil {
				notes = *req.Notes
			}
			var newID int64
			err = db.WithRetry(func() error {
				res, e := wdb.Exec(`INSERT INTO holdings(user_id, stock_id, quantity, avg_purchase_price,
					purchase_date, notes, created_at, updated_at)
					VALUES(?, ?, ?, ?, ?, ?, ?, ?)`,
					u.ID, stockID, *req.Quantity, *req.AvgPrice, purchDate, notes, db.NowUTC(), db.NowUTC())
				if e != nil {
					return e
				}
				newID, e = res.LastInsertId()
				return e
			})
			if err != nil {
				if db.IsConflict(err) {
					continue // race: rileggi e fondi al giro successivo
				}
				if db.IsBusy(err) {
					writeJSON(w, http.StatusServiceUnavailable, map[string]string{
						"detail": "database temporaneamente occupato, riprova",
					})
					return
				}
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
			dashboard.InvalidateUser(u.ID)
			dashboard.InvalidateDailyCache(wdb)
			InvalidateAnalytics(u.ID)
			var h2 holdingRow
			if e := wdb.QueryRow(`SELECT `+holdingCols+` FROM holdings WHERE id = ?`, newID).
				Scan(&h2.ID, &h2.Owner, &h2.StockID, &h2.Qty, &h2.Avg,
					&h2.PurchDate, &h2.Notes, &h2.Created, &h2.Updated); e != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
			writeJSON(w, http.StatusOK, holdingMap(h2))
			return
		}
		writeJSON(w, http.StatusConflict, map[string]string{
			"detail": "Conflitto concorrente sulla posizione, riprova.",
		})
	}
}

// UpdateHolding PUT /api/portfolio/holdings/{id} — update parziale.
func UpdateHolding(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || id <= 0 {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Holding non trovata"})
			return
		}
		var raw map[string]json.RawMessage
		if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Body JSON non valido."})
			return
		}
		lk := writelock.For(u.ID)
		lk.Lock()
		defer lk.Unlock()

		var h holdingRow
		err = wdb.QueryRow(`SELECT `+holdingCols+` FROM holdings WHERE id = ?`, id).
			Scan(&h.ID, &h.Owner, &h.StockID, &h.Qty, &h.Avg,
				&h.PurchDate, &h.Notes, &h.Created, &h.Updated)
		if err != nil || !canAccess(h.Owner, u) {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Holding non trovata"})
			return
		}
		sets, args := []string{}, []any{}
		if rawQty, ok := raw["quantity"]; ok {
			var q float64
			if json.Unmarshal(rawQty, &q) != nil || q <= 0 {
				writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Quantità deve essere > 0."})
				return
			}
			sets, args = append(sets, "quantity = ?"), append(args, q)
			h.Qty = q
		}
		if rawAvg, ok := raw["avg_purchase_price"]; ok {
			var a float64
			if json.Unmarshal(rawAvg, &a) != nil || a <= 0 {
				writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Prezzo medio deve essere > 0."})
				return
			}
			sets, args = append(sets, "avg_purchase_price = ?"), append(args, a)
			h.Avg = a
		}
		if rawDate, ok := raw["purchase_date"]; ok {
			var s *string
			_ = json.Unmarshal(rawDate, &s)
			if s != nil {
				if d, good := parseDate(*s); good {
					sets, args = append(sets, "purchase_date = ?"), append(args, d)
					h.PurchDate = sql.NullString{String: d, Valid: true}
				}
			}
		}
		if rawNotes, ok := raw["notes"]; ok {
			var s *string
			_ = json.Unmarshal(rawNotes, &s)
			if s == nil {
				sets = append(sets, "notes = NULL")
				h.Notes = sql.NullString{}
			} else {
				sets, args = append(sets, "notes = ?"), append(args, *s)
				h.Notes = sql.NullString{String: *s, Valid: true}
			}
		}
		if len(sets) == 0 {
			writeJSON(w, http.StatusOK, holdingMap(h))
			return
		}
		sets = append(sets, "updated_at = ?")
		args = append(args, db.NowUTC(), id)
		err = db.WithRetry(func() error {
			_, e := wdb.Exec(`UPDATE holdings SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...)
			return e
		})
		if err != nil {
			if db.IsBusy(err) {
				writeJSON(w, http.StatusServiceUnavailable, map[string]string{"detail": "database temporaneamente occupato, riprova"})
				return
			}
			if db.IsConflict(err) {
				writeJSON(w, http.StatusConflict, map[string]string{"detail": "Conflitto nell'aggiornamento della holding, riprova."})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		dashboard.InvalidateUser(u.ID)
		writeJSON(w, http.StatusOK, holdingMap(h))
	}
}

// DeleteHolding DELETE /api/portfolio/holdings/{id}.
func DeleteHolding(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || id <= 0 {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Holding non trovata"})
			return
		}
		lk := writelock.For(u.ID)
		lk.Lock()
		defer lk.Unlock()

		var owner sql.NullInt64
		if err := wdb.QueryRow(`SELECT user_id FROM holdings WHERE id = ?`, id).Scan(&owner); err != nil || !canAccess(owner, u) {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Holding non trovata"})
			return
		}
		if err := db.WithRetry(func() error {
			_, e := wdb.Exec(`DELETE FROM holdings WHERE id = ?`, id)
			return e
		}); err != nil {
			if db.IsBusy(err) {
				writeJSON(w, http.StatusServiceUnavailable, map[string]string{"detail": "database temporaneamente occupato, riprova"})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		effID := u.ID
		if owner.Valid {
			effID = owner.Int64
		}
		dashboard.InvalidateUser(effID)
		dashboard.InvalidateDailyCache(wdb)
		InvalidateAnalytics(effID)
		writeJSON(w, http.StatusOK, map[string]string{"status": "success", "message": "Holding rimossa"})
	}
}

// ---------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------

const txCols = `t.id, t.user_id, t.stock_id, s.ticker, s.name, s.market,
	t.type, t.quantity, t.price, t.fee, t.realized_pnl, t.currency,
	t.transaction_date, t.notes`

func txMap(scan func(...any) error) (map[string]any, error) {
	var id, stockID int64
	var owner sql.NullInt64
	var ticker sql.NullString
	var name, mkt, typ, cur, txDate, notes sql.NullString
	var qty, price, fee float64
	var rpnl sql.NullFloat64
	err := scan(&id, &owner, &stockID, &ticker, &name, &mkt,
		&typ, &qty, &price, &fee, &rpnl, &cur, &txDate, &notes)
	if err != nil {
		return nil, err
	}
	m := map[string]any{
		"id": id, "stock_id": stockID,
		"ticker": ticker.String, "name": name.String, "market": mkt.String,
		"type": typ.String, "quantity": qty, "price": price, "fee": fee,
		"realized_pnl": nil, "currency": cur.String,
		"transaction_date": txDate.String, "notes": "",
	}
	if mkt.String == "" {
		m["market"] = "US"
	}
	if name.String == "" {
		m["name"] = ""
	}
	if ticker.String == "" {
		m["ticker"] = "?"
	}
	if rpnl.Valid {
		m["realized_pnl"] = rpnl.Float64
	}
	if cur.String == "" {
		m["currency"] = "EUR"
	}
	if txDate.String == "" {
		m["transaction_date"] = ""
	}
	if notes.Valid {
		m["notes"] = notes.String
	}
	return m, nil
}

// ListTransactions GET /api/portfolio/transactions?type=&ticker=&limit=&skip=.
func ListTransactions(read, _ *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil {
			return
		}
		q := r.URL.Query()
		cond, args := []string{`t.user_id = ?`}, []any{u.ID}
		if t := strings.TrimSpace(strings.ToUpper(q.Get("type"))); t != "" {
			cond, args = append(cond, `t.type = ?`), append(args, t)
		}
		if t := strings.TrimSpace(strings.ToUpper(q.Get("ticker"))); t != "" {
			cond, args = append(cond, `s.ticker = ?`), append(args, t)
		}
		limit, skip := 100, 0
		if s := strings.TrimSpace(q.Get("limit")); s != "" {
			if n, err := strconv.Atoi(s); err == nil && n > 0 {
				limit = n
			}
		}
		if limit > 1000 {
			limit = 1000
		}
		if s := strings.TrimSpace(q.Get("skip")); s != "" {
			if n, err := strconv.Atoi(s); err == nil && n >= 0 {
				skip = n
			}
		}
		args = append(args, limit, skip)
		rows, err := read.Query(`
			SELECT `+txCols+`
			  FROM transactions t JOIN stocks s ON s.id = t.stock_id
			 WHERE `+strings.Join(cond, " AND ")+`
			 ORDER BY t.transaction_date DESC LIMIT ? OFFSET ?`, args...)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		defer rows.Close()
		out := []any{}
		for rows.Next() {
			m, err := txMap(rows.Scan)
			if err != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
			out = append(out, m)
		}
		writeJSON(w, http.StatusOK, out)
	}
}

// CreateTransaction POST /api/portfolio/transactions (BUY/SELL/DIVIDEND).
func CreateTransaction(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		var req struct {
			Ticker          *string  `json:"ticker"`
			Type            *string  `json:"type"`
			Quantity        *float64 `json:"quantity"`
			Price           *float64 `json:"price"`
			Fee             *float64 `json:"fee"`
			TransactionDate *string  `json:"transaction_date"`
			Notes           *string  `json:"notes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Body JSON non valido."})
			return
		}
		tType := "BUY"
		if req.Type != nil {
			tType = strings.TrimSpace(strings.ToUpper(*req.Type))
		}
		if tType != "BUY" && tType != "SELL" && tType != "DIVIDEND" {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"detail": "Il tipo transazione deve essere BUY, SELL o DIVIDEND.",
			})
			return
		}
		ticker := ""
		if req.Ticker != nil {
			ticker = strings.TrimSpace(strings.ToUpper(*req.Ticker))
		}
		if ticker == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Specificare un ticker valido."})
			return
		}
		qty, price, fee := 0.0, 0.0, 0.0
		if req.Quantity != nil {
			qty = *req.Quantity
		}
		if req.Price != nil {
			price = *req.Price
		}
		if req.Fee != nil {
			fee = *req.Fee
		}
		if qty < 0 || price < 0 || fee < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"detail": "Quantità, prezzo e commissioni devono essere >= 0.",
			})
			return
		}
		notes := ""
		if req.Notes != nil {
			notes = *req.Notes
		}
		txDate := db.NowUTC()
		if req.TransactionDate != nil {
			if d, ok := parseDateTime(*req.TransactionDate); ok {
				txDate = d
			}
		}

		lk := writelock.For(u.ID)
		lk.Lock()
		defer lk.Unlock()

		stockID, err := db.EnsureStock(wdb, ticker)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		var stockCur sql.NullString
		_ = wdb.QueryRow(`SELECT currency FROM stocks WHERE id = ?`, stockID).Scan(&stockCur)
		currency := stockCur.String
		if currency == "" {
			currency = "EUR"
		}

		var rpnl any
		switch tType {
		case "BUY":
			if qty <= 0 || price <= 0 {
				writeJSON(w, http.StatusBadRequest, map[string]string{
					"detail": "Quantità e prezzo devono essere maggiori di zero per un acquisto.",
				})
				return
			}
			var h holdingRow
			err := wdb.QueryRow(`SELECT `+holdingCols+` FROM holdings WHERE stock_id = ? AND user_id = ?`,
				stockID, u.ID).Scan(&h.ID, &h.Owner, &h.StockID, &h.Qty, &h.Avg,
				&h.PurchDate, &h.Notes, &h.Created, &h.Updated)
			if err != nil && err != sql.ErrNoRows {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
			if err == nil {
				newQty := h.Qty + qty
				newAvg := (h.Qty*h.Avg + qty*price) / newQty
				noteArg := any(h.Notes.String)
				if !h.Notes.Valid {
					noteArg = nil
				}
				if notes != "" {
					noteArg = notes
				}
				if e := db.WithRetry(func() error {
					_, e := wdb.Exec(`UPDATE holdings SET quantity = ?, avg_purchase_price = ?,
						notes = ?, updated_at = ? WHERE id = ?`,
						round4(newQty), round4(newAvg), noteArg, db.NowUTC(), h.ID)
					return e
				}); e != nil {
					writeBusyOr500(w, e, "Conflitto nella registrazione della transazione, riprova.")
					return
				}
			} else {
				pd := txDate
				if len(txDate) >= 10 {
					pd = txDate[:10]
				}
				if e := db.WithRetry(func() error {
					_, e := wdb.Exec(`INSERT INTO holdings(user_id, stock_id, quantity, avg_purchase_price,
						purchase_date, notes, created_at, updated_at)
						VALUES(?, ?, ?, ?, ?, ?, ?, ?)`,
						u.ID, stockID, qty, price, pd, notes, db.NowUTC(), db.NowUTC())
					return e
				}); e != nil {
					// Race: rileggi e fondi (stessa semantica dell'upsert).
					var h2 holdingRow
					if e2 := wdb.QueryRow(`SELECT `+holdingCols+` FROM holdings WHERE stock_id = ? AND user_id = ?`,
						stockID, u.ID).Scan(&h2.ID, &h2.Owner, &h2.StockID, &h2.Qty, &h2.Avg,
						&h2.PurchDate, &h2.Notes, &h2.Created, &h2.Updated); e2 == nil {
						newQty := h2.Qty + qty
						newAvg := (h2.Qty*h2.Avg + qty*price) / newQty
						if e3 := db.WithRetry(func() error {
							_, e := wdb.Exec(`UPDATE holdings SET quantity = ?, avg_purchase_price = ?,
								updated_at = ? WHERE id = ?`,
								round4(newQty), round4(newAvg), db.NowUTC(), h2.ID)
							return e
						}); e3 != nil {
							writeBusyOr500(w, e3, "Conflitto nella registrazione della transazione, riprova.")
							return
						}
					} else {
						writeBusyOr500(w, e, "Conflitto nella registrazione della transazione, riprova.")
						return
					}
				}
			}
			rpnl = 0.0
		case "SELL":
			if qty <= 0 || price <= 0 {
				writeJSON(w, http.StatusBadRequest, map[string]string{
					"detail": "Quantità e prezzo devono essere maggiori di zero per una vendita.",
				})
				return
			}
			var h holdingRow
			err := wdb.QueryRow(`SELECT `+holdingCols+` FROM holdings WHERE stock_id = ? AND user_id = ?`,
				stockID, u.ID).Scan(&h.ID, &h.Owner, &h.StockID, &h.Qty, &h.Avg,
				&h.PurchDate, &h.Notes, &h.Created, &h.Updated)
			if err != nil || h.Qty+1e-9 < qty {
				avail := 0.0
				if err == nil {
					avail = h.Qty
				}
				writeJSON(w, http.StatusConflict, map[string]string{
					"detail": fmt.Sprintf("Quantità insufficiente in portafoglio: possiedi %v quote di %s, impossibile venderne %v.", avail, ticker, qty),
				})
				return
			}
			rpnl = round2((price-h.Avg)*qty - fee)
			// Decremento atomico con guardia: rowcount 0 -> 409 (come il Python).
			var affected int64
			err = db.WithRetry(func() error {
				res, e := wdb.Exec(`UPDATE holdings SET quantity = quantity - ?, updated_at = ?
					WHERE id = ? AND user_id = ? AND quantity >= ?`,
					qty, db.NowUTC(), h.ID, u.ID, qty)
				if e != nil {
					return e
				}
				affected, e = res.RowsAffected()
				return e
			})
			if err != nil || affected != 1 {
				if err != nil && db.IsBusy(err) {
					writeJSON(w, http.StatusServiceUnavailable, map[string]string{
						"detail": "database temporaneamente occupato, riprova",
					})
					return
				}
				writeJSON(w, http.StatusConflict, map[string]string{
					"detail": "Quantità insufficiente in portafoglio per " + ticker + ": la posizione è cambiata durante la vendita, riprova.",
				})
				return
			}
			if h.Qty-qty <= 0.0001 {
				_ = db.WithRetry(func() error {
					_, e := wdb.Exec(`DELETE FROM holdings WHERE id = ? AND user_id = ?`, h.ID, u.ID)
					return e
				})
			}
		case "DIVIDEND":
			if price < 0 {
				writeJSON(w, http.StatusBadRequest, map[string]string{
					"detail": "L'importo del dividendo non può essere negativo.",
				})
				return
			}
			total := price
			if qty > 0 {
				total = price * qty
			}
			rpnl = round2(total - fee)
		}

		var txID int64
		err = db.WithRetry(func() error {
			res, e := wdb.Exec(`INSERT INTO transactions(user_id, stock_id, type, quantity, price, fee,
				realized_pnl, currency, transaction_date, notes, created_at)
				VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
				u.ID, stockID, tType, qty, price, fee, rpnl, currency, txDate, notes, db.NowUTC())
			if e != nil {
				return e
			}
			txID, e = res.LastInsertId()
			return e
		})
		if err != nil {
			writeBusyOr500(w, err, "Conflitto nella registrazione della transazione, riprova.")
			return
		}
		dashboard.InvalidateUser(u.ID)
		writeJSON(w, http.StatusOK, map[string]any{
			"status": "success",
			"transaction": map[string]any{
				"id": txID, "ticker": ticker, "type": tType,
				"quantity": qty, "price": price, "fee": fee,
				"realized_pnl": rpnl, "currency": currency,
				"transaction_date": txDate,
			},
		})
	}
}

// DeleteTransaction DELETE /api/portfolio/transactions/{id} + ricalcolo holding.
func DeleteTransaction(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || id <= 0 {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Transazione non trovata."})
			return
		}
		lk := writelock.For(u.ID)
		lk.Lock()
		defer lk.Unlock()

		var owner sql.NullInt64
		var stockID int64
		err = wdb.QueryRow(`SELECT user_id, stock_id FROM transactions WHERE id = ?`, id).
			Scan(&owner, &stockID)
		if err != nil || !canAccess(owner, u) {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Transazione non trovata."})
			return
		}
		effOwner := u.ID
		if owner.Valid {
			effOwner = owner.Int64
		}
		if err := db.WithRetry(func() error {
			_, e := wdb.Exec(`DELETE FROM transactions WHERE id = ?`, id)
			return e
		}); err != nil {
			writeBusyOr500(w, err, "Conflitto nel ricalcolo della posizione, riprova.")
			return
		}
		// Ricalcolo dai movimenti residui (media ponderata di TUTTI i BUY).
		rows, err := wdb.Query(`SELECT type, quantity, price, transaction_date FROM transactions
			WHERE user_id = ? AND stock_id = ? AND type IN ('BUY','SELL')
			ORDER BY transaction_date, id`, effOwner, stockID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		buyQty, sellQty, buyCost := 0.0, 0.0, 0.0
		var firstBuyDate sql.NullString
		for rows.Next() {
			var typ string
			var q, p float64
			var dt sql.NullString
			if e := rows.Scan(&typ, &q, &p, &dt); e != nil {
				rows.Close()
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
			if typ == "BUY" {
				buyQty += q
				buyCost += q * p
				if !firstBuyDate.Valid && dt.Valid {
					firstBuyDate = dt
				}
			} else {
				sellQty += q
			}
		}
		rows.Close()
		totalQty := buyQty - sellQty
		var newAvg *float64
		if buyQty > 0 {
			a := round4(buyCost / buyQty)
			newAvg = &a
		}
		var holdID int64
		err = wdb.QueryRow(`SELECT id FROM holdings WHERE user_id = ? AND stock_id = ?`,
			effOwner, stockID).Scan(&holdID)
		if totalQty <= 0.0001 {
			if err == nil {
				_ = db.WithRetry(func() error {
					_, e := wdb.Exec(`DELETE FROM holdings WHERE id = ?`, holdID)
					return e
				})
			}
		} else if err == nil {
			if newAvg != nil {
				_ = db.WithRetry(func() error {
					_, e := wdb.Exec(`UPDATE holdings SET quantity = ?, avg_purchase_price = ?,
						updated_at = ? WHERE id = ?`, round4(totalQty), *newAvg, db.NowUTC(), holdID)
					return e
				})
			} else {
				_ = db.WithRetry(func() error {
					_, e := wdb.Exec(`UPDATE holdings SET quantity = ?, updated_at = ? WHERE id = ?`,
						round4(totalQty), db.NowUTC(), holdID)
					return e
				})
			}
		} else {
			pd := time.Now().UTC().Format("2006-01-02")
			if firstBuyDate.Valid && len(firstBuyDate.String) >= 10 {
				pd = firstBuyDate.String[:10]
			}
			avg := 0.0
			if newAvg != nil {
				avg = *newAvg
			}
			_ = db.WithRetry(func() error {
				_, e := wdb.Exec(`INSERT INTO holdings(user_id, stock_id, quantity, avg_purchase_price,
					purchase_date, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?)`,
					effOwner, stockID, round4(totalQty), avg, pd, db.NowUTC(), db.NowUTC())
				return e
			})
		}
		dashboard.InvalidateUser(effOwner)
		dashboard.InvalidateDailyCache(wdb)
		InvalidateAnalytics(effOwner)
		writeJSON(w, http.StatusOK, map[string]string{
			"status": "success", "message": fmt.Sprintf("Transazione #%d rimossa.", id),
		})
	}
}

func writeBusyOr500(w http.ResponseWriter, err error, conflictDetail string) {
	if db.IsBusy(err) {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"detail": "database temporaneamente occupato, riprova",
		})
		return
	}
	if db.IsConflict(err) {
		writeJSON(w, http.StatusConflict, map[string]string{"detail": conflictDetail})
		return
	}
	writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
}
