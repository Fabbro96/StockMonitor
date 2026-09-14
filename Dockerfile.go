# syntax=docker/dockerfile:1
# ============================================================================
# StockMon Go — immagine minimale per TerraMaster F2-212 (ARM64, 2 GB RAM)
# Target: ~20 MB totali, idle 15-30 MB, solo stdlib net/http + SQLite pure-Go.
# Il web embedded (server-go/web/dist) è servito via embed.FS: niente
# Node/Flutter/Caddy nel runtime.
# ============================================================================

# --- Stage 1: builder (toolchain Go, scartata nel runtime) ---
FROM golang:1.23-bookworm AS builder

ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=arm64 \
    GOFLAGS=-mod=mod

WORKDIR /src

# Solo go.mod/go.sum prima: layer cache per i download dei moduli.
COPY server-go/go.mod server-go/go.sum ./
RUN go mod download

# Sorgenti Go + web statico (embed.FS lo include nel binary).
COPY server-go/ ./

RUN go build -trimpath -ldflags="-s -w" -o /stockmon ./cmd/stockmon

# --- Stage 2: runtime scratch (~20 MB) ---
FROM scratch

# TLS verso Yahoo (chart v8) senza shell né package manager.
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
# Fusi orari per market-status (Europe/Rome, Europe/Paris, America/New_York).
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

COPY --from=builder /stockmon /stockmon

ENV PORT=8000 \
    DB_PATH=/data/stock_monitor.db \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    ZONEINFO=/usr/share/zoneinfo

EXPOSE 8000

HEALTHCHECK --interval=60s --timeout=3s --retries=3 \
    CMD ["/stockmon", "-healthcheck"]

ENTRYPOINT ["/stockmon"]
