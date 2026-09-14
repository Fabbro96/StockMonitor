// Scritture watchlist Fase-2 (backend/routers/watchlist.py):
// POST /api/watchlist/, PUT /{id}/alert, DELETE /{id},
// DELETE /ticker/{ticker}. Stessi campi del Python; status creation/
// duplicato secondo specifica Fase-2 (201 nuovo, 409 duplicato).

package watchlist

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"stockmon/internal/auth"
	"stockmon/internal/dashboard"
	"stockmon/internal/db"
	"stockmon/internal/writelock"
)

// Invalidate elimina la entry di cache GET dell'utente.
func Invalidate(userID int64) {
	mu.Lock()
	defer mu.Unlock()
	delete(cache, "watch:"+strconv.FormatInt(userID, 10))
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

// canAccess mirror di _can_access_watchlist_item: righe legacy user_id NULL
// solo admin, altrimenti solo proprietario.
func canAccess(userID sql.NullInt64, u *auth.User) bool {
	if !userID.Valid {
		return u.IsAdmin
	}
	return userID.Int64 == u.ID
}

// Create POST /api/watchlist/ — 201 nuovo, 409 se già presente.
func Create(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		var req struct {
			Ticker     string   `json:"ticker"`
			Notes      *string  `json:"notes"`
			AlertAbove *float64 `json:"alert_above"`
			AlertBelow *float64 `json:"alert_below"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Body JSON non valido."})
			return
		}
		ticker := strings.TrimSpace(strings.ToUpper(req.Ticker))
		if ticker == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Ticker non valido."})
			return
		}
		lk := writelock.For(u.ID)
		lk.Lock()
		defer lk.Unlock()

		stockID, err := db.EnsureStock(wdb, ticker)
		if err != nil {
			if db.IsConflict(err) {
				writeJSON(w, http.StatusConflict, map[string]string{
					"detail": "Conflitto concorrente sulla creazione di " + ticker + ".",
				})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
			return
		}
		var existingID int64
		err = wdb.QueryRow(
			`SELECT id FROM watchlist_items WHERE stock_id = ? AND user_id = ?`,
			stockID, u.ID).Scan(&existingID)
		if err == nil {
			// Già presente: aggiorna i campi forniti (come il Python "exists").
			sets, args := []string{}, []any{}
			if req.Notes != nil {
				sets, args = append(sets, "notes = ?"), append(args, *req.Notes)
			}
			if req.AlertAbove != nil {
				sets, args = append(sets, "alert_above = ?"), append(args, *req.AlertAbove)
			}
			if req.AlertBelow != nil {
				sets, args = append(sets, "alert_below = ?"), append(args, *req.AlertBelow)
			}
			if len(sets) > 0 {
				args = append(args, existingID)
				if e := db.WithRetry(func() error {
					_, e := wdb.Exec(`UPDATE watchlist_items SET `+strings.Join(sets, ", ")+` WHERE id = ?`, args...)
					return e
				}); e != nil {
					writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore interno."})
					return
				}
			}
			Invalidate(u.ID)
			writeJSON(w, http.StatusConflict, map[string]string{
				"detail": ticker + " è già nella Watchlist.",
			})
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
		var above, below any
		if req.AlertAbove != nil {
			above = *req.AlertAbove
		}
		if req.AlertBelow != nil {
			below = *req.AlertBelow
		}
		var newID int64
		err = db.WithRetry(func() error {
			// alert_triggered è NOT NULL senza server_default (default solo
			// lato Python): va valorizzato esplicitamente.
			res, e := wdb.Exec(
				`INSERT INTO watchlist_items(user_id, stock_id, notes, alert_above, alert_below, alert_triggered, added_at)
				 VALUES(?, ?, ?, ?, ?, 0, ?)`, u.ID, stockID, notes, above, below, db.NowUTC())
			if e != nil {
				return e
			}
			newID, e = res.LastInsertId()
			return e
		})
		if err != nil {
			if db.IsConflict(err) {
				writeJSON(w, http.StatusConflict, map[string]string{
					"detail": ticker + " è già nella Watchlist.",
				})
				return
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
		Invalidate(u.ID)
		dashboard.InvalidateUser(u.ID)
		writeJSON(w, http.StatusCreated, map[string]any{
			"status": "success", "message": ticker + " aggiunto alla Watchlist", "id": newID,
		})
	}
}

// UpdateAlert PUT /api/watchlist/{id}/alert.
func UpdateAlert(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || id <= 0 {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Elemento Watchlist non trovato."})
			return
		}
		var req struct {
			AlertAbove *float64 `json:"alert_above"`
			AlertBelow *float64 `json:"alert_below"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"detail": "Body JSON non valido."})
			return
		}
		var owner sql.NullInt64
		err = wdb.QueryRow(`SELECT user_id FROM watchlist_items WHERE id = ?`, id).Scan(&owner)
		if err != nil || !canAccess(owner, u) {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Elemento Watchlist non trovato."})
			return
		}
		var above, below any
		if req.AlertAbove != nil {
			above = *req.AlertAbove
		}
		if req.AlertBelow != nil {
			below = *req.AlertBelow
		}
		err = db.WithRetry(func() error {
			_, e := wdb.Exec(`UPDATE watchlist_items SET alert_above = ?, alert_below = ? WHERE id = ?`,
				above, below, id)
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
		effID := u.ID
		if owner.Valid {
			effID = owner.Int64
		}
		Invalidate(effID)
		dashboard.InvalidateUser(effID)
		writeJSON(w, http.StatusOK, map[string]string{
			"status": "success", "message": "Alert aggiornato con successo",
		})
	}
}

// Delete DELETE /api/watchlist/{id}.
func Delete(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || id <= 0 {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Elemento Watchlist non trovato."})
			return
		}
		var owner sql.NullInt64
		err = wdb.QueryRow(`SELECT user_id FROM watchlist_items WHERE id = ?`, id).Scan(&owner)
		if err != nil || !canAccess(owner, u) {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Elemento Watchlist non trovato."})
			return
		}
		err = db.WithRetry(func() error {
			_, e := wdb.Exec(`DELETE FROM watchlist_items WHERE id = ?`, id)
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
		effID := u.ID
		if owner.Valid {
			effID = owner.Int64
		}
		Invalidate(effID)
		dashboard.InvalidateUser(effID)
		writeJSON(w, http.StatusOK, map[string]string{
			"status": "success", "message": "Rimosso dalla Watchlist",
		})
	}
}

// DeleteByTicker DELETE /api/watchlist/ticker/{ticker} — 404 se titolo ignoto.
func DeleteByTicker(read, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		u := userOr401(w, r)
		if u == nil || !needWriter(w, wdb) {
			return
		}
		ticker := strings.TrimSpace(strings.ToUpper(r.PathValue("ticker")))
		var stockID int64
		if err := wdb.QueryRow(`SELECT id FROM stocks WHERE ticker = ?`, ticker).Scan(&stockID); err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"detail": "Titolo non trovato."})
			return
		}
		err := db.WithRetry(func() error {
			_, e := wdb.Exec(`DELETE FROM watchlist_items WHERE stock_id = ? AND user_id = ?`,
				stockID, u.ID)
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
		Invalidate(u.ID)
		dashboard.InvalidateUser(u.ID)
		writeJSON(w, http.StatusOK, map[string]string{
			"status": "success", "message": ticker + " rimosso dalla Watchlist",
		})
	}
}
