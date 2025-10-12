# medical-mcp-toolkit

Production-ready MCP-style server that exposes clinical tools for IBM watsonx Orchestrate agents.

## Features
- 12 tools: patient, vitals, profile, clinical calculators, drug info/interactions/contraindications/alternatives, symptom triage, KB search, scheduling, patient 360.
- FastAPI HTTP endpoints: `/health`, `/schema`, `/tools`, `/invoke`.
- Bearer token authentication (set `BEARER_TOKEN`).
- Thin adapters with retries and timeouts (`httpx` + `tenacity`).
- Containerized (Dockerfile). Structured logs to stdout.

## System Context

```mermaid
graph TD
    %% === STYLES ===
    classDef agent fill:#eefaf0,stroke:#1a7f37,stroke-width:2px
    classDef tool fill:#f3e8fd,stroke:#8e44ad,stroke-width:1px
    classDef external fill:#f8f9fa,stroke:#666,stroke-width:1px,stroke-dasharray: 5 5

    %% === ORCHESTRATION AGENTS ===
    subgraph WXO[IBM watsonx Orchestrate]
        direction TB
        Coordinator[Medical Coordinator Agent]:::agent
        Triage[Emergency Triage Agent]:::agent
        GenMed[General Medicine Agent]:::agent

        subgraph Specialists
            direction LR
            Cardiology[Cardiology]:::agent
            Pediatrics[Pediatrics]:::agent
            Oncology[Oncology]:::agent
            Endocrinology[Endocrinology]:::agent
        end

        %% Agent Handoffs
        Coordinator -->|delegates| Triage
        Coordinator -->|routes| GenMed
        GenMed -->|refers| Specialists
    end

    %% === BACKEND SERVICES & TOOLS ===
    subgraph BackendServices [Backend Services]
        direction TB
        subgraph MCPToolkit[Medical MCP Toolkit]
            direction TB
            T1[getPatient]:::tool
            T2[getPatientVitals]:::tool
            T3[getPatientMedicalProfile]:::tool
            T4[calcClinicalScores]:::tool
            T5[getDrugInfo]:::tool
            T6[triageSymptoms]:::tool
            T7[searchMedicalKB]:::tool
            T8[scheduleAppointment]:::tool
        end

        subgraph ExternalRuntimes [External Runtimes]
            MCPServer[Medical MCP Server<br/>FastMCP/SSE]:::external
            WatsonxAI[watsonx.ai Foundation Models]:::external
        end
        
        MCPToolkit -.->|runtime API calls| MCPServer
        MCPServer -.->|LLM calls| WatsonxAI
    end

    %% === CONNECTIONS ===
    WXO -->|All agents use| MCPToolkit
```

**Companion Multi‑Agent Repository (Orchestrate):**
<https://github.com/ruslanmv/Medical-AI-Assistant-System>

## Quickstart (with uv)
```bash
# 1) Clone and enter the repo
cd medical-mcp-toolkit

# 2) Create venv and install deps
make install

# 3) Run the server (dev)
BEARER_TOKEN=dev-token make run
# Server on http://localhost:8080
```

## API
- `GET /health` → `ok`
- `GET /schema` (auth) → Shared JSON Schema (`schemas/components.schema.json`)
- `GET /tools` (auth) → List of registered tools
- `POST /invoke` (auth) → Invoke any tool

### Invoke example
```bash
curl -s -X POST "http://localhost:8080/invoke" \
  -H "Authorization: Bearer dev-token" \
  -H "Content-Type: application/json" \
  -d '{
    "tool": "triageSymptoms",
    "args": {
      "age": 45,
      "sex": "male",
      "symptoms": ["chest pain", "sweating"],
      "duration_text": "2 hours"
    }
  }' | jq
```

## Docker
```bash
make docker-build
BEARER_TOKEN=prod-secret make docker-run
```

## Configuration (env vars)
- `BEARER_TOKEN` — required for auth in non-dev environments
- `DRUG_API_BASE`, `DRUG_API_KEY` — drug DB adapter
- `KB_BASE` — knowledge base adapter
- `SCHED_BASE` — scheduling adapter
- `PORT`, `HOST` — server binding

## Postman Collection
A ready-to-import collection is provided in `postman/medical-mcp-toolkit.postman_collection.json` with variables `baseUrl` and `token`.

## Smoke Test
Run a full tool sweep locally:
```bash
export TOKEN=dev-token
export BASE_URL=http://localhost:8080
make smoke
```

## Notes
- The included schemas are a compact subset for brevity. For a full contract, expand `schemas/components.schema.json` to match your formal model set.
- Tools validate inputs via Pydantic; outputs are serialized to JSON.
- Replace DEMO stores in patient_tools.py with EHR integration.
