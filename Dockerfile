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
# Stage 2 - webbuilder: compile the Flutter web bundle
# ============================================================================
# Flutter is pinned via the official release tarball, not a container tag:
# ghcr.io/cirruslabs/flutter:3.47.2 does not exist (404, verified 2026-09-14)
# and :stable may ship a Dart SDK older than the `sdk: ^3.13.2` constraint in
# app/pubspec.yaml, breaking the build. Keep FLUTTER_VERSION in sync with that
# constraint when the app SDK requirement changes (Flutter 3.47.2 -> Dart 3.13.2,
# confirmed via releases_linux.json).
# Tarball existence verified with:
#   curl -sI https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.2-stable.tar.xz  ->  HTTP/2 200
# --platform=$BUILDPLATFORM: the web bundle does not depend on the target
# architecture, so build it once natively instead of emulating arm64 via QEMU.
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS webbuilder

ARG FLUTTER_VERSION=3.47.2

# Minimal download-only toolchain. unzip is required by the Flutter tool to
# unpack the web engine artifacts; git is needed to inspect the checkout.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/flutter/bin:$PATH"

# Flutter refuses to run from a git checkout owned by a different user; harmless
# as root, required if the build ever runs with a remapped uid.
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm -f /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter \
    && flutter --version

COPY app/ /app/app
RUN cd /app/app \
    && flutter pub get \
    && flutter build web --release --no-web-resources-cdn

# ============================================================================
# Stage 3 - runtime: slim image, no gcc/build toolchain
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

# Flutter web bundle (served by the backend at /, replaces the old frontend/)
COPY --from=webbuilder /app/app/build/web ./web

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
