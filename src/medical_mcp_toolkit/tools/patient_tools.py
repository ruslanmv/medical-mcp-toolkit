from __future__ import annotations
from typing import Optional
from ..models.components import (
    Patient, VitalSigns, MedicalProfile, ClinicalCalcOutput
)

def getPatient(patient_id: Optional[str] = None, name: str = "John Doe", age: int = 45, sex: str = "male") -> Patient:
    pid = patient_id or "PT-0001"
    return Patient(patient_id=pid, name=name, age=age, sex=sex)

def getPatientVitals(patient_id: Optional[str] = None) -> VitalSigns:
    # demo vitals
    return VitalSigns(
        heart_rate_bpm=88, systolic_bp_mmHg=132, diastolic_bp_mmHg=84,
        respiratory_rate_bpm=16, temperature_c=36.9, spo2_percent=98
    )

def getPatientMedicalProfile(patient_id: Optional[str] = None) -> MedicalProfile:
    return MedicalProfile(
        conditions=["hypertension"],
        allergies=["penicillin"],
        medications=["lisinopril 10 mg daily"]
    )

def calcClinicalScores(
    age: int, sex: str, weight_kg: float, height_cm: float, serum_creatinine_mg_dl: float
) -> ClinicalCalcOutput:
    # BMI
    height_m = height_cm / 100.0
    bmi = weight_kg / (height_m ** 2) if height_m > 0 else 0.0

    # BSA (Mosteller)
    bsa = ((height_cm * weight_kg) / 3600.0) ** 0.5

    # Cockcroft–Gault CrCl
    crcl = ((140 - age) * weight_kg) / (72.0 * serum_creatinine_mg_dl)
    if sex.lower().startswith("f"):
        crcl *= 0.85

    # Simple eGFR proxy (not for clinical use)
    egfr = crcl  # demo: reuse

    return ClinicalCalcOutput(
        bmi=round(bmi, 2),
        bsa_m2=round(bsa, 2),
        creatinine_clearance_ml_min=round(crcl, 1),
        egfr_ml_min_1_73m2=round(egfr, 1),
        notes=["Demo calculations; not for clinical use."]
    )
