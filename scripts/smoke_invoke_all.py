#!/usr/bin/env python
"""
scripts/smoke_invoke_all.py

Runs a quick sweep of all 12 tools via REST /invoke.
Environment:
  BASE_URL (default http://localhost:8080)
  TOKEN    (default dev-token)
"""
from __future__ import annotations

import json
import os
import sys
from typing import Any, Dict, List

import requests

BASE_URL = os.getenv("BASE_URL", "http://localhost:8080")
TOKEN = os.getenv("TOKEN", "dev-token")


def call(path: str, method="GET", **kwargs) -> requests.Response:
    headers = kwargs.pop("headers", {})
    headers["Authorization"] = f"Bearer {TOKEN}"
    if method.upper() == "GET":
        return requests.get(f"{BASE_URL}{path}", headers=headers, **kwargs)
    return requests.post(f"{BASE_URL}{path}", headers=headers, **kwargs)


def invoke(tool: str, args: Dict[str, Any]) -> Dict[str, Any]:
    r = call("/invoke", method="POST", json={"tool": tool, "args": args})
    if r.status_code != 200:
        print(f"❌ {tool} -> {r.status_code} {r.text}")
        sys.exit(1)
    data = r.json()
    print(f"✅ {tool} -> ok")
    return data


def main() -> None:
    print(f"Using BASE_URL={BASE_URL}")
    print("Checking /health ...")
    r = requests.get(f"{BASE_URL}/health")
    r.raise_for_status()
    print("OK")

    # Patient-centric
    invoke("getPatient", {"patient_id": "demo-001"})
    invoke("getPatientVitals", {"patient_id": "demo-001"})
    invoke("getPatientMedicalProfile", {"patient_id": "demo-001"})
    invoke(
        "calcClinicalScores",
        {"age": 45, "sex": "male", "weight_kg": 80, "height_cm": 178, "serum_creatinine_mg_dl": 1.0},
    )

    # Drug-centric
    invoke("getDrugInfo", {"drug_name": "ibuprofen"})
    invoke(
        "getDrugInteractions",
        {"primary_drug": "ibuprofen", "interacting_drugs": ["warfarin", "lisinopril"]},
    )
    invoke(
        "getDrugContraindications",
        {"drug_name": "ibuprofen", "context": {"age": 72, "sex": "female", "comorbidities": ["CKD"]}},
    )
    invoke("getDrugAlternatives", {"drug_name": "ibuprofen", "condition": "pain"})

    # Triage & KB
    invoke(
        "triageSymptoms",
        {"age": 45, "sex": "male", "symptoms": ["chest pain"], "duration_text": "2 hours"},
    )
    invoke("searchMedicalKB", {"query": "chest pain emergency", "top_k": 3})

    # Scheduling & 360
    invoke(
        "scheduleAppointment",
        {"patient_id": "demo-001", "specialty": "cardiology", "earliest_date": "2025-10-01"},
    )
    invoke("getPatient360", {"patient_id": "demo-001"})

    print("All tools succeeded ✅")


if __name__ == "__main__":
    main()
