# src/medical_mcp_toolkit/tools/drug_tools.py
from __future__ import annotations

"""
Drug-related helper functions.

- Uses the updated models (DrugInformation.reference_urls).
- Defensive, production-ready defaults with clear docstrings.
- Pure functions for easy testing; can be wired to a DB-backed repository later.
"""

from typing import List
from pydantic import BaseModel

from ..models.components import (
    DrugInformation,
    InteractionSet,
    ContraindicationReport,
    AlternativeTreatment,
    MedicalProfile,
    InteractionSeverity,
)


class _DemoMonograph(BaseModel):
    name: str
    indications: List[str]
    dosage: str
    adverse_effects: List[str]
    reference_urls: List[str]


# Minimal, canned demo monographs for offline behavior
_DEMO_DRUG_DB: dict[str, _DemoMonograph] = {
    "lisinopril": _DemoMonograph(
        name="Lisinopril",
        indications=["hypertension", "heart failure"],
        dosage="10 mg orally once daily",
        adverse_effects=["cough", "hyperkalemia", "dizziness"],
        reference_urls=[
            "https://www.ncbi.nlm.nih.gov/books/NBK482230/",
            "https://www.drugs.com/lisinopril.html",
        ],
    ),
    "spironolactone": _DemoMonograph(
        name="Spironolactone",
        indications=["heart failure", "hypertension", "hyperaldosteronism"],
        dosage="25–50 mg orally once daily",
        adverse_effects=["hyperkalemia", "gynecomastia"],
        reference_urls=[
            "https://www.ncbi.nlm.nih.gov/books/NBK554421/",
            "https://www.drugs.com/spironolactone.html",
        ],
    ),
}


def _normalize(name: str) -> str:
    return name.strip().lower()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
def getDrugInfo(name: str) -> DrugInformation:
    """
    Return basic monograph information for a drug name.

    This implementation uses a small built-in demo set so it works out-of-the-box.
    In production, back this with your DB or a drug API and populate all fields.
    """
    key = _normalize(name)
    d = _DEMO_DRUG_DB.get(key)
    if not d:
        # Sensible fallback for unknown drugs
        return DrugInformation(
            name=name,
            indications=[],
            dosage="",
            adverse_effects=[],
            reference_urls=[],
        )
    return DrugInformation(
        name=d.name,
        indications=list(d.indications),
        dosage=d.dosage,
        adverse_effects=list(d.adverse_effects),
        reference_urls=list(d.reference_urls),  # ✅ updated field
    )


def getDrugInteractions(drugs: List[str]) -> InteractionSet:
    """
    Compute a coarse interaction summary for a list of drug names.

    Strategy:
      - Normalize names.
      - Apply a simple known rule for demo purposes:
            lisinopril + spironolactone -> moderate
      - Otherwise return 'none'.

    In production:
      - Resolve names -> drug IDs.
      - Query your `drug_interactions` table using LEAST/GREATEST pair logic.
      - Aggregate the worst (max) severity across all pairs.
    """
    normalized = {_normalize(x) for x in drugs}

    # Demo rule: ACE inhibitor + potassium-sparing diuretic
    if {"lisinopril", "spironolactone"}.issubset(normalized):
        desc = (
            "ACE inhibitor + potassium-sparing diuretic may increase risk of hyperkalemia."
        )
        return InteractionSet(
            interacting_drugs=drugs,
            severity=InteractionSeverity.moderate,
            description=desc,
        )

    return InteractionSet(
        interacting_drugs=drugs,
        severity=InteractionSeverity.minor,  # default, conservative
        description="No major interactions found in demo set.",
    )


def getDrugContraindications(
    drug: str, profile: MedicalProfile | None = None
) -> ContraindicationReport:
    """
    Provide a simple contraindication check using the patient's profile.

    Current demo logic:
      - If the patient lists a 'penicillin' allergy and the drug is penicillin,
        mark as 'high'.
    Extend this to map profile.conditions to each drug's contraindications list.
    """
    reasons: List[str] = []
    if profile and any(a.strip().lower() == "penicillin" for a in profile.allergies):
        if _normalize(drug) == "penicillin":
            reasons.append("Allergy to penicillin")

    severity = "high" if reasons else "none"
    return ContraindicationReport(drug=drug, reasons=reasons, severity=severity)


def getDrugAlternatives(drug: str) -> List[AlternativeTreatment]:
    """
    Suggest simple alternatives within the same therapeutic area.

    Demo rules:
      - For lisinopril, suggest losartan (ARB) and amlodipine (CCB).
      - Otherwise, return a generic guidance item.
    """
    if _normalize(drug) == "lisinopril":
        return [
            AlternativeTreatment(
                drug="Losartan", rationale="ARB alternative to ACE inhibitor."
            ),
            AlternativeTreatment(
                drug="Amlodipine", rationale="Calcium channel blocker for hypertension."
            ),
        ]
    return [
        AlternativeTreatment(
            drug="Consult formulary",
            rationale="No demo alternatives known; consult local guidelines.",
        )
    ]


__all__ = [
    "getDrugInfo",
    "getDrugInteractions",
    "getDrugContraindications",
    "getDrugAlternatives",
]
