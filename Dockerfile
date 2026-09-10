# syntax=docker/dockerfile:1

# ============================================================================
# Stage 1 - builder: install Python dependencies (build toolchain stays here)
# ============================================================================
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install -r requirements.txt

# ============================================================================
# Stage 2 - runtime: slim image, no gcc/build toolchain
# ============================================================================
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

# Python dependencies copied from builder (no compiler in runtime image)
COPY --from=builder /opt/venv /opt/venv

# Application code
COPY backend/ ./backend/
COPY frontend/ ./frontend/

# Data directory for SQLite
RUN mkdir -p /app/data

# NOTE: runtime intentionally runs as root. On the TerraMaster NAS ./data is a
# bind mount holding a SQLite DB created by the previous root container; a
# non-root uid (e.g. 1000) may lack write access and break the app on the first
# Watchtower auto-update. Accepted risk on LAN (same posture as before).

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD python -c "import httpx; r = httpx.get('http://localhost:8000/health', timeout=8); exit(0 if r.status_code == 200 else 1)" || exit 1

# Single worker: NAS has 2 GB RAM. Arch-neutral on both linux/amd64 and linux/arm64.
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
