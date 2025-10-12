SHELL := /bin/bash
.ONESHELL:
.DEFAULT_GOAL := help

# --- Configuration ---
IMAGE_NAME     := medical-mcp-server
CONTAINER_NAME := $(IMAGE_NAME)-dev
VENV_DIR       := .venv
RUN_DIR        := .run
SERVER_PID     := $(RUN_DIR)/server.pid
SERVER_LOG     := $(RUN_DIR)/server.log

# MCP server defaults
MCP_HOST       := 0.0.0.0
MCP_PORT       := 9090

# --- Tooling detection (prefer uv if available) ---
UV_BIN     := $(shell command -v uv 2>/dev/null)
HAVE_UV    := $(if $(UV_BIN),1,0)

ifeq ($(HAVE_UV),0)
  RUNNER       := $(VENV_DIR)/bin/python -m
  VENV_CREATE  := python -m venv $(VENV_DIR)
  INSTALL_PROD := $(VENV_DIR)/bin/pip install -U pip && $(VENV_DIR)/bin/pip install -e .
  RUN_RUFF     := $(VENV_DIR)/bin/ruff
  RUN_BLACK    := $(VENV_DIR)/bin/black
  RUN_PYTEST   := $(VENV_DIR)/bin/pytest
  RUN_PY       := $(VENV_DIR)/bin/python
  RUN_UVICORN  := $(VENV_DIR)/bin/uvicorn
else
  RUNNER       := uv run
  VENV_CREATE  := uv venv $(VENV_DIR)
  INSTALL_PROD := UV_LINK_MODE=$${UV_LINK_MODE:-copy} uv sync
  RUN_RUFF     := uv run --with ruff ruff
  RUN_BLACK    := uv run --with black black
  RUN_PYTEST   := uv run --with pytest pytest
  RUN_PY       := uv run python
  RUN_UVICORN  := uv run uvicorn
endif

# --- Targets ---
.PHONY: help venv install \
        run start start-stdio \
        test-client logs stop-server \
        fmt lint test \
        clean docker-build docker-run docker-logs docker-stop

##@ Help
help: ## Show this help message
	@echo ""
	@echo "medical-mcp-toolkit — developer commands"
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	sed -e 's/^\([^:]*\):.*## \(.*\)/\1|\2/' | \
	awk -F "|" '{printf "  %-22s %s\n", $$1, $$2}' | \
	sort

##@ Setup & Installation
venv: ## Create the Python virtual environment (prefers uv)
	@if [ -d "$(VENV_DIR)" ]; then echo "venv already exists at $(VENV_DIR)"; else $(VENV_CREATE); fi

install: ## Install production deps from pyproject.toml
	@echo "Checking production dependencies..."
	@if $(RUN_PY) -c "import pydantic, mcp, uvicorn" >/dev/null 2>&1; then \
	  echo '✓ Dependencies already installed.'; \
	else \
	  echo '→ Installing production dependencies...'; \
	  $(INSTALL_PROD); \
	fi

##@ Development
run: start ## Run the MCP SSE server (alias)

start: install ## Start the MCP server (SSE transport) on $(MCP_HOST):$(MCP_PORT)
	@echo "[mcp] Starting SSE server on $(MCP_HOST):$(MCP_PORT) ..."
	@MCP_LOG_LEVEL="$${MCP_LOG_LEVEL:-INFO}" $(RUN_PY) -c "import asyncio; \
from medical_mcp_toolkit.mcp_server import run_mcp_async; \
print('[mcp] running SSE...'); \
asyncio.run(run_mcp_async('sse', host='$(MCP_HOST)', port=$(MCP_PORT)))"

start-stdio: install ## Start the MCP server (STDIO transport)
	@echo "[mcp] Starting STDIO server ..."
	@MCP_LOG_LEVEL="$${MCP_LOG_LEVEL:-INFO}" $(RUN_PY) -c "import asyncio; \
from medical_mcp_toolkit.mcp_server import run_mcp_async; \
print('[mcp] running STDIO...'); \
asyncio.run(run_mcp_async('stdio'))"

##@ Client / Quick checks
test-client: install ## Start a temp SSE server on a free port and run the quick client (list-tools)
	@CLIENT_TIMEOUT="30" LOG_FILE="$(SERVER_LOG)" PID_FILE="$(SERVER_PID)" \
	bash scripts/mcp_quick_client.sh

logs: ## Tail the background server logs (.run/server.log)
	@echo "Tailing $(SERVER_LOG) (Ctrl+C to stop)..."
	@mkdir -p $(RUN_DIR); touch $(SERVER_LOG)
	@tail -f $(SERVER_LOG)

stop-server: ## Stop the temporary background server started by test-client
	@if [ -f "$(SERVER_PID)" ]; then \
	  PID=$$(cat $(SERVER_PID)); echo "[mcp] Stopping server PID $$PID ..."; \
	  kill $$PID >/dev/null 2>&1 || true; rm -f $(SERVER_PID); echo "✓ Stopped."; \
	else echo "No PID file at $(SERVER_PID). Nothing to stop."; fi

##@ Quality & Testing
fmt: ## Format code (ruff + black)
	$(RUN_RUFF) check --fix .
	$(RUN_BLACK) .

lint: ## Lint the codebase (ruff)
	$(RUN_RUFF) check .

test: ## Run unit tests (pytest)
	$(RUN_PYTEST) -q

##@ Docker
docker-build: ## Build the Docker image
	@docker build -t $(IMAGE_NAME):latest .

docker-run: ## Run the containerized MCP SSE server
	@echo "Stopping any existing container named $(CONTAINER_NAME)..."; \
	docker stop $(CONTAINER_NAME) >/dev/null 2>&1 || true; \
	echo "Starting container $(CONTAINER_NAME) in detached mode..."; \
	docker run -d --rm --name $(CONTAINER_NAME) -p 9090:9090 \
	  -e MCP_LOG_LEVEL=$${MCP_LOG_LEVEL:-INFO} \
	  $(IMAGE_NAME):latest \
	  sh -lc "python -c 'import asyncio; \
from medical_mcp_toolkit.mcp_server import run_mcp_async; \
print(\"[mcp] container SSE...\"); \
asyncio.run(run_mcp_async(\"sse\", host=\"0.0.0.0\", port=9090))'"
	@echo "✓ Container is running. Use 'make docker-logs' or 'make docker-stop'."

docker-logs: ## View logs from the running Docker container
	@echo "Following logs for $(CONTAINER_NAME). Press Ctrl+C to exit."
	@docker logs -f $(CONTAINER_NAME)

docker-stop: ## Stop the running Docker container
	@echo "Stopping container $(CONTAINER_NAME)..."
	@docker stop $(CONTAINER_NAME)

##@ Housekeeping
clean: ## Remove virtual env, caches, and runtime artifacts
	@echo "Cleaning up..."
	@rm -rf $(VENV_DIR) .pytest_cache .ruff_cache $(RUN_DIR)
	@find . -type f -name '*.pyc' -delete
	@find . -type d -name '__pycache__' -delete
