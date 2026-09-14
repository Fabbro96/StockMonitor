// Package auth replica il contratto di backend/routers/auth.py +
// backend/services/auth.py in sola lettura (Fase-1):
//
//   - POST /api/auth/login  {username, password} ->
//     {access_token, token_type, username, is_admin} (snake_case)
//   - GET  /api/auth/me     -> {id, username, is_admin, is_active,
//     created_at, last_login} (snake_case)
//
// JWT HS256 con claims sub/exp (+iat), SECRET_KEY dallo stesso env del
// backend Python, verifica bcrypt via golang.org/x/crypto.
//
// NOTA Fase-1 read-only: failed_attempts/locked_until/last_login NON
// vengono aggiornati (nessuna scrittura); il lockout per troppi tentativi
// è quindi applicato solo dal backend Python.
package auth

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

const defaultSecret = "stock-monitor-super-secret-key-change-in-env-2026"

// User riflette la tabella users (solo campi esposti da UserResponse).
type User struct {
	ID        int64   `json:"id"`
	Username  string  `json:"username"`
	IsAdmin   bool    `json:"is_admin"`
	IsActive  bool    `json:"is_active"`
	CreatedAt *string `json:"created_at"`
	LastLogin *string `json:"last_login"`
}

type ctxKey struct{}

// SecretKey riusa lo stesso env del backend Python (backend/config.py).
func SecretKey() string {
	if s := strings.TrimSpace(os.Getenv("SECRET_KEY")); s != "" {
		return s
	}
	return defaultSecret
}

// ExpireDays allineato a settings.ACCESS_TOKEN_EXPIRE_DAYS (default 7).
func ExpireDays() int {
	if s := strings.TrimSpace(os.Getenv("ACCESS_TOKEN_EXPIRE_DAYS")); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 {
			return n
		}
	}
	return 7
}

func boolOf(v any) bool {
	switch t := v.(type) {
	case bool:
		return t
	case int64:
		return t != 0
	case int:
		return t != 0
	case []byte:
		s := string(t)
		return s == "1" || strings.EqualFold(s, "true")
	case string:
		return t == "1" || strings.EqualFold(t, "true")
	}
	return false
}

func nullString(ns sql.NullString) *string {
	if !ns.Valid {
		return nil
	}
	s := ns.String
	return &s
}

// FindByUsername cerca l'utente per username esatto (dopo TrimSpace).
func FindByUsername(db *sql.DB, username string) (*User, string, error) {
	username = strings.TrimSpace(username)
	var u User
	var hashed string
	var created, lastLogin sql.NullString
	var isAdmin, isActive any
	err := db.QueryRow(
		`SELECT id, username, hashed_password, is_admin, is_active, created_at, last_login
		 FROM users WHERE username = ?`, username,
	).Scan(&u.ID, &u.Username, &hashed, &isAdmin, &isActive, &created, &lastLogin)
	if err != nil {
		return nil, "", err
	}
	u.IsAdmin = boolOf(isAdmin)
	u.IsActive = boolOf(isActive)
	u.CreatedAt = nullString(created)
	u.LastLogin = nullString(lastLogin)
	return &u, hashed, nil
}

// CreateToken firma un JWT HS256 con claims sub/exp/iat.
func CreateToken(username string) (string, error) {
	now := time.Now().UTC()
	claims := jwt.MapClaims{
		"sub": username,
		"exp": now.Add(time.Duration(ExpireDays()) * 24 * time.Hour).Unix(),
		"iat": now.Unix(),
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return tok.SignedString([]byte(SecretKey()))
}

// BearerOrCookie estrae il token come backend/services/auth.py:
// 1. header Authorization: Bearer <token>, 2. fallback cookie access_token.
func BearerOrCookie(r *http.Request) string {
	if h := r.Header.Get("Authorization"); h != "" {
		parts := strings.SplitN(h, " ", 2)
		if len(parts) == 2 && strings.EqualFold(parts[0], "bearer") {
			if t := strings.TrimSpace(parts[1]); t != "" {
				return t
			}
		}
	}
	if c, err := r.Cookie("access_token"); err == nil {
		return strings.TrimSpace(c.Value)
	}
	return ""
}

// Authenticate valida il token e ricarica l'utente dal DB.
func Authenticate(db *sql.DB, token string) (*User, error) {
	parsed, err := jwt.Parse(token, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte(SecretKey()), nil
	})
	if err != nil || !parsed.Valid {
		return nil, jwt.ErrSignatureInvalid
	}
	claims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok {
		return nil, jwt.ErrInvalidKey
	}
	sub, _ := claims["sub"].(string)
	if strings.TrimSpace(sub) == "" {
		return nil, jwt.ErrInvalidKey
	}
	u, _, err := FindByUsername(db, sub)
	if err != nil {
		return nil, err
	}
	if !u.IsActive {
		return nil, sql.ErrNoRows
	}
	return u, nil
}

// FromContext restituisce l'utente autenticato dal middleware.
func FromContext(ctx context.Context) *User {
	u, _ := ctx.Value(ctxKey{}).(*User)
	return u
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeDetail(w http.ResponseWriter, status int, detail string) {
	writeJSON(w, status, map[string]string{"detail": detail})
}

// LoginHandler implementa POST /api/auth/login.
func LoginHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeDetail(w, http.StatusMethodNotAllowed, "Metodo non consentito.")
			return
		}
		var req struct {
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeDetail(w, http.StatusBadRequest, "Body JSON non valido.")
			return
		}
		username := strings.TrimSpace(req.Username)
		if username == "" || req.Password == "" {
			writeDetail(w, http.StatusUnauthorized, "Credenziali non corrette.")
			return
		}
		u, hashed, err := FindByUsername(db, username)
		if err != nil {
			// Stesso messaggio del Python per utenti inesistenti (no enumeration).
			writeDetail(w, http.StatusUnauthorized, "Credenziali non corrette.")
			return
		}
		if !u.IsActive {
			writeDetail(w, http.StatusForbidden, "Questo account è stato disabilitato dall'amministratore.")
			return
		}
		if err := bcrypt.CompareHashAndPassword([]byte(hashed), []byte(req.Password)); err != nil {
			writeDetail(w, http.StatusUnauthorized, "Credenziali non corrette.")
			return
		}
		token, err := CreateToken(u.Username)
		if err != nil {
			writeDetail(w, http.StatusInternalServerError, "Errore interno.")
			return
		}
		http.SetCookie(w, &http.Cookie{
			Name:     "access_token",
			Value:    token,
			Path:     "/",
			HttpOnly: true,
			MaxAge:   7 * 24 * 3600,
			SameSite: http.SameSiteLaxMode,
		})
		writeJSON(w, http.StatusOK, map[string]any{
			"access_token": token,
			"token_type":   "bearer",
			"username":     u.Username,
			"is_admin":     u.IsAdmin,
		})
	}
}

// MeHandler implementa GET /api/auth/me (pack perf: Cache-Control private
// 60s + ETag sul token — copre sub+exp senza cambiare shape JWT — così
// web/app evitano roundtrip con If-None-Match → 304).
func MeHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeDetail(w, http.StatusMethodNotAllowed, "Metodo non consentito.")
			return
		}
		token := BearerOrCookie(r)
		if token == "" {
			writeDetail(w, http.StatusUnauthorized, "Sessione non valida o scaduta. Effettua il login.")
			return
		}
		u, err := Authenticate(db, token)
		if err != nil {
			writeDetail(w, http.StatusUnauthorized, "Token di autenticazione non valido.")
			return
		}
		// ETag DOPO l'autenticazione: un token scaduto/revocato deve dare
		// 401, mai 304.
		sum := sha256.Sum256([]byte(token))
		etag := `"` + hex.EncodeToString(sum[:]) + `"`
		if r.Header.Get("If-None-Match") == etag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		body, err := json.Marshal(u)
		if err != nil {
			writeDetail(w, http.StatusInternalServerError, "Errore interno.")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "private, max-age=60")
		w.Header().Set("ETag", etag)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	}
}

// Middleware protegge le route /api/* (tranne login): 401 senza token valido.
// Forma dei messaggi allineata a backend/services/auth.py.
func Middleware(db *sql.DB, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := BearerOrCookie(r)
		if token == "" {
			writeDetail(w, http.StatusUnauthorized, "Sessione non valida o scaduta. Effettua il login.")
			return
		}
		u, err := Authenticate(db, token)
		if err != nil {
			writeDetail(w, http.StatusUnauthorized, "Token di autenticazione non valido.")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, u)))
	})
}
