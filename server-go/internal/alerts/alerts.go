// Package alerts implementa il CRUD Fase-2 di
// backend/routers/settings.py (path reale /api/settings/alerts):
// GET+POST /alerts, PUT+DELETE /alerts/{id} (il PUT è un'estensione
// Fase-2: il Python espone solo GET/POST/DELETE).
package alerts

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"stockmon/internal/auth"
	"stockmon/internal/dashboard"
	"stockmon/internal/db"
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

func canAccess(owner sql.NullInt64, u *auth.User) bool {
	if !owner.Valid {
		return u.IsAdmin
	}
	return owner.Int64 == u.ID
}

type ruleRow struct {
	ID        int64
	Owner     sql.NullInt64
	StockID   int64
	Ticker    sql.NullString
	Name      sql.NullString
	Direction sql.NullString
	Threshold sql.NullFloat64
	Active    any
}

func boolOf(v any) bool {
	switch t := v.(type) {
	case bool:
		return t
	case int64:
		return t != 0
	case []byte:
		s := string(t)
		return s == "1" || strings.EqualFold(s, "true")
	case string:
		return t == "1" || strings.EqualFold(t, "true")
	}
	return false
}

func ruleMap(rr ruleRow) map[string]any {
	thr := 0.0
	if rr.Threshold.Valid {
		thr = rr.Threshold.Float64
	}
	return map[string]any{
		"id": rr.ID, "stock_id": rr.StockID,
		"ticker": rr.Ticker.String, "name": rr.Name.String,
		"direction":         rr.Direction.String,
		"threshold":         thr,
		"threshold_percent": thr,
		"active":            boolOf(rr.Active),
	}
}

const ruleCols = `ar.id, ar.user_id, ar.stock_id, s.ticker, s.name,
	ar.direction, ar.threshold_percent, ar.is_active`

const ruleFrom = `FROM alert_rules ar JOIN stocks s ON s.id = ar.stock_id`

// List GET /api/settings/alerts.
func List(read, _ *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil {
			return
		}
		rows, err := read.Query(`SELECT `+ruleCols+` `+ruleFrom+` WHERE ar.user_id = ?`, u.ID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		defer rows.Close()
		out := []any{}
		for rows.Next() {
			var rr ruleRow
			if err := rows.Scan(&rr.ID, &rr.Owner, &rr.StockID, &rr.Ticker, &rr.Name,
				&rr.Direction, &rr.Threshold, &rr.Active); err != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
			out = append(out, ruleMap(rr))
		}
		writeJSON(w, http.StatusOK, out)
	}
}

func validDirection(s string) (string, bool) {
	d := strings.TrimSpace(strings.ToUpper(s))
	if d == "" {
		return "BOTH", true
	}
	if d == "UP" || d == "DOWN" || d == "BOTH" {
		return d, true
	}
	return "", false
}

// Create POST /api/settings/alerts — accetta stock_id|ticker e
// threshold_percent|threshold (come il Python).
func Create(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		var req struct {
			StockID          *int64   `json:"stock_id"`
			Ticker           *string  `json:"ticker"`
			ThresholdPercent *float64 `json:"threshold_percent"`
			Threshold        *float64 `json:"threshold"`
			Direction        *string  `json:"direction"`
			Active           *bool    `json:"active"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Body JSON non valido."})
			return
		}
		thr := req.ThresholdPercent
		if thr == nil {
			thr = req.Threshold
		}
		if thr == nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"detail": "Specifica threshold_percent o threshold.",
			})
			return
		}
		if *thr <= 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"detail": "La soglia deve essere positiva.",
			})
			return
		}
		dir := "BOTH"
		if req.Direction != nil {
			var ok bool
			if dir, ok = validDirection(*req.Direction); !ok {
				writeJSON(w, http.StatusBadRequest, map[string]string{
					"detail": "direction deve essere UP, DOWN o BOTH.",
				})
				return
			}
		}
		var stockID int64
		if req.StockID != nil {
			if err := wdb.QueryRow(`SELECT id FROM stocks WHERE id = ?`, *req.StockID).Scan(&stockID); err != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{
					"detail": "Stock id inesistente.",
				})
				return
			}
		} else {
			ticker := ""
			if req.Ticker != nil {
				ticker = strings.TrimSpace(strings.ToUpper(*req.Ticker))
			}
			if ticker == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{
					"detail": "Specifica stock_id oppure ticker.",
				})
				return
			}
			var err error
			if stockID, err = db.EnsureStock(wdb, ticker); err != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
		}
		active := true
		if req.Active != nil {
			active = *req.Active
		}
		activeInt := 0
		if active {
			activeInt = 1
		}
		var newID int64
		err := db.WithRetry(func() error {
			res, e := wdb.Exec(`INSERT INTO alert_rules(user_id, stock_id, threshold_percent,
				direction, is_active, created_at) VALUES(?, ?, ?, ?, ?, ?)`,
				u.ID, stockID, *thr, dir, activeInt, db.NowUTC())
			if e != nil {
				return e
			}
			newID, e = res.LastInsertId()
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
		var rr ruleRow
		if err := wdb.QueryRow(`SELECT `+ruleCols+` `+ruleFrom+` WHERE ar.id = ?`, newID).
			Scan(&rr.ID, &rr.Owner, &rr.StockID, &rr.Ticker, &rr.Name,
				&rr.Direction, &rr.Threshold, &rr.Active); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		dashboard.InvalidateUser(u.ID)
		writeJSON(w, http.StatusOK, ruleMap(rr))
	}
}

// Update PUT /api/settings/alerts/{id} — update parziale (estensione Fase-2).
func Update(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || id <= 0 {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Alert rule not found"})
			return
		}
		var raw map[string]json.RawMessage
		if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Body JSON non valido."})
			return
		}
		var owner sql.NullInt64
		if err := wdb.QueryRow(`SELECT user_id FROM alert_rules WHERE id = ?`, id).Scan(&owner); err != nil || !canAccess(owner, u) {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Alert rule not found"})
			return
		}
		sets, args := []string{}, []any{}
		if rawThr, ok := raw["threshold_percent"]; ok {
			if _, has := raw["threshold"]; !has {
				var t float64
				if json.Unmarshal(rawThr, &t) != nil || t <= 0 {
					writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "La soglia deve essere positiva."})
					return
				}
				sets, args = append(sets, "threshold_percent = ?"), append(args, t)
			}
		}
		if rawThr, ok := raw["threshold"]; ok {
			var t float64
			if json.Unmarshal(rawThr, &t) != nil || t <= 0 {
				writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "La soglia deve essere positiva."})
				return
			}
			sets, args = append(sets, "threshold_percent = ?"), append(args, t)
		}
		if rawDir, ok := raw["direction"]; ok {
			var s string
			if json.Unmarshal(rawDir, &s) != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "direction deve essere UP, DOWN o BOTH."})
				return
			}
			dir, valid := validDirection(s)
			if !valid {
				writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "direction deve essere UP, DOWN o BOTH."})
				return
			}
			sets, args = append(sets, "direction = ?"), append(args, dir)
		}
		if rawAct, ok := raw["active"]; ok {
			var b bool
			if json.Unmarshal(rawAct, &b) != nil {
				writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Body JSON non valido."})
				return
			}
			ai := 0
			if b {
				ai = 1
			}
			sets, args = append(sets, "is_active = ?"), append(args, ai)
		}
		if len(sets) > 0 {
			args = append(args, id)
			if err := db.WithRetry(func() error {
				_, e := wdb.Exec(`UPDATE alert_rules SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...)
				return e
			}); err != nil {
				if db.IsBusy(err) {
					writeJSON(w, http.StatusServiceUnavailable, map[string]string{
						"detail": "database temporaneamente occupato, riprova",
					})
					return
				}
				writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
				return
			}
		}
		var rr ruleRow
		if err := wdb.QueryRow(`SELECT `+ruleCols+` `+ruleFrom+` WHERE ar.id = ?`, id).
			Scan(&rr.ID, &rr.Owner, &rr.StockID, &rr.Ticker, &rr.Name,
				&rr.Direction, &rr.Threshold, &rr.Active); err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Alert rule not found"})
			return
		}
		effID := u.ID
		if owner.Valid {
			effID = owner.Int64
		}
		dashboard.InvalidateUser(effID)
		writeJSON(w, http.StatusOK, ruleMap(rr))
	}
}

// Delete DELETE /api/settings/alerts/{id}.
func Delete(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || id <= 0 {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Alert rule not found"})
			return
		}
		var owner sql.NullInt64
		if err := wdb.QueryRow(`SELECT user_id FROM alert_rules WHERE id = ?`, id).Scan(&owner); err != nil || !canAccess(owner, u) {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Alert rule not found"})
			return
		}
		if err := db.WithRetry(func() error {
			_, e := wdb.Exec(`DELETE FROM alert_rules WHERE id = ?`, id)
			return e
		}); err != nil {
			if db.IsBusy(err) {
				writeJSON(w, http.StatusServiceUnavailable, map[string]string{
					"detail": "database temporaneamente occupato, riprova",
				})
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
		writeJSON(w, http.StatusOK, map[string]string{"status": "success"})
	}
}
