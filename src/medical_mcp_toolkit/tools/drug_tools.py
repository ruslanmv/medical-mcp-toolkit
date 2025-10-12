from __future__ import annotations
from typing import List
from ..models.components import DrugInformation, InteractionSet, ContraindicationReport, AlternativeTreatment, MedicalProfile

def getDrugInfo(name: str) -> DrugInformation:
    return DrugInformation(
        name=name,
        indications=["hypertension"],
        dosage="10 mg orally once daily",
        adverse_effects=["cough", "hyperkalemia"]
    )

def getDrugInteractions(drugs: List[str]) -> InteractionSet:
    sev = "moderate" if {"lisinopril", "spironolactone"} <= set(map(str.lower, drugs)) else "none"
    desc = "ACE inhibitor + potassium-sparing diuretic may increase risk of hyperkalemia." if sev == "moderate" else "No major interactions found in demo set."
    return InteractionSet(interacting_drugs=drugs, severity=sev, description=desc)

def getDrugContraindications(drug: str, profile: MedicalProfile | None = None) -> ContraindicationReport:
    reasons: List[str] = []
    if profile and any(a.lower() == "penicillin" for a in profile.allergies):
        if drug.lower() == "penicillin":
            reasons.append("Allergy to penicillin")
    severity = "high" if reasons else "none"
    return ContraindicationReport(drug=drug, reasons=reasons, severity=severity)

def getDrugAlternatives(drug: str) -> List[AlternativeTreatment]:
    if drug.lower() == "lisinopril":
        return [
            AlternativeTreatment(drug="Losartan", rationale="ARB alternative to ACE inhibitor."),
            AlternativeTreatment(drug="Amlodipine", rationale="Calcium channel blocker for hypertension.")
        ]
    return [AlternativeTreatment(drug="Consult formulary", rationale="No demo alternatives known.")]
