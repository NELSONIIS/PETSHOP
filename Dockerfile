# syntax=docker/dockerfile:1.7
# PETORA: one image containing the Go API/worker binaries and the compiled React app.

# ---- 1. web frontend ----
FROM node:22.11-alpine AS web
WORKDIR /src/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
COPY docs/ /src/docs/
RUN npm run build

# ---- 2. Go binaries ----
FROM golang:1.26-alpine AS go
WORKDIR /src
ENV CGO_ENABLED=0 GOFLAGS=-trimpath
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/ cmd/
COPY internal/ internal/
COPY migrations/ migrations/
ARG VERSION=dev
RUN go build -ldflags="-s -w -X main.version=${VERSION}" -o /out/api ./cmd/api && \
    go build -ldflags="-s -w" -o /out/worker ./cmd/worker && \
    mkdir -p /out/data/storage

# ---- 3. runtime (distroless, non-root) ----
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=go /out/api /out/worker /app/
# Pre-create the media directory owned by nonroot so the named volume inherits writable ownership.
COPY --from=go --chown=nonroot:nonroot /out/data /data
COPY --from=web /src/frontend/dist /app/frontend/dist
COPY docs/openapi.yaml /app/docs/openapi.yaml
ENV HTTP_ADDR=:8080 FRONTEND_DIST=/app/frontend/dist STORAGE_LOCAL_PATH=/data/storage
USER nonroot:nonroot
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=4s --start-period=20s --retries=3 CMD ["/app/api", "healthcheck"]
ENTRYPOINT ["/app/api"]
CMD ["serve"]
