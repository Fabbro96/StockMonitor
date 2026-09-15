package stocks

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
)

func resetSearchState(t *testing.T, mockURL string) *int64 {
	t.Helper()
	mu.Lock()
	cache = map[string]cacheEntry{}
	mu.Unlock()
	old := searchBaseURL
	searchBaseURL = mockURL
	t.Cleanup(func() { searchBaseURL = old })
	return new(int64)
}

func doSearch(t *testing.T, q string, headers map[string]string) (int, []byte, http.Header) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/stocks/search?q="+url.QueryEscape(q), nil)
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	Search()(rec, req)
	return rec.Code, rec.Body.Bytes(), rec.Header()
}

func TestSearchMappingMax8(t *testing.T) {
	var hits int64
	mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt64(&hits, 1)
		if got := r.URL.Query().Get("quotesCount"); got != "8" {
			t.Errorf("quotesCount=%q, want 8", got)
		}
		if ua := r.Header.Get("User-Agent"); ua != uaFixed {
			t.Errorf("User-Agent=%q, want fisso", ua)
		}
		// 10 quote valide + 1 falso positivo senza symbol.
		quotes := []string{`{"symbol":"","shortname":"Senza Symbol"}`}
		for i := 0; i < 10; i++ {
			quotes = append(quotes, `{"symbol":"T`+string(rune('A'+i))+`.MI","shortname":"Titolo `+string(rune('A'+i))+`"}`)
		}
		_, _ = w.Write([]byte(`{"quotes":[` + strings.Join(quotes, ",") + `]}`))
	}))
	defer mock.Close()
	resetSearchState(t, mock.URL)

	code, body, _ := doSearch(t, "mediolanum", nil)
	if code != http.StatusOK {
		t.Fatalf("status=%d, want 200", code)
	}
	var out []SearchResult
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(out) != 8 {
		t.Fatalf("len=%d, want max 8", len(out))
	}
	for _, r := range out {
		if r.Ticker == "" || r.Name == "" || r.Market == "" {
			t.Errorf("record incompleto: %+v", r)
		}
	}
	if out[0].Ticker != "TA.MI" || out[0].Name != "Titolo A" || out[0].Market != "IT" {
		t.Errorf("mapping errato: %+v", out[0])
	}
}

func TestSearchMediolanumResolve(t *testing.T) {
	mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"quotes":[
			{"symbol":"MED.MI","shortname":"Mediobanca SpA"},
			{"symbol":"","shortname":"Falso positivo"}
		]}`))
	}))
	defer mock.Close()
	resetSearchState(t, mock.URL)

	sym, name, ok := ResolveTicker("mediolanum")
	if !ok || sym != "MED.MI" || name != "Mediobanca SpA" {
		t.Errorf("resolve=(%q,%q,%v), want (MED.MI, Mediobanca SpA, true)", sym, name, ok)
	}
}

func TestSearchCacheHit(t *testing.T) {
	var hits int64
	mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt64(&hits, 1)
		_, _ = w.Write([]byte(`{"quotes":[{"symbol":"ENEL.MI","shortname":"Enel"}]}`))
	}))
	defer mock.Close()
	resetSearchState(t, mock.URL)

	if code, _, _ := doSearch(t, "enel", nil); code != 200 {
		t.Fatalf("prima: status=%d", code)
	}
	code, body, hdr := doSearch(t, "enel", nil)
	if code != 200 {
		t.Fatalf("seconda: status=%d", code)
	}
	if n := atomic.LoadInt64(&hits); n != 1 {
		t.Errorf("mock hits=%d, want 1 (seconda da cache)", n)
	}
	if hdr.Get("ETag") == "" {
		t.Errorf("ETag mancante in cache HIT")
	}
	var out []SearchResult
	if err := json.Unmarshal(body, &out); err != nil || len(out) != 1 || out[0].Ticker != "ENEL.MI" {
		t.Errorf("body HIT errato: %s", body)
	}
	// 304 con If-None-Match.
	code, _, _ = doSearch(t, "enel", map[string]string{"If-None-Match": hdr.Get("ETag")})
	if code != http.StatusNotModified {
		t.Errorf("304: status=%d", code)
	}
	if n := atomic.LoadInt64(&hits); n != 1 {
		t.Errorf("mock hits=%d dopo 304, want 1", n)
	}
}

func TestSearchQueryCorta(t *testing.T) {
	resetSearchState(t, "http://127.0.0.1:1")
	for _, q := range []string{"", "a", " x "} {
		if code, _, _ := doSearch(t, q, nil); code != http.StatusBadRequest {
			t.Errorf("q=%q: status=%d, want 400", q, code)
		}
	}
}

func TestSearchYahooDown(t *testing.T) {
	// Mock che risponde 429 e poi chiude: entrambi devono dare 200 vuoto.
	mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	resetSearchState(t, mock.URL)
	code, body, _ := doSearch(t, "qualcosa", nil)
	if code != http.StatusOK {
		t.Fatalf("429: status=%d, want 200", code)
	}
	if strings.TrimSpace(string(body)) != "[]" {
		t.Errorf("429: body=%s, want []", body)
	}
	mock.Close()

	mu.Lock()
	cache = map[string]cacheEntry{}
	mu.Unlock()
	code, body, _ = doSearch(t, "altro", nil)
	if code != http.StatusOK {
		t.Fatalf("down: status=%d, want 200", code)
	}
	if strings.TrimSpace(string(body)) != "[]" {
		t.Errorf("down: body=%s, want []", body)
	}
}

func TestSearchResolveFail(t *testing.T) {
	mock := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer mock.Close()
	resetSearchState(t, mock.URL)
	if _, _, ok := ResolveTicker("xyz123"); ok {
		t.Errorf("resolve su Yahoo ko: ok=true, want false")
	}
}
