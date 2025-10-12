from __future__ import annotations
from typing import List, Dict, Any
from ..models.components import TriageResult, KBHit

def triageSymptoms(age: int, sex: str, symptoms: List[str], duration_text: str | None = None) -> TriageResult:
    s = {x.lower() for x in symptoms}
    rules = []
    next_steps = []
    acuity = "routine"
    advice = "self-care"

    if "chest pain" in s and ("sweating" in s or "diaphoresis" in s):
        acuity = "urgent"
        advice = "call emergency services"
        rules = ["chest pain", "diaphoresis"]
        next_steps = ["ECG", "troponin", "aspirin if not contraindicated"]

    return TriageResult(acuity=acuity, advice=advice, rulesMatched=rules, nextSteps=next_steps)

def searchMedicalKB(query: str, limit: int = 3) -> Dict[str, List[KBHit]]:
    hits = [
        KBHit(title="Chest Pain Initial Evaluation", url="https://kb.example/chest-pain", score=0.92, snippet="Assess ACS risk, ECG within 10 minutes."),
        KBHit(title="Hypertension Management", url="https://kb.example/htn", score=0.83, snippet="Start ACE inhibitor or ARB unless contraindicated."),
        KBHit(title="Diabetes Screening", url="https://kb.example/dm2", score=0.71, snippet="ADA recommendations for screening and A1c targets.")
    ][:limit]
    return {"hits": hits}
