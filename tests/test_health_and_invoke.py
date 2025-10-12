# tests/test_health_and_invoke.py
from __future__ import annotations

import os
import sys
from pathlib import Path

from fastapi.testclient import TestClient

# Ensure repo root is on sys.path so "server" can be imported if present
ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

try:
    # Prefer the top-level module if available (supports `uvicorn server:app`)
    from server import app  # type: ignore
except ModuleNotFoundError:
    # Fallback to the package-native app (always available from src layout)
    from medical_mcp_toolkit.http_app import app  # type: ignore

TOKEN = os.getenv("BEARER_TOKEN", "dev-token")
client = TestClient(app)


def _auth():
    return {"Authorization": f"Bearer {TOKEN}"}


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.text == "ok"


def test_tools_list():
    r = client.get("/tools", headers=_auth())
    assert r.status_code == 200
    data = r.json()
    assert "tools" in data and isinstance(data["tools"], list)
    assert "triageSymptoms" in data["tools"]


def test_invoke_triage():
    payload = {
        "tool": "triageSymptoms",
        "args": {
            "age": 45,
            "sex": "male",
            "symptoms": ["chest pain", "sweating"],
            "duration_text": "2 hours",
        },
    }
    r = client.post("/invoke", json=payload, headers=_auth())
    assert r.status_code == 200
    body = r.json()
    assert body.get("ok") is True
    assert body.get("tool") == "triageSymptoms"
    assert "result" in body
    assert body["result"]["acuity"] in {"EMERGENT", "URGENT", "ROUTINE"}
