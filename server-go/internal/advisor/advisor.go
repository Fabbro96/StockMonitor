// Package advisor implementa generazione consigli via Gemini 3.8 Flash
// (REST API, niente SDK Python) e storage in advices table.
package advisor

import (
	"bytes"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/fernet/fernet-go"
	"stockmon/internal/auth"
	"stockmon/internal/db"
)

const geminiURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent"
const geminiTimeout = 30 * time.Second

var (
	keyMu       sync.Mutex
	keyCache    string
	keyCacheTS  time.Time
	keyCacheDur = 5 * time.Minute
)

type geminiRequest struct {
	Contents        []geminiContent   `json:"contents"`
	GenerationConfig *geminiGenConfig `json:"generationConfig,omitempty"`
}
type geminiContent struct {
	Parts []geminiPart `json:"parts"`
}
type geminiPart struct {
	Text string `json:"text"`
}
type geminiGenConfig struct {
	ResponseMimeType string  `json:"responseMimeType,omitempty"`
	MaxOutputTokens  int     `json:"maxOutputTokens,omitempty"`
	Temperature      *float64 `json:"temperature,omitempty"`
}
type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
		FinishReason string `json:"finishReason"`
	} `json:"candidates"`
	PromptFeedback *struct {
		BlockReason string `json:"blockReason"`
	} `json:"promptFeedback"`
	Error *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
		Status  string `json:"status"`
	} `json:"error"`
}

type AdviceData struct {
	Title             string       `json:"title"`
	Action            string       `json:"action"`
	Overview          string       `json:"overview"`
	Reasoning         string       `json:"reasoning"`
	Risks             string       `json:"risks"`
	Confidence        string       `json:"confidence"`
	Timeframe         string       `json:"timeframe"`
	TargetPrice       *float64     `json:"target_price,omitempty"`
	SuggestedQuantity *int64       `json:"suggested_quantity,omitempty"`
	Stocks            []AdviceStock `json:"stocks,omitempty"`
}
type AdviceStock struct {
	Ticker string   `json:"ticker"`
	Name   string   `json:"name"`
	Action string   `json:"action"`
	Target *float64 `json:"target,omitempty"`
}

// resolveAPIKey cerca la chiave Gemini in DB (cifrata Fernet) poi env.
func resolveAPIKey(rdb *sql.DB) string {
	keyMu.Lock()
	if keyCache != "" && time.Since(keyCacheTS) < keyCacheDur {
		defer keyMu.Unlock()
		return keyCache
	}
	keyMu.Unlock()

	var enc sql.NullString
	_ = rdb.QueryRow(`SELECT gemini_api_key_encrypted FROM user_settings LIMIT 1`).Scan(&enc)
	if enc.Valid && strings.TrimSpace(enc.String) != "" {
		if key, err := decryptFernet(enc.String); err == nil && key != "" {
			keyMu.Lock()
			keyCache = key
			keyCacheTS = time.Now()
			keyMu.Unlock()
			return key
		} else {
			log.Printf("advisor: decrypt key fallito: %v", err)
		}
	}

	key := strings.TrimSpace(os.Getenv("GEMINI_API_KEY"))
	if key != "" {
		keyMu.Lock()
		keyCache = key
		keyCacheTS = time.Now()
		keyMu.Unlock()
	}
	return key
}

// InvalidateKeyCache forza rilettura prossima chiamata.
func InvalidateKeyCache() {
	keyMu.Lock()
	keyCache = ""
	keyMu.Unlock()
}

// decryptFernet decodifica un Fernet token Python con chiave derivata da SECRET_KEY.
func decryptFernet(token string) (string, error) {
	secretKey := strings.TrimSpace(os.Getenv("SECRET_KEY"))
	if secretKey == "" {
		return "", fmt.Errorf("SECRET_KEY non impostata")
	}
	// Python: fernet_key = base64.urlsafe_b64encode(sha256(secret.encode())[:32])
	keyHash := sha256.Sum256([]byte(secretKey))
	var keyArr [32]byte
	copy(keyArr[:], keyHash[:])
	key := fernet.Key(keyArr)
	// TTL=0: nessuna scadenza (come Python default)
	msg := fernet.VerifyAndDecrypt([]byte(token), 0, []*fernet.Key{&key})
	if msg == nil {
		return "", fmt.Errorf("fernet: decrypt fallito (chiave non valida o token corrotto)")
	}
	return string(msg), nil
}

func callGemini(prompt, apiKey string) (string, error) {
	body, _ := json.Marshal(geminiRequest{
		Contents: []geminiContent{{Parts: []geminiPart{{Text: prompt}}}},
		GenerationConfig: &geminiGenConfig{
			ResponseMimeType: "application/json",
			MaxOutputTokens:  2048,
		},
	})
	url := geminiURL + "?key=" + apiKey
	client := &http.Client{Timeout: geminiTimeout}
	resp, err := client.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("gemini request: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == 400 || resp.StatusCode == 401 || resp.StatusCode == 403 {
		return "", fmt.Errorf("gemini %d: chiave non valida o modello non disponibile", resp.StatusCode)
	}
	if resp.StatusCode == 404 {
		return "", fmt.Errorf("gemini: modello non trovato (verifica GEMINI_MODEL)")
	}
	if resp.StatusCode == 429 || resp.StatusCode >= 500 {
		return "", fmt.Errorf("gemini %d: transient, riprova", resp.StatusCode)
	}
	var gr geminiResponse
	if err := json.Unmarshal(respBody, &gr); err != nil {
		return "", fmt.Errorf("gemini parse: %w", err)
	}
	if gr.Error != nil {
		return "", fmt.Errorf("gemini error %d: %s", gr.Error.Code, gr.Error.Message)
	}
	if gr.PromptFeedback != nil && gr.PromptFeedback.BlockReason != "" {
		return "", fmt.Errorf("gemini bloccato: %s", gr.PromptFeedback.BlockReason)
	}
	if len(gr.Candidates) == 0 || len(gr.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("gemini: risposta vuota (finish=%s)", gr.Candidates[0].FinishReason)
	}
	return gr.Candidates[0].Content.Parts[0].Text, nil
}

func buildPrompt(market, portfolioJSON string) string {
	marketName := "Wall Street"
	if market == "IT" {
		marketName = "Borsa Italiana"
	}
	return fmt.Sprintf(`Sei un analista finanziario esperto. Analizza questo portafoglio e genera UN SOLO consiglio per il mercato %s.

PORTFOLIO:
%s

Rispondi SOLO con JSON valido (nessun testo extra):
{
  "title": "Titolo breve del consiglio",
  "action": "BUY o SELL o HOLD",
  "overview": "Riassunto 2-3 frasi",
  "reasoning": "Ragionamento dettagliato in 3-5 frasi",
  "risks": "Rischio principale in 1-2 frasi",
  "confidence": "ALTA o MEDIA o BASSA",
  "timeframe": "es. 3-6 mesi",
  "stocks": [{"ticker": "XXX", "name": "Nome", "action": "BUY/SELL/HOLD"}]
}`, marketName, portfolioJSON)
}

func parseAdvice(text string, userID int64, market string) (*AdviceData, error) {
	// Strip markdown code block se presente
	text = strings.TrimSpace(text)
	if strings.HasPrefix(text, "```") {
		lines := strings.SplitN(text, "\n", 3)
		if len(lines) >= 3 {
			text = lines[1]
			if idx := strings.LastIndex(text, "```"); idx >= 0 {
				text = text[:idx]
			}
		}
	}
	text = strings.TrimSpace(text)

	var adv AdviceData
	if err := json.Unmarshal([]byte(text), &adv); err != nil {
		return nil, fmt.Errorf("parse JSON: %w", err)
	}
	adv.Title = strings.TrimSpace(adv.Title)
	adv.Action = strings.TrimSpace(adv.Action)
	adv.Overview = strings.TrimSpace(adv.Overview)
	adv.Reasoning = strings.TrimSpace(adv.Reasoning)
	adv.Risks = strings.TrimSpace(adv.Risks)
	adv.Confidence = strings.TrimSpace(adv.Confidence)
	adv.Timeframe = strings.TrimSpace(adv.Timeframe)
	if adv.Title == "" {
		adv.Title = "Consiglio " + market
	}
	return &adv, nil
}

func storeAdvice(wdb *sql.DB, adv *AdviceData, userID int64, market string) error {
	stocksJSON, _ := json.Marshal(adv.Stocks)
	var stockID sql.NullInt64
	if len(adv.Stocks) > 0 {
		ticker := strings.TrimSpace(strings.ToUpper(adv.Stocks[0].Ticker))
		if ticker != "" {
			var id int64
			if err := wdb.QueryRow(`SELECT id FROM stocks WHERE ticker = ?`, ticker).Scan(&id); err == nil {
				stockID = sql.NullInt64{Int64: id, Valid: true}
			}
		}
	}
	return db.WithRetry(func() error {
		_, err := wdb.Exec(`INSERT INTO advices
			(user_id, market, title, action, overview, reasoning, stocks_json,
			 risks, confidence, timeframe, target_price, suggested_quantity,
			 stock_id, followed, timestamp, created_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
			userID, market, adv.Title, adv.Action, adv.Overview, adv.Reasoning,
			string(stocksJSON), adv.Risks, adv.Confidence, adv.Timeframe,
			adv.TargetPrice, adv.SuggestedQuantity, stockID,
			db.NowUTC(), db.NowUTC())
		return err
	})
}

func loadHoldingsBrief(rdb *sql.DB, userID int64) (string, error) {
	rows, err := rdb.Query(`
		SELECT s.ticker, s.name, s.market, s.currency,
		       h.quantity, h.avg_purchase_price,
		       (SELECT ph.close FROM price_history ph
		         WHERE ph.stock_id = h.stock_id ORDER BY ph.timestamp DESC LIMIT 1)
		  FROM holdings h JOIN stocks s ON s.id = h.stock_id
		 WHERE h.user_id = ? AND s.is_active = 1`, userID)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	type h struct {
		Ticker, Name, Market, Currency string
		Qty, AvgPrice, LastClose       float64
	}
	var hs []h
	for rows.Next() {
		var r h
		if err := rows.Scan(&r.Ticker, &r.Name, &r.Market, &r.Currency, &r.Qty, &r.AvgPrice, &r.LastClose); err != nil {
			return "", err
		}
		if r.LastClose == 0 {
			r.LastClose = r.AvgPrice
		}
		hs = append(hs, r)
	}
	b, err := json.MarshalIndent(hs, "", "  ")
	return string(b), err
}

// Generate POST /api/advice/generate — chiama Gemini 3.8 Flash e salva il consiglio.
func Generate(rdb, wdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		u := auth.FromContext(r.Context())
		if u == nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"detail": "Sessione non valida."})
			return
		}

		apiKey := resolveAPIKey(rdb)
		if apiKey == "" {
			writeJSON(w, http.StatusBadRequest, map[string]any{
				"ok": false, "detail": "Chiave Gemini non configurata.",
			})
			return
		}

		// Parse body opzionale
		var req struct {
			Market string `json:"market"`
		}
		if r.Body != nil {
			json.NewDecoder(r.Body).Decode(&req)
		}
		market := strings.ToUpper(strings.TrimSpace(req.Market))
		if market == "" {
			market = "ALL"
		}

		portfolioJSON, err := loadHoldingsBrief(rdb, u.ID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore lettura portafoglio."})
			return
		}
		if portfolioJSON == "null" || portfolioJSON == "[]" {
			writeJSON(w, http.StatusBadRequest, map[string]any{
				"ok": false, "detail": "Portafoglio vuoto, niente da analizzare.",
			})
			return
		}

		prompt := buildPrompt(market, portfolioJSON)
		text, err := callGemini(prompt, apiKey)
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]any{
				"ok": false, "detail": fmt.Sprintf("Errore Gemini: %s", err.Error()),
			})
			return
		}

		adv, err := parseAdvice(text, u.ID, market)
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]any{
				"ok": false, "detail": fmt.Sprintf("Risposta Gemini non valida: %s", err.Error()),
			})
			return
		}

		if wdb == nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"detail": "DB in sola lettura, impossibile salvare."})
			return
		}
		if err := storeAdvice(wdb, adv, u.ID, market); err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore salvataggio consiglio."})
			return
		}

		log.Printf("advisor: consiglio generato per user %d (market=%s, action=%s, confidence=%s)", u.ID, market, adv.Action, adv.Confidence)
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":     true,
			"detail": "Consiglio generato e salvato.",
			"advice": adv,
		})
	}
}

// List GET /api/advice — ultimi consigli per l'utente.
func List(rdb *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"detail": "Metodo non consentito."})
			return
		}
		u := auth.FromContext(r.Context())
		if u == nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"detail": "Sessione non valida."})
			return
		}

		rows, err := rdb.Query(`
			SELECT a.id, a.market, a.title, a.action, a.overview, a.reasoning,
			       a.stocks_json, a.risks, a.confidence, a.timeframe,
			       a.target_price, a.suggested_quantity, a.followed,
			       a.timestamp, s.ticker, s.name
			  FROM advices a LEFT JOIN stocks s ON s.id = a.stock_id
			 WHERE a.user_id = ? OR a.user_id IS NULL
			 ORDER BY a.timestamp DESC LIMIT 20`, u.ID)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"detail": "Errore DB."})
			return
		}
		defer rows.Close()

		out := []any{}
		for rows.Next() {
			var id int64
			var market, title, action, overview, reasoning, stocksJSON, risks,
				confidence, timeframe, ts, ticker, name sql.NullString
			var target sql.NullFloat64
			var qty sql.NullInt64
			var followed sql.NullBool
			if err := rows.Scan(&id, &market, &title, &action, &overview, &reasoning,
				&stocksJSON, &risks, &confidence, &timeframe, &target, &qty,
				&followed, &ts, &ticker, &name); err != nil {
				continue
			}
			var analysis any
			if stocksJSON.Valid && strings.TrimSpace(stocksJSON.String) != "" {
				json.Unmarshal([]byte(stocksJSON.String), &analysis)
			}
			item := map[string]any{
				"id": id, "market": strOr(market, "ALL"), "title": strOr(title, "Consiglio"),
				"action": strOr(action, ""), "overview": strOr(overview, ""),
				"strategy": strOr(reasoning, ""), "stocks_analysis": analysis,
				"risks": strOr(risks, ""), "confidence": strOr(confidence, ""),
				"timeframe": strOr(timeframe, ""),
				"followed":  followed.Valid && followed.Bool, "timestamp": strOr(ts, ""),
				"ticker": strOr(ticker, ""), "name": strOr(name, ""),
			}
			if target.Valid {
				item["targetPrice"] = target.Float64
			}
			if qty.Valid {
				item["suggestedQuantity"] = qty.Int64
			}
			out = append(out, item)
		}
		writeJSON(w, http.StatusOK, out)
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func strOr(ns sql.NullString, def string) string {
	if ns.Valid && ns.String != "" {
		return ns.String
	}
	return def
}
