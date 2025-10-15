# Installation & Production Setup Guide — *medical-mcp-toolkit*

Production-ready **MCP-style** server that exposes clinical tools for **IBM watsonx Orchestrate** agents, with an HTTP shim, SSE/STDIO transports, and a PostgreSQL backend.

---

## 0) Prerequisites

**OS:** Linux / macOS / Windows 10+
**You’ll need:**

* **Docker** (and Docker Desktop on macOS/Windows)
* **Make** (GNU Make; optional on Windows if you use the provided commands directly)
* **Python 3.11** (exact)
* **uv** package manager (recommended) — [https://docs.astral.sh/uv/](https://docs.astral.sh/uv/)

> If you don’t have `uv`, the Makefile can help install/sync; see `make check-uv`.

---

## 1) Clone & Configure

```bash
git clone https://github.com/ruslanmv/medical-mcp-toolkit
cd medical-mcp-toolkit
cp .env.example .env
```

Open `.env` and set:

```ini
BEARER_TOKEN=dev-token
DATABASE_URL="postgresql://mcp_user:mcp_password@localhost:5432/medical_db"
MCP_LOG_LEVEL=INFO
```

**Tips**

* Generate a strong token: `openssl rand -hex 32`
* For production, consider an external/managed PostgreSQL and update `DATABASE_URL`.

---

## 2) Database (Dockerized Postgres)

This repo ships a hardened schema and demo seed. You can spin up the database two ways.

### Option A: Makefile (recommended)

```bash
make db-up     # builds image and starts container: medical-db-container
# Helpers:
make db-logs   # tail logs
make db-down   # stop & remove the db container
make db-reset  # recreate container (fresh DB)
```

### Option B: Script

```bash
./scripts/create_db.sh
```

### (Production) Persistent Storage

For real deployments, mount a **named volume** so data persists across container restarts:

```bash
docker volume create medical_db_data
docker run -d --name medical-db-container \
  -e POSTGRES_USER=mcp_user \
  -e POSTGRES_PASSWORD=mcp_password \
  -e POSTGRES_DB=medical_db \
  -p 5432:5432 \
  -v medical_db_data:/var/lib/postgresql/data \
  medical-db
```

> Or use a managed Postgres service (preferred in regulated environments).

---

## 3) Verify Database Health

Use the bundled schema inspector:

```bash
./scripts/db_schema_check.sh
```

**What you should see (excerpt):**

```
🔌 Connecting to container: medical-db-container
----------------------------------------------------------------
You are connected to database "medical_db" as user "mcp_user" ...
...
📑 Tables in schema 'public'
 appointments
 auth_sessions
 conditions
 documents
 drug_interactions
 drugs
 encounter_notes
 encounters
 patients
 patient_users
 ...
🎨 ENUM types
 public | sex: male, female, intersex, other, unknown
 ...
📋 Column details + row counts
▶ public.patients
 ordinal_position | column_name   | data_type | is_nullable | column_default
 ...
 table_name | size  | est_rows
 patients   | 64 kB | 2
```

If any table is missing, check `docker logs -f medical-db-container` for SQL errors.

---

## 4) Install Python Dependencies

We use an **uv-first** workflow. This will create `.venv` and sync all dependencies.

```bash
make install      # or: make uv-install
```

**Windows note:** Make sure `py -3.11` is installed and on PATH (the Makefile auto-detects).

---

## 5) Run the HTTP API (FastAPI)

```bash
# dev/prod alike (ensure BEARER_TOKEN is set)
uv run uvicorn server:app --host 0.0.0.0 --port 9090 --proxy-headers
```

Or via Makefile:

```bash
make run-api
```

**Expected startup logs (example):**

```
INFO:     Started server process [23217]
INFO:     Waiting for application startup.
2025-10-15 12:16:46,272 INFO [mcp_server] [registry] 12 tools registered: calcClinicalScores, ...
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:9090 (Press CTRL+C to quit)
```

---

## 6) Health & Smoke Tests

### Health (plain text)

```bash
curl -sS http://localhost:9090/health | jq -R .
# "ok"
```

### List tools (auth)

```bash
curl -sS "http://localhost:9090/tools" \
  -H "Authorization: Bearer $BEARER_TOKEN" | jq
```

### Invoke a tool

```bash
curl -sS -X POST "http://localhost:9090/invoke" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "tool": "triageSymptoms",
    "args": { "age": 45, "sex": "male",
              "symptoms": ["chest pain","sweating"],
              "duration_text": "2 hours" }
  }' | jq
```

**Expected JSON (example):**

```json
{
  "ok": true,
  "tool": "triageSymptoms",
  "result": {
    "acuity": "urgent",
    "advice": "call emergency services",
    "rulesMatched": ["chest pain", "diaphoresis"],
    "nextSteps": ["ECG", "troponin", "aspirin if not contraindicated"]
  }
}
```

---

## 7) Run MCP Transports (SSE / STDIO)

The same tool registry is exposed via MCP. You can run either transport.

### SSE transport (port 9090)

```bash
uv run python -c "import asyncio; \
from medical_mcp_toolkit.mcp_server import run_mcp_async; \
asyncio.run(run_mcp_async('sse', host='0.0.0.0', port=9090))"
```

### STDIO transport

```bash
uv run python -c "import asyncio; \
from medical_mcp_toolkit.mcp_server import run_mcp_async; \
asyncio.run(run_mcp_async('stdio'))"
```

> Note: The **HTTP API** above (`/invoke`) is served by `uvicorn server:app`.
> The **SSE/STDIO** runner is separate.

### SSE Quick Demo (curl JSON-RPC)

```bash
# This script will negotiate the SSE writer URL and issue JSON-RPC calls
./scripts/mcp_curl_demo.sh
```

**What to expect (excerpt):**

```
→ Opening SSE at http://localhost:9090/sse to get session writer URL...
✅ SSE writer URL: http://localhost:9090/sse/messages
→ JSON-RPC: initialize
{
  "jsonrpc": "2.0",
  "id": 0,
  "result": { "protocolVersion": "2024-11-05", ... }
}
→ JSON-RPC: tools/list
{ "jsonrpc":"2.0", "id":1, "result": { "tools":[{"name":"triageSymptoms"}, ...]}}
→ JSON-RPC: tools/call triageSymptoms
{ "jsonrpc":"2.0", "id":2, "result": { ... } }
✅ Done.
```

---

## 8) Dockerizing the App

Build and run the **application** container:

```bash
make docker-build
BEARER_TOKEN=prod-secret make docker-run
# Exposes :9090 on localhost
```

Logs & stop:

```bash
make docker-logs
make docker-stop
```

> For production: run behind a reverse proxy (Nginx/Traefik) with TLS.

---

## 9) Production Hardening

### Reverse Proxy (Nginx, sample)

```
server {
  listen 443 ssl http2;
  server_name mcp.example.com;

  ssl_certificate     /etc/ssl/certs/fullchain.pem;
  ssl_certificate_key /etc/ssl/private/privkey.pem;

  location / {
    proxy_pass http://127.0.0.1:9090;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
```

### Systemd Unit (example)

`/etc/systemd/system/medical-mcp.service`:

```
[Unit]
Description=Medical MCP HTTP API
After=network.target

[Service]
Environment="BEARER_TOKEN=prod-long-random-secret"
Environment="DATABASE_URL=postgresql://mcp_user:mcp_password@127.0.0.1:5432/medical_db"
Environment="MCP_LOG_LEVEL=INFO"
WorkingDirectory=/opt/medical-mcp-toolkit
ExecStart=/opt/medical-mcp-toolkit/.venv/bin/uvicorn server:app --host 127.0.0.1 --port 9090 --proxy-headers
Restart=on-failure
User=www-data
Group=www-data

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now medical-mcp
```

### Security Notes

* Set **strong** `BEARER_TOKEN` and rotate periodically.
* Terminate TLS at a reverse proxy; do not expose plain HTTP to the internet.
* Lock down DB access (network ACLs, strong passwords, use managed DB if possible).
* The DB schema includes **CITEXT** emails, **hashed credentials**, **sessions**, and **password reset tokens** (hash-only).

---

## 10) Database Backups & Migrations

**Back up (logical):**

```bash
docker exec -i medical-db-container \
  pg_dump -U mcp_user -d medical_db -F c -Z 6 > backup_$(date +%Y%m%d).dump
```

**Restore:**

```bash
docker exec -i medical-db-container \
  pg_restore -U mcp_user -d medical_db --clean --if-exists < backup_20250101.dump
```

**Migrations:** This project uses versioned SQL (`db/10_init.sql`, `db/20_seed.sql`).
For production changes, create new files (e.g., `db/30_add_feature.sql`) and apply via CI/CD.

---

## 11) Observability & Ops

* **App logs:** `make docker-logs` or your process manager logs.
* **DB logs:** `make db-logs`
* **Port check:** `ss -ltnp | grep 9090` (Linux) / `lsof -i :9090` (macOS)
* **Health probe:** `GET /health` returns `ok` (text/plain)

---

## 12) Postman Collection (Optional)

Import `postman/medical-mcp-toolkit.postman_collection.json`.
Set:

* `baseUrl` → `http://localhost:9090`
* `token` → your bearer token

---

## 13) Environment Variables

| Variable            | Description                 | Default                                                        |
| ------------------- | --------------------------- | -------------------------------------------------------------- |
| `BEARER_TOKEN`      | Secret for HTTP API auth    | `dev-token` (set your own for prod)                            |
| `DATABASE_URL`      | PostgreSQL DSN              | `postgresql://mcp_user:mcp_password@localhost:5432/medical_db` |
| `MCP_LOG_LEVEL`     | Log level for MCP internals | `INFO`                                                         |
| `UVICORN_LOG_LEVEL` | Log level for Uvicorn       | `info`                                                         |

---

## 14) Troubleshooting

* **`401 Unauthorized` on `/tools` or `/invoke`:**
  Ensure `BEARER_TOKEN` is set in the server **and** you send `Authorization: Bearer ...`.

* **`jq` parse error on `/health`:**
  `/health` returns **text/plain**. Use:
  `curl -sS http://localhost:9090/health | jq -R .`

* **Tables missing after `db-up`:**
  Inspect DB logs: `make db-logs`. Look for SQL errors in `db/10_init.sql`.

* **SSE vs HTTP confusion:**
  SSE/STDIO runner does **not** serve `/invoke`. Use `uvicorn server:app` for HTTP API.

* **Port already in use (9090):**
  Find the process and stop it, or change the port when launching.

---

## 15) What You Get After Setup

* A **running PostgreSQL** with production schema: users/auth, patients, encounters, vitals, drugs, interactions, appointments, documents, audit.
* A **FastAPI HTTP service** on port `9090` exposing:

  * `GET /health` (text `ok`)
  * `GET /tools` (auth) — list of 12 tools
  * `GET /schema` (auth) — JSON schema for tool contracts
  * `POST /invoke` (auth) — execute a tool
* An **MCP-compatible** runtime you can drive via SSE or STDIO for multi-agent systems.

---

## 16) Next Steps

* Wire the HTTP API or MCP SSE to **IBM watsonx Orchestrate** agents.
* Replace demo adapters with **real EHR/Drug-DB/KB/Scheduling systems** behind the stable Pydantic/JSON contracts.
* Add dashboards or a web portal leveraging the **users/auth** tables provided.


