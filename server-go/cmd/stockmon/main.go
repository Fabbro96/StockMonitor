// Command stockmon: backend Go leggerissimo Fase-1/2 per Terramaster
// F2-212 (ARM64, 2GB RAM), target idle 15-30MB.
//
// DB_MODE=ro (default): sola lettura, il Python resta writer unico.
// DB_MODE=rw: scritture Fase-2 (watchlist/portfolio/alert-rules) + scheduler
// in-process su UN solo *sql.DB serializzato. Solo stdlib net/http.
package main

import (
	"bytes"
	"compress/gzip"
	"database/sql"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"stockmon/internal/alerts"
	"stockmon/internal/auth"
	"stockmon/internal/dashboard"
	"stockmon/internal/db"
	"stockmon/internal/portfolio"
	"stockmon/internal/scheduler"
	"stockmon/internal/stocks"
	"stockmon/internal/watchlist"
	"stockmon/web"
)

// gzipMinBytes: sotto questa soglia gzip non conviene (solo overhead).
const gzipMinBytes = 1024

func acceptsGzip(r *http.Request) bool {
	for _, part := range strings.Split(r.Header.Get("Accept-Encoding"), ",") {
		if strings.TrimSpace(strings.SplitN(part, ";", 2)[0]) == "gzip" {
			return true
		}
	}
	return false
}

type gzipBuffer struct {
	http.ResponseWriter
	status      int
	buf         bytes.Buffer
	wroteHeader bool
}

func (g *gzipBuffer) WriteHeader(status int) {
	if g.wroteHeader {
		return
	}
	g.wroteHeader = true
	g.status = status
}

func (g *gzipBuffer) Write(p []byte) (int, error) {
	if !g.wroteHeader {
		g.WriteHeader(http.StatusOK)
	}
	return g.buf.Write(p)
}

// gzipMiddleware comprime (level 1, stdlib) solo le risposte /api/* JSON
// >1KB quando il client invia Accept-Encoding: gzip. Header Cache-Control /
// ETag esistenti restano intoccati (il 304 esce prima, body vuoto).
func gzipMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/api/") || !acceptsGzip(r) {
			next.ServeHTTP(w, r)
			return
		}
		gb := &gzipBuffer{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(gb, r)
		body := gb.buf.Bytes()
		ct := w.Header().Get("Content-Type")
		if gb.status == http.StatusNoContent || gb.status == http.StatusNotModified ||
			len(body) <= gzipMinBytes || !strings.Contains(ct, "application/json") {
			w.WriteHeader(gb.status)
			_, _ = w.Write(body)
			return
		}
		w.Header().Del("Content-Length")
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Add("Vary", "Accept-Encoding")
		w.WriteHeader(gb.status)
		gz, err := gzip.NewWriterLevel(w, 1)
		if err != nil {
			_, _ = w.Write(body)
			return
		}
		_, _ = gz.Write(body)
		_ = gz.Close()
	})
}

func env(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, `{"status":"ok"}`)
}

func main() {
	healthcheck := flag.Bool("healthcheck", false, "GET /health in-process ed esci (0 ok, 1 ko)")
	schedOnce := flag.String("scheduler-once", "", "dry-run scheduler e esci: collect|alerts (richiede DB_MODE=rw)")
	cleanupOnce := flag.Bool("cleanup-once", false, "dry-run retention e esci (richiede DB_MODE=rw)")
	precomputeOnce := flag.Bool("precompute-once", false, "dry-run serie 90gg e esci (richiede DB_MODE=rw)")
	flag.Parse()

	port := env("PORT", "8001")
	dbPath := env("DB_PATH", "data/stock_monitor.db")
	dbMode := strings.ToLower(strings.TrimSpace(env("DB_MODE", "ro")))
	readOnly := dbMode != "rw"

	if *schedOnce != "" && *schedOnce != "collect" && *schedOnce != "alerts" {
		fmt.Fprintln(os.Stderr, "-scheduler-once deve essere collect|alerts")
		os.Exit(2)
	}

	if *healthcheck {
		resp, err := http.Get("http://127.0.0.1:" + port + "/health")
		if err != nil {
			fmt.Fprintln(os.Stderr, "healthcheck: "+err.Error())
			os.Exit(1)
		}
		defer resp.Body.Close()
		_, _ = io.Copy(io.Discard, resp.Body)
		if resp.StatusCode != http.StatusOK {
			fmt.Fprintf(os.Stderr, "healthcheck: status %d\n", resp.StatusCode)
			os.Exit(1)
		}
		os.Exit(0)
	}

	boot := time.Now()
	// DB_MODE=rw: UN solo handle (pool 1) per letture+scritture serializzate.
	// DB_MODE=ro: pool di lettura separato, writer esterno unico.
	conn, err := db.Open(dbPath, readOnly)
	if err != nil {
		log.Fatalf("db open %s (ro=%v): %v", dbPath, readOnly, err)
	}
	defer conn.Close()
	read := conn
	var wdb *sql.DB
	if !readOnly {
		wdb = conn
	}

	// Dry-run retention/precompute: eseguono un job e escono (writer).
	if *cleanupOnce {
		if wdb == nil {
			fmt.Fprintln(os.Stderr, "-cleanup-once richiede DB_MODE=rw")
			os.Exit(2)
		}
		deleted, err := scheduler.CleanupOnce(read, wdb)
		if err != nil {
			log.Fatalf("cleanup-once: %v", err)
		}
		log.Printf("cleanup-once: eliminate %+v", deleted)
		return
	}
	if *precomputeOnce {
		if wdb == nil {
			fmt.Fprintln(os.Stderr, "-precompute-once richiede DB_MODE=rw")
			os.Exit(2)
		}
		if err := scheduler.PrecomputeOnce(read, wdb); err != nil {
			log.Fatalf("precompute-once: %v", err)
		}
		return
	}

	// Dry-run scheduler: esegue un job e esce (serve il writer).
	if *schedOnce != "" {
		if wdb == nil {
			fmt.Fprintln(os.Stderr, "-scheduler-once richiede DB_MODE=rw")
			os.Exit(2)
		}
		if *schedOnce == "collect" {
			n, err := scheduler.CollectOnce(read, wdb)
			if err != nil {
				log.Fatalf("scheduler-once collect: %v", err)
			}
			log.Printf("scheduler-once collect: %d righe scritte", n)
		} else {
			n, err := scheduler.AlertsOnce(read)
			if err != nil {
				log.Fatalf("scheduler-once alerts: %v", err)
			}
			log.Printf("scheduler-once alerts: %d trigger", n)
		}
		return
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", healthHandler)
	mux.HandleFunc("POST /api/auth/login", auth.LoginHandler(conn))
	mux.HandleFunc("GET /api/auth/me", auth.MeHandler(conn))

	authed := func(h http.HandlerFunc) http.HandlerFunc {
		return auth.Middleware(conn, h).ServeHTTP
	}

	// Dashboard: sia con che senza trailing slash (il client Flutter usa "/").
	mux.HandleFunc("GET /api/dashboard", authed(dashboard.Root(conn)))
	mux.HandleFunc("GET /api/dashboard/", authed(dashboard.Root(conn)))
	mux.HandleFunc("GET /api/dashboard/market-status", authed(dashboard.MarketStatusHandler()))
	mux.HandleFunc("GET /api/dashboard/indices", authed(dashboard.Indices(conn)))
	mux.HandleFunc("GET /api/dashboard/heatmap", authed(dashboard.Heatmap(conn)))
	mux.HandleFunc("GET /api/dashboard/performance", authed(dashboard.Performance(conn)))

	mux.HandleFunc("GET /api/watchlist", authed(watchlist.List(conn)))
	mux.HandleFunc("GET /api/watchlist/", authed(watchlist.List(conn)))
	// Scritture Fase-2 (503 se DB_MODE=ro): 201 nuovo / 409 duplicato.
	mux.HandleFunc("POST /api/watchlist", authed(watchlist.Create(read, wdb)))
	mux.HandleFunc("POST /api/watchlist/", authed(watchlist.Create(read, wdb)))
	mux.HandleFunc("PUT /api/watchlist/{id}/alert", authed(watchlist.UpdateAlert(read, wdb)))
	mux.HandleFunc("DELETE /api/watchlist/{id}", authed(watchlist.Delete(read, wdb)))
	mux.HandleFunc("DELETE /api/watchlist/ticker/{ticker}", authed(watchlist.DeleteByTicker(read, wdb)))

	mux.HandleFunc("GET /api/portfolio", authed(portfolio.List(read, wdb)))
	mux.HandleFunc("GET /api/portfolio/", authed(portfolio.List(read, wdb)))
	mux.HandleFunc("POST /api/portfolio/holdings", authed(portfolio.CreateHolding(read, wdb)))
	mux.HandleFunc("PUT /api/portfolio/holdings/{id}", authed(portfolio.UpdateHolding(read, wdb)))
	mux.HandleFunc("DELETE /api/portfolio/holdings/{id}", authed(portfolio.DeleteHolding(read, wdb)))
	mux.HandleFunc("GET /api/portfolio/transactions", authed(portfolio.ListTransactions(read, wdb)))
	mux.HandleFunc("POST /api/portfolio/transactions", authed(portfolio.CreateTransaction(read, wdb)))
	mux.HandleFunc("DELETE /api/portfolio/transactions/{id}", authed(portfolio.DeleteTransaction(read, wdb)))
	// Analytics pack-perf: daily-cache fresca o on-demand (X-Cache HIT/MISS).
	mux.HandleFunc("GET /api/portfolio/risk-metrics", authed(portfolio.RiskMetrics(read, wdb)))
	mux.HandleFunc("GET /api/portfolio/history", authed(portfolio.History(read, wdb)))

	// Path reale Python: /api/settings/alerts (+ PUT estensione Fase-2).
	mux.HandleFunc("GET /api/settings/alerts", authed(alerts.List(read, wdb)))
	mux.HandleFunc("POST /api/settings/alerts", authed(alerts.Create(read, wdb)))
	mux.HandleFunc("PUT /api/settings/alerts/{id}", authed(alerts.Update(read, wdb)))
	mux.HandleFunc("DELETE /api/settings/alerts/{id}", authed(alerts.Delete(read, wdb)))

	mux.HandleFunc("GET /api/stocks/search", authed(stocks.Search()))
	mux.HandleFunc("GET /api/stocks/{ticker}/candles", authed(stocks.Candles(conn)))

	// Build web embedded (server-go/web/dist): registrata DOPO /api/* e
	// /health così le API hanno sempre precedenza. La query string (?v=1)
	// non fa parte del match del ServeMux: nessun handling dedicato.
	indexHTML, err := web.Dist.ReadFile("dist/index.html")
	if err != nil {
		log.Fatalf("web embedded: index.html mancante: %v", err)
	}
	appJS, err := web.Dist.ReadFile("dist/app.js")
	if err != nil {
		log.Fatalf("web embedded: app.js mancante: %v", err)
	}
	styleCSS, err := web.Dist.ReadFile("dist/style.css")
	if err != nil {
		log.Fatalf("web embedded: style.css mancante: %v", err)
	}
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(indexHTML)
	})
	serveImmutable := func(body []byte, contentType string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", contentType)
			w.Header().Set("Cache-Control", "public,max-age=31536000,immutable")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(body)
		}
	}
	mux.HandleFunc("GET /app.js", serveImmutable(appJS, "text/javascript; charset=utf-8"))
	mux.HandleFunc("GET /style.css", serveImmutable(styleCSS, "text/css; charset=utf-8"))

	// CORS mirror del Python (origini locali/LAN + credentials) + gzip /api/*.
	handler := gzipMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if o := r.Header.Get("Origin"); isLocalOrigin(o) {
			w.Header().Set("Access-Control-Allow-Origin", o)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set("Vary", "Origin")
		}
		if r.Method == http.MethodOptions {
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		mux.ServeHTTP(w, r)
	}))

	// Scheduler in-process: solo con writer (DB_MODE=rw) + opt-in esplicito.
	schedOn := strings.EqualFold(strings.TrimSpace(env("ENABLE_SCHEDULER", "false")), "true")
	if schedOn && wdb == nil {
		log.Printf("scheduler: ENABLE_SCHEDULER=true ma DB_MODE=ro, scheduler disabilitato")
		schedOn = false
	}
	if schedOn {
		alertsMin := 60
		if s := strings.TrimSpace(env("ALERT_CHECK_INTERVAL_MINUTES", "60")); s != "" {
			if n, err := strconv.Atoi(s); err == nil && n > 0 {
				alertsMin = n
			}
		}
		scheduler.Start(read, wdb, alertsMin, nil)
	}

	log.Printf("stockmon fase-2 (db=%s ro=%v sched=%v) :%s boot=%s", dbPath, readOnly, schedOn, port, time.Since(boot).Round(time.Millisecond))
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatal(err)
	}
}

func isLocalOrigin(o string) bool {
	if o == "" {
		return false
	}
	for _, p := range []string{
		"http://localhost", "https://localhost",
		"http://127.0.0.1", "https://127.0.0.1",
		"http://192.168.", "https://192.168.",
		"http://10.", "https://10.",
		"http://0.0.0.0", "https://0.0.0.0",
	} {
		if strings.HasPrefix(o, p) {
			return true
		}
	}
	return false
}
