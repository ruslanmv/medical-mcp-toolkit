# Makefile — Cross-Platform (Windows PowerShell / Unix shells)
# Migrated to uv-first workflow for medical-mcp-toolkit

# =============================================================================
#  Configuration & Cross-Platform Setup
# =============================================================================

.DEFAULT_GOAL := uv-install

# --- User-Configurable Variables ---
PYTHON ?= python3.11
VENV   ?= .venv

# --- OS Detection for Paths and Commands ---
ifeq ($(OS),Windows_NT)
# Use the Python launcher on Windows
PYTHON      := py -3.11
# Windows settings (PowerShell-safe)
PY_SUFFIX   := .exe
BIN_DIR     := Scripts
ACTIVATE    := $(VENV)\$(BIN_DIR)\activate
# Use $$null for PowerShell redirection
NULL_DEVICE := $$null
RM          := Remove-Item -Force -ErrorAction SilentlyContinue
RMDIR       := Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
SHELL       := powershell.exe
.SHELLFLAGS := -NoProfile -ExecutionPolicy Bypass -Command
# Reference to environment variables for PowerShell
ENVREF      := $$env:
# Docker volume source for PS (use the .Path of $PWD)
MOUNT_SRC   := "$$PWD.Path"
else
# Unix/Linux/macOS settings
PY_SUFFIX   :=
BIN_DIR     := bin
ACTIVATE    := . $(VENV)/$(BIN_DIR)/activate
NULL_DEVICE := /dev/null
RM          := rm -f
RMDIR       := rm -rf
SHELL       := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
# Reference to environment variables for POSIX sh/bash
ENVREF      := $$
# Docker volume source for POSIX shells
MOUNT_SRC   := "$$(pwd)"
endif

# --- Derived Variables ---
PY_EXE  := $(VENV)/$(BIN_DIR)/python$(PY_SUFFIX)
PIP_EXE := $(VENV)/$(BIN_DIR)/pip$(PY_SUFFIX)

# =============================================================================
#  Project-Specific Config
# =============================================================================

# Docker / container config
IMAGE_NAME     ?= medical-mcp-server
CONTAINER_NAME ?= $(IMAGE_NAME)-dev

# MCP server defaults
MCP_HOST ?= 0.0.0.0
MCP_PORT ?= 9090

# Runtime files (used by some helper scripts)
RUN_DIR    ?= .run
SERVER_PID ?= $(RUN_DIR)/server.pid
SERVER_LOG ?= $(RUN_DIR)/server.log

.PHONY: help venv install dev uv-install update test lint fmt check shell clean distclean \
	clean-venv build-container run-container stop-container remove-container logs \
	check-python check-pyproject check-uv python-version \
	run start start-stdio test-client docker-build docker-run docker-logs docker-stop

# =============================================================================
#  Helper Scripts (exported env vars; expanded by the shell)
# =============================================================================

export HELP_SCRIPT
define HELP_SCRIPT
import re, sys, io
print('Usage: make <target> [OPTIONS...]\n')
print('Available targets:\n')
mf = '$(firstword $(MAKEFILE_LIST))'
with io.open(mf, 'r', encoding='utf-8', errors='ignore') as f:
	for line in f:
		m = re.match(r'^([a-zA-Z0-9_.-]+):.*?## (.*)$$', line)
		if m:
			target, help_text = m.groups()
			print('  {0:<22} {1}'.format(target, help_text))
endef

export CLEAN_SCRIPT
define CLEAN_SCRIPT
import glob, os, shutil, sys
patterns = ['*.pyc', '*.pyo', '*~', '*.egg-info', '__pycache__', 'build', 'dist', '.mypy_cache', '.pytest_cache', '.ruff_cache']
to_remove = set()
for p in patterns:
	to_remove.update(glob.glob('**/' + p, recursive=True))
for path in sorted(to_remove, key=len, reverse=True):
	try:
		if os.path.isfile(path) or os.path.islink(path):
			os.remove(path)
		elif os.path.isdir(path):
			shutil.rmtree(path)
	except OSError as e:
		print('Error removing {0}: {1}'.format(path, e), file=sys.stderr)
endef

# =============================================================================
#  Core Targets
# =============================================================================

help: ## Show this help message
ifeq ($(OS),Windows_NT)
	@& $(PYTHON) -X utf8 -c "$(ENVREF)HELP_SCRIPT"
else
	@$(PYTHON) -X utf8 -c "$(ENVREF)HELP_SCRIPT"
endif

# --- Local Python Environment ---

ifeq ($(OS),Windows_NT)
$(VENV): check-python
	@echo "Creating virtual environment at $(VENV)..."
	# Kill stray python.exe using cmd.exe to handle || operator correctly
	@& $$env:ComSpec /c "taskkill /F /IM python.exe >NUL 2>&1 || exit 0"
	@Start-Sleep -Milliseconds 300
	@if (Test-Path '$(VENV)'){ Remove-Item -Recurse -Force '$(VENV)' -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 200 }
	@& $(PYTHON) -m venv '$(VENV)'
	@& '$(VENV)\Scripts\python.exe' -m pip install --upgrade pip
	@& '$(VENV)\Scripts\python.exe' -V | % { "✅ Created $(VENV) with $$_" }
else
$(VENV): check-python
	@echo "Creating virtual environment at $(VENV)..."
	@$(PYTHON) -m venv --clear "$(VENV)" || { rm -rf "$(VENV)"; $(PYTHON) -m venv "$(VENV)"; }
	@"$(VENV)/bin/python" -m pip install --upgrade pip
	@echo "✅ Created $(VENV) with $$("$(VENV)/bin/python" -V)"
endif

venv: $(VENV) ## [pip] Create the virtual environment if it does not exist

install: uv-install ## Install project using uv (default)

dev: uv-install ## Install project in dev mode using uv (default)

pip-install: venv check-pyproject ## [pip] Install project in non-editable mode
	@$(PIP_EXE) install .
	@echo "✅ Installed project into $(VENV) using pip"

uv-install: check-pyproject ## [uv] Create venv & install all dependencies (prod+dev if requested)
ifeq ($(OS),Windows_NT)
	@echo "Syncing environment with uv..."
	@$$uvCmd = (Get-Command uv -ErrorAction SilentlyContinue); if (-not $$uvCmd) { $$uvCmd = Join-Path $$env:USERPROFILE '.local\bin\uv.exe' }; if (Test-Path $$uvCmd) { & $$uvCmd sync } else { Write-Host 'Error: uv not found. Please run `make check-uv` to install it.'; exit 1 }
	@echo "Done! To activate the environment, run:"
	@echo "   .\$(VENV)\Scripts\Activate.ps1"
else
	@echo "Syncing environment with uv..."
	@uv sync
	@echo "✅ Done! To activate the environment, run:"
	@echo "   source $(VENV)/bin/activate"
endif

update: check-pyproject ## Upgrade/sync dependencies (prefers uv; falls back to pip editable dev)
ifeq ($(OS),Windows_NT)
	@$$uvCmd = (Get-Command uv -ErrorAction SilentlyContinue); if (-not $$uvCmd) { $$uvCmd = Join-Path $$env:USERPROFILE '.local\bin\uv.exe' }; if (Test-Path $$uvCmd) { Write-Host 'Syncing with uv...'; & $$uvCmd sync } else { Write-Host 'uv not found, falling back to pip...'; if (-not (Test-Path '$(VENV)\Scripts\python.exe')) { & $(PYTHON) -m venv '$(VENV)'; & '$(VENV)\Scripts\python.exe' -m pip install -U pip }; & '$(VENV)\Scripts\python.exe' -m pip install -U -e ".[dev]"; Write-Host '✅ Project and dependencies upgraded (pip fallback)'; }
else
	@if command -v uv >$(NULL_DEVICE) 2>&1; then \
		echo "Syncing with uv..."; \
		uv sync; \
	else \
		echo "uv not found, falling back to pip..."; \
		[ -x "$(VENV)/bin/python" ] || $(PYTHON) -m venv "$(VENV)"; \
		"$(VENV)/bin/python" -m pip install -U pip; \
		"$(VENV)/bin/pip" install -U -e ".[dev]"; \
		echo "✅ Project and dependencies upgraded (pip fallback)"; \
	fi
endif

# --- Development & QA ---

test: ## Run tests with pytest
	@echo "🧪 Running tests..."
	@$(PY_EXE) -m pytest -q

lint: ## Check code style with ruff
	@echo "🔍 Linting with ruff..."
	@$(PY_EXE) -m ruff check .

fmt: ## Format code (ruff format + black)
	@echo "🎨 Formatting with ruff format..."
	@$(PY_EXE) -m ruff format .
	@echo "🖤 Formatting with black..."
	@$(PY_EXE) -m black .

check: lint test ## Run all checks (linting and testing)

# --- MCP: Run Servers ---

run: start ## Alias

start: ## Start the MCP server (SSE transport) on $(MCP_HOST):$(MCP_PORT)
	@echo "[mcp] Starting SSE server on $(MCP_HOST):$(MCP_PORT) ..."
	@$(PY_EXE) -c "import asyncio; from medical_mcp_toolkit.mcp_server import run_mcp_async; asyncio.run(run_mcp_async('sse', host='$(MCP_HOST)', port=$(MCP_PORT)))"

start-stdio: ## Start the MCP server (STDIO transport)
	@echo "[mcp] Starting STDIO server ..."
	@$(PY_EXE) -c "import asyncio; from medical_mcp_toolkit.mcp_server import run_mcp_async; asyncio.run(run_mcp_async('stdio'))"

test-client: ## Run a quick curl-based demo against a temporary SSE server
	@echo "[mcp] Running quick curl demo..."
	@bash scripts/mcp_curl_demo.sh

# --- Docker (helpers) ---

build-container: docker-build ## Alias

docker-build: ## Build the Docker image
	@docker build -t $(IMAGE_NAME):latest .

docker-run: ## Run the containerized MCP SSE server
	@echo "Stopping any existing container named $(CONTAINER_NAME)..."
	@docker stop $(CONTAINER_NAME) >$(NULL_DEVICE) 2>&1 || true
	@echo "Starting container $(CONTAINER_NAME) in detached mode..."
	@docker run -d --rm --name $(CONTAINER_NAME) -p 9090:9090 \
		-e MCP_LOG_LEVEL=$${MCP_LOG_LEVEL:-INFO} \
		$(IMAGE_NAME):latest \
		sh -lc "python -c 'import asyncio; from medical_mcp_toolkit.mcp_server import run_mcp_async; asyncio.run(run_mcp_async(\"sse\", host=\"0.0.0.0\", port=9090))'"
	@echo "✓ Container is running. Use 'make docker-logs' or 'make docker-stop'."

docker-logs: ## View logs from the running Docker container (Ctrl+C to stop)
	@docker logs -f $(CONTAINER_NAME)

docker-stop: ## Stop the running Docker container
	@echo "Stopping container $(CONTAINER_NAME)..."
	@docker stop $(CONTAINER_NAME)

# --- Utility ---

python-version: check-python ## Show resolved Python interpreter and version
ifeq ($(OS),Windows_NT)
	@echo "Using: $(PYTHON)"
	@& $(PYTHON) -V
else
	@echo "Using: $(PYTHON)"
	@$(PYTHON) -V
endif

shell: ## Show how to activate the virtual environment shell
	@echo "Virtual environment is ready."
	@echo "To activate it, run:"
	@echo "  On Windows (CMD/PowerShell): .\\$(VENV)\\Scripts\\Activate.ps1"
	@echo "  On Unix (Linux/macOS/Git Bash): source $(VENV)/bin/activate"

clean-venv: ## Force-remove the venv (kills python.exe on Windows)
ifeq ($(OS),Windows_NT)
	@& $$env:ComSpec /c "taskkill /F /IM python.exe >NUL 2>&1 || exit 0"
	@Start-Sleep -Milliseconds 300
	@if (Test-Path '.venv'){ Remove-Item -Recurse -Force '.venv' }
else
	@rm -rf .venv
endif

clean: ## Remove Python artifacts, caches, and the virtualenv
	@echo "Cleaning project..."
	-$(RMDIR) $(VENV)
	-$(RMDIR) .pytest_cache
	-$(RMDIR) .ruff_cache
ifeq ($(OS),Windows_NT)
	@& $(PYTHON) -c "$(ENVREF)CLEAN_SCRIPT"
else
	@$(PYTHON) -c "$(ENVREF)CLEAN_SCRIPT"
endif
	@echo "Clean complete."

distclean: clean ## Alias for clean

# =============================================================================
#  Internal Helper Targets
# =============================================================================

ifeq ($(OS),Windows_NT)
check-python:
	@echo "Checking for a Python 3.11 interpreter..."
	@& $(PYTHON) -c "import sys; sys.exit(0 if sys.version_info[:2]==(3,11) else 1)" 2>$(NULL_DEVICE); if ($$LASTEXITCODE -ne 0) { echo "Error: '$(PYTHON)' is not Python 3.11."; echo "Please install Python 3.11 and add it to your PATH,"; echo "or specify via: make install PYTHON='py -3.11'"; exit 1; }
	@echo "Found Python 3.11:"
	@& $(PYTHON) -V

check-pyproject:
	@if (Test-Path -LiteralPath 'pyproject.toml') { echo 'Found pyproject.toml' } else { echo ('Error: pyproject.toml not found in ' + (Get-Location)); exit 1 }

check-uv: ## Check for uv and install it if missing
	@echo "Checking for uv..."
	@$$cmd = Get-Command uv -ErrorAction SilentlyContinue; if (-not $$cmd) { echo 'Info: ''uv'' not found. Attempting to install it now...'; iwr https://astral.sh/uv/install.ps1 -UseBasicParsing | iex; $$localBin = Join-Path $$env:USERPROFILE '.local\bin'; if (Test-Path $$localBin) { $$env:Path = "$$localBin;$$env:Path" } }
	@$$cmd = Get-Command uv -ErrorAction SilentlyContinue; if (-not $$cmd) { $$candidate = Join-Path $$env:USERPROFILE '.local\bin\uv.exe'; if (Test-Path $$candidate) { echo ('Using ' + $$candidate); $$env:Path = (Split-Path $$candidate) + ';' + $$env:Path } else { echo 'Error: ''uv'' is still not available after installation.'; exit 1 } }
	@echo "✅ uv is available."
else
check-python:
	@echo "Checking for a Python 3.11 interpreter..."
	@$(PYTHON) -c "import sys; sys.exit(0 if sys.version_info[:2]==(3,11) else 1)" 2>$(NULL_DEVICE) || ( \
		echo "Error: '$(PYTHON)' is not Python 3.11."; \
		echo "Please install Python 3.11 and add it to your PATH,"; \
		echo 'or specify the command via make install PYTHON=\"py -3.11\"'; \
		exit 1; \
	)
	@echo "Found Python 3.11:"
	@$(PYTHON) -V

check-pyproject:
	@[ -f pyproject.toml ] || { echo "Error: pyproject.toml not found in $$(pwd)"; exit 1; }
	@echo "Found pyproject.toml"

check-uv: ## Check for uv and install it if missing
	@echo "Checking for uv..."
	@command -v uv >$(NULL_DEVICE) 2>&1 || ( \
		echo "Info: 'uv' not found. Attempting to install it now..."; \
		curl -LsSf https://astral.sh/uv/install.sh | sh; \
	)
	@command -v uv >$(NULL_DEVICE) 2>&1 || ( \
		echo "Error: 'uv' is still not available after installation."; \
		exit 1; \
	)
	@echo "✅ uv is available."
endif