# Comet Boundary: Hermetic Replay Makefile
# This Makefile orchestrates the "One-Button" replay of the entire demo environment.

.PHONY: replay deps setup start verify stop clean restart

# Include dynamic environment variables if they exist (generated during setup)
ifneq ("$(wildcard .env)","")
    include .env
    export
endif

COMPOSE := $(shell command -v docker-compose 2>/dev/null || echo "docker compose")

# --- PRIMARY WORKFLOW ---

# The "One-Button" Replay: Cleans, verifies dependencies, bootstraps, and starts the demo.
# Use this to establish a fresh, verified environment on any macOS machine.
replay: clean deps setup
	$(MAKE) start verify

# --- INDIVIDUAL STEPS ---

# 0. Check and install system-level dependencies (brew, jq, go, node, docker)
deps:
	@echo "Step 0: Verifying system dependencies..."
	./scripts/00_check-deps.sh

# 1. Bootstrap the infrastructure and initialize Boundary configuration
setup:
	@echo "Step 1: Starting infrastructure and bootstrapping Boundary..."
	$(COMPOSE) up -d postgres openldap controller worker ssh-target-1 ssh-target-2 setup
	./scripts/01_setup-boundary.sh
	@echo "Syncing backend dependencies..."
	cd server && go mod tidy

# 2. Start the Backend Proxy and Frontend Application via Docker
start:
	@echo "Step 2: Starting Backend and Frontend services..."
	$(COMPOSE) up -d --build backend frontend

# 3. Verify the entire environment
verify:
	@echo "Step 3: Running final verification checks..."
	./scripts/02_verify-setup.sh

# --- MAINTENANCE ---

# Stop all running containers
stop:
	$(COMPOSE) stop

# Completely destroy the environment, including persistent volumes and logs
clean:
	@echo "Cleaning up previous state..."
	$(COMPOSE) down -v
	rm -f server.log client.log server/server_bin .env client/.env.local

# Restart the application services without rebuilding infrastructure
restart: stop
	$(COMPOSE) up -d --build backend frontend
	$(COMPOSE) up -d postgres openldap controller worker ssh-target-1 ssh-target-2
