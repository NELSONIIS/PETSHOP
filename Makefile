# PETORA developer tasks
SHELL := /bin/bash
ENV ?= .env.dev.local
TEST_DATABASE_URL ?= postgres://petora@localhost:5433/petora_test?sslmode=disable
TEST_REDIS_URL ?= redis://localhost:6380/15
load = set -a; [ -f $(ENV) ] && . ./$(ENV); set +a;

.PHONY: build run worker migrate seed seed-demo test test-unit test-integration lint fmt vuln web web-test docker-build compose-config

build:            ## compile Go binaries
	go build -o bin/api ./cmd/api && go build -o bin/worker ./cmd/worker
run: build        ## run API (uses $(ENV))
	$(load) ./bin/api serve
worker: build
	$(load) ./bin/worker
migrate: build
	$(load) ./bin/api migrate
seed: build
	$(load) ./bin/api seed
seed-demo: build  ## demo data (refused in production)
	$(load) ./bin/api seed --demo
test: test-unit test-integration
test-unit:
	go test ./internal/...
test-integration: ## drops and recreates the TEST database schema
	TEST_DATABASE_URL='$(TEST_DATABASE_URL)' TEST_REDIS_URL='$(TEST_REDIS_URL)' go test -count=1 ./tests/integration/
lint:
	@test -z "$$(gofmt -l cmd internal tests migrations)" || (echo "gofmt needed:"; gofmt -l cmd internal tests; exit 1)
	go vet ./...
fmt:
	gofmt -w cmd internal tests
vuln:
	go run golang.org/x/vuln/cmd/govulncheck@latest ./...
web:
	cd frontend && npm ci && npm run build
web-test:
	cd frontend && npm run lint && npm run typecheck && npm test
docker-build:
	docker build -t petora:latest .
compose-config:   ## validate compose file
	docker compose --env-file .env.example config >/dev/null && echo "compose OK"
