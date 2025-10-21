# src/medical_mcp_toolkit/tools/triage_tools.py
from __future__ import annotations

"""
Symptom triage utilities.

- Returns enum-aware acuity levels aligned with DB enum (EMERGENT/URGENT/ROUTINE).
- Adds clear rules and next steps; safe defaults for low acuity.
"""

from typing import List, Dict, Any

from ..models.components import TriageResult, KBHit, AcuityLevel, SexEnum


def triageSymptoms(
    age: int, sex: str | SexEnum, symptoms: List[str], duration_text: str | None = None
) -> TriageResult:
    """
    Lightweight rule-based triage:
      - Chest pain + diaphoresis/sweating -> EMERGENT
      - Chest pain alone -> URGENT
      - Otherwise -> ROUTINE
    """
    s = {x.strip().lower() for x in symptoms}
    rules: List[str] = []
    next_steps: List[str] = []

    acuity = AcuityLevel.ROUTINE
    advice = "self-care"

    has_chest_pain = "chest pain" in s
    has_diaphoresis = "diaphoresis" in s or "sweating" in s
    has_shortness_of_breath = "shortness of breath" in s or "dyspnea" in s

    if has_chest_pain and has_diaphoresis:
        acuity = AcuityLevel.EMERGENT
        advice = "Call emergency services"
        rules = ["chest pain", "diaphoresis"]
        next_steps = ["ECG", "Troponin", "Aspirin if not contraindicated"]
    elif has_chest_pain or has_shortness_of_breath:
        acuity = AcuityLevel.URGENT
        advice = "Seek urgent evaluation"
        matched = ["chest pain"] if has_chest_pain else []
        if has_shortness_of_breath:
            matched.append("shortness of breath")
        rules = matched
        next_steps = ["ECG", "Vitals", "Pulse oximetry"]

    return TriageResult(acuity=acuity, advice=advice, rulesMatched=rules, nextSteps=next_steps)


def searchMedicalKB(query: str, limit: int = 3) -> Dict[str, List[KBHit]]:
    """
    Return a few deterministic, high-signal KB hits (demo-only).
    Swap this with a real search connector as needed.
    """
    hits = [
        KBHit(
            title="Chest Pain Initial Evaluation",
            url="https://kb.example/chest-pain",
            score=0.92,
            snippet="Assess ACS risk, ECG within 10 minutes.",
        ),
        KBHit(
            title="Hypertension Management",
            url="https://kb.example/htn",
            score=0.83,
            snippet="Start ACE inhibitor or ARB unless contraindicated.",
        ),
        KBHit(
            title="Diabetes Screening",
            url="https://kb.example/dm2",
            score=0.71,
            snippet="ADA recommendations for screening and A1c targets.",
        ),
    ][: max(0, int(limit))]
    return {"hits": hits}


__all__ = ["triageSymptoms", "searchMedicalKB"]
