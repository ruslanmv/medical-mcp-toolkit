# src/medical_mcp_toolkit/tools/patient_tools.py
from __future__ import annotations

"""
Patient-facing helpers.

- Updated to match the new VitalSigns field names and enums.
- Adds a safe Cockcroft–Gault calculator.
- Provides an async helper to link a patient to a user using the new patient_users PK.
"""

from typing import Optional
from datetime import datetime

from ..models.components import (
    Patient,
    VitalSigns,
    MedicalProfile,
    ClinicalCalcOutput,
    SexEnum,
    PatientUserRole,
)
from ..store import pg as db  # async helpers (optional use)


def getPatient(
    patient_id: Optional[str] = None,
    name: str = "John Doe",
    age: int = 45,
    sex: str | SexEnum = SexEnum.male,
) -> Patient:
    """
    Return a lightweight Patient model (demo/defaults).
    """
    pid = patient_id or "PT-0001"
    sex_enum = SexEnum(str(sex)) if not isinstance(sex, SexEnum) else sex
    return Patient(patient_id=pid, name=name, age=age, sex=sex_enum)


def getPatientVitals(patient_id: Optional[str] = None) -> VitalSigns:
    """
    Return demo vitals that align with the updated DB schema.
    """
    return VitalSigns(
        heart_rate_bpm=88,
        systolic_mmhg=132,
        diastolic_mmhg=84,
        resp_rate_min=16,
        temperature_c=36.9,
        spo2_percent=98,
        weight_kg=82.0,
        height_cm=178.0,
        bmi=round(82.0 / (1.78**2), 2),
        serum_creatinine=1.0,
        egfr_ml_min_1_73m2=85.0,
        timestamp_utc=datetime.utcnow(),
    )


def getPatientMedicalProfile(patient_id: Optional[str] = None) -> MedicalProfile:
    """
    Return a minimal profile with common fields.
    """
    return MedicalProfile(
        conditions=["hypertension"],
        allergies=["penicillin"],
        medications=["lisinopril 10 mg daily"],
    )


def calcClinicalScores(
    age: int,
    sex: str | SexEnum,
    weight_kg: float,
    height_cm: float,
    serum_creatinine_mg_dl: float,
) -> ClinicalCalcOutput:
    """
    Compute BMI, Mosteller BSA, Cockcroft–Gault CrCl, and a simple eGFR proxy.
    NOTE: Demo only. Not for clinical use.
    """
    sex_enum = SexEnum(str(sex)) if not isinstance(sex, SexEnum) else sex

    # BMI
    height_m = height_cm / 100.0
    bmi = weight_kg / (height_m**2) if height_m > 0 else 0.0

    # BSA (Mosteller)
    bsa = ((height_cm * weight_kg) / 3600.0) ** 0.5

    # Cockcroft–Gault CrCl (mL/min)
    crcl = ((140 - age) * weight_kg) / (72.0 * max(serum_creatinine_mg_dl, 0.1))
    if sex_enum == SexEnum.female:
        crcl *= 0.85

    # Simple eGFR proxy (demo: reuse CrCl)
    egfr = crcl

    return ClinicalCalcOutput(
        bmi=round(bmi, 2),
        bsa_m2=round(bsa, 2),
        creatinine_clearance_ml_min=round(crcl, 1),
        egfr_ml_min_1_73m2=round(egfr, 1),
        notes=["Demo calculations; not for clinical use."],
    )


# -----------------------------------------------------------------------------
# Optional async helper to link patient <-> user via DB (new PK on patient_users)
# -----------------------------------------------------------------------------
async def linkPatientToUser_async(
    patient_id: str, user_id: str, role: PatientUserRole = PatientUserRole.OWNER
) -> dict:
    """
    Link a patient to a user using the DB unique (patient_id, user_id) pair.
    Returns the patient_users row.
    """
    return await db.link_patient_user(
        patient_id=patient_id,
        user_id=user_id,
        role=role.value if isinstance(role, PatientUserRole) else str(role),
    )


__all__ = [
    "getPatient",
    "getPatientVitals",
    "getPatientMedicalProfile",
    "calcClinicalScores",
    "linkPatientToUser_async",
]
