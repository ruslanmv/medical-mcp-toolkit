# src/medical_mcp_toolkit/data/demo_data.py
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Dict, List, Tuple

from ..models.components import (
    AlternativeTreatment,
    AppointmentRequest,
    DrugInformation,
    InteractionSeverity,
    KBHit,
    MedicalProfile,
    Medication,
    Patient,
    PatientContext,
    Patient360,
    Condition,
    Allergy,
    VitalSigns,
)

# ------------------------------------------------------------------------------
# Patients, Profiles, Vitals (in-memory demo)
# ------------------------------------------------------------------------------
PATIENTS: Dict[str, Patient] = {
    "demo-001": Patient(patient_id="demo-001", age=45, sex="male"),
    "demo-002": Patient(patient_id="demo-002", age=72, sex="female", pregnant=False),
}

PROFILES: Dict[str, MedicalProfile] = {
    "demo-001": MedicalProfile(
        conditions=[Condition(name="Hypertension", code="I10")],
        allergies=[Allergy(substance="penicillin", reaction="rash", severity="mild")],
        medications=[
            Medication(drug_name="lisinopril", dose="10 mg", route="oral", frequency="daily"),
        ],
    ),
    "demo-002": MedicalProfile(
        conditions=[Condition(name="Osteoarthritis")],
        allergies=[],
        medications=[
            Medication(drug_name="warfarin", dose="5 mg", route="oral", frequency="daily"),
        ],
    ),
}

def _iso(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat()

_now = datetime.now(timezone.utc)

VITALS: Dict[str, VitalSigns] = {
    "demo-001": VitalSigns(
        timestamp_iso=_iso(_now - timedelta(hours=1)),
        systolic_mmHg=162,
        diastolic_mmHg=98,
        heart_rate_bpm=88,
        resp_rate_min=18,
        temperature_c=36.8,
        spo2_percent=97.0,
        weight_kg=82,
        height_cm=178,
        bmi=25.9,
    ),
    "demo-002": VitalSigns(
        timestamp_iso=_iso(_now - timedelta(days=1)),
        systolic_mmHg=128,
        diastolic_mmHg=78,
        heart_rate_bpm=72,
        resp_rate_min=16,
        temperature_c=36.7,
        spo2_percent=98.0,
        weight_kg=64,
        height_cm=162,
        bmi=24.4,
    ),
}

# ------------------------------------------------------------------------------
# Drug DB (minimal monographs)
# ------------------------------------------------------------------------------
DRUG_DB: Dict[str, DrugInformation] = {
    "ibuprofen": DrugInformation(
        drug_name="ibuprofen",
        brand_names=["Advil", "Motrin"],
        drug_class="NSAID",
        mechanism="Non-selective COX inhibitor; analgesic and anti-inflammatory",
        atc_codes=["M01AE01"],
        indications=["pain", "fever", "inflammation"],
        contraindications=["Active GI bleed"],
        warnings=["Use caution in renal or hepatic impairment"],
        pregnancy_category="C",
        lactation="Compatible with breastfeeding; monitor infant for GI upset",
        renal_adjustment="Avoid in severe renal impairment",
        hepatic_adjustment="Use with caution",
        common_adverse_effects=["dyspepsia", "nausea", "headache"],
        serious_adverse_effects=["GI bleeding", "renal failure"],
        references=["https://www.ncbi.nlm.nih.gov/books/NBK547742/"],
    ),
    "warfarin": DrugInformation(
        drug_name="warfarin",
        brand_names=["Coumadin"],
        drug_class="Vitamin K antagonist anticoagulant",
        mechanism="Inhibits vitamin K epoxide reductase complex 1",
        atc_codes=["B01AA03"],
        indications=["thromboembolism prevention"],
        contraindications=["Pregnancy (X)", "Hemorrhagic tendencies"],
        warnings=["Many drug-drug and diet interactions"],
        pregnancy_category="X",
        lactation="Use with caution; monitor infant",
        renal_adjustment="No adjustment; monitor INR closely",
        hepatic_adjustment="Use with caution",
        common_adverse_effects=["bleeding", "bruising"],
        serious_adverse_effects=["major bleeding"],
        references=["https://www.ncbi.nlm.nih.gov/books/NBK470313/"],
    ),
    "lisinopril": DrugInformation(
        drug_name="lisinopril",
        brand_names=["Prinivil", "Zestril"],
        drug_class="ACE inhibitor",
        mechanism="Inhibits ACE; reduces angiotensin II",
        atc_codes=["C09AA03"],
        indications=["hypertension", "heart failure"],
        contraindications=["History of angioedema related to previous ACE inhibitor treatment"],
        warnings=["Hyperkalemia risk, renal dysfunction"],
        pregnancy_category="D",
        lactation="Use with caution",
        renal_adjustment="Adjust dose based on renal function",
        hepatic_adjustment="No adjustment",
        common_adverse_effects=["cough", "dizziness"],
        serious_adverse_effects=["angioedema", "renal failure"],
        references=["https://www.ncbi.nlm.nih.gov/books/NBK482230/"],
    ),
}

# ------------------------------------------------------------------------------
# Interaction DB (pairwise)
# ------------------------------------------------------------------------------
# Use canonical sorted tuple keys: (drug_a, drug_b) in lowercase
INTERACTION_DB: Dict[Tuple[str, str], Dict] = {
    tuple(sorted(("ibuprofen", "warfarin"))): {
        "severity": InteractionSeverity.major,
        "mechanism": "Additive anticoagulant/platelet inhibition → bleeding risk",
        "clinical_effect": "Increased INR/bleeding risk",
        "management": "Avoid combination; if necessary, close INR monitoring",
        "references": ["https://reference.medscape.com/drug-interactionchecker"],
    },
    tuple(sorted(("ibuprofen", "lisinopril"))): {
        "severity": InteractionSeverity.moderate,
        "mechanism": "NSAIDs may reduce antihypertensive effect and impair renal function",
        "clinical_effect": "Attenuated BP control; risk of AKI",
        "management": "Monitor BP and renal function; use lowest effective NSAID dose",
        "references": ["https://reference.medscape.com/drug-interactionchecker"],
    },
}

# ------------------------------------------------------------------------------
# Contraindication rules (demo)
# ------------------------------------------------------------------------------
# Each rule is a dict with:
#  - type: 'absolute' | 'relative'
#  - cond: callable(PatientContext) -> bool
#  - reason: str
#  - severity: InteractionSeverity
def _has_severe_renal(ctx: PatientContext) -> bool:
    return (ctx.renal_impairment_stage or "none") in {"severe", "dialysis"}


def _elderly(ctx: PatientContext) -> bool:
    return ctx.age >= 65


CONTRAINDICATION_RULES = {
    "ibuprofen": [
        {
            "type": "absolute",
            "cond": _has_severe_renal,
            "reason": "Severe renal impairment/dialysis",
            "severity": InteractionSeverity.contraindicated,
        },
        {
            "type": "relative",
            "cond": _elderly,
            "reason": "Elderly — higher risk of GI/renal adverse events",
            "severity": InteractionSeverity.moderate,
        },
    ],
    "warfarin": [
        {
            "type": "absolute",
            "cond": lambda ctx: bool(ctx.pregnant),
            "reason": "Pregnancy (Category X)",
            "severity": InteractionSeverity.contraindicated,
        }
    ],
}

# ------------------------------------------------------------------------------
# Alternatives DB
# ------------------------------------------------------------------------------
ALTERNATIVES_DB: Dict[str, List[AlternativeTreatment]] = {
    "pain": [
        AlternativeTreatment(
            drug_name="acetaminophen",
            rationale="First-line analgesic with lower GI/renal risk than NSAIDs",
            notes="Avoid overdose; max daily dose per local guidelines",
            suitability=["first-line", "OTC"],
            references=["https://www.ncbi.nlm.nih.gov/books/NBK482369/"],
        ),
        AlternativeTreatment(
            drug_name="topical diclofenac",
            rationale="Topical NSAID reduces systemic exposure",
            notes="Useful for localized musculoskeletal pain",
            suitability=["adjunct", "localized pain"],
            references=["https://www.ncbi.nlm.nih.gov/books/NBK554476/"],
        ),
    ],
    "hypertension": [
        AlternativeTreatment(
            drug_name="amlodipine",
            rationale="Calcium channel blocker alternative to ACEI/ARB",
            suitability=["first-line (per context)"],
            references=[],
        )
    ],
}

# ------------------------------------------------------------------------------
# Knowledge base documents (toy)
# ------------------------------------------------------------------------------
KB_DOCS: List[KBHit] = [
    KBHit(
        title="Chest pain red flags and immediate actions",
        snippet="Severe chest pain, hypotension, hypoxia, or diaphoresis warrant emergency evaluation.",
        score=0.99,
        source_url="https://example.org/guidelines/chest-pain-red-flags",
    ),
    KBHit(
        title="Hypertension: initial management",
        snippet="For BP >=160/100 consider dual therapy and urgent assessment of end-organ damage.",
        score=0.85,
        source_url="https://example.org/guidelines/hypertension-initial",
    ),
    KBHit(
        title="NSAID safety profile",
        snippet="Ibuprofen increases bleeding risk with anticoagulants; monitor or avoid.",
        score=0.8,
        source_url="https://example.org/drugs/nsaids-safety",
    ),
]

# ------------------------------------------------------------------------------
# Appointment slots (toy)
# ------------------------------------------------------------------------------
APPOINTMENT_SLOTS = [
    {
        "id": "slot-001",
        "specialty": "cardiology",
        "start_iso": _iso(_now + timedelta(days=1, hours=9)),
        "end_iso": _iso(_now + timedelta(days=1, hours=10)),
        "provider": "Dr. Rivera",
        "location": "Main Hospital - Cardiology",
    },
    {
        "id": "slot-002",
        "specialty": "general medicine",
        "start_iso": _iso(_now + timedelta(days=2, hours=14)),
        "end_iso": _iso(_now + timedelta(days=2, hours=14, minutes=30)),
        "provider": "Dr. Patel",
        "location": "Outpatient Clinic - GM",
    },
    {
        "id": "slot-003",
        "specialty": "endocrinology",
        "start_iso": _iso(_now + timedelta(days=3, hours=11)),
        "end_iso": _iso(_now + timedelta(days=3, hours=12)),
        "provider": "Dr. Kim",
        "location": "Specialty Center - Endo",
    },
]
