from __future__ import annotations
from typing import List, Optional
from pydantic import BaseModel, Field
from datetime import datetime

class Patient(BaseModel):
    patient_id: str
    name: str
    age: Optional[int] = None
    sex: Optional[str] = Field(default="unknown")

class VitalSigns(BaseModel):
    heart_rate_bpm: int
    systolic_bp_mmHg: int
    diastolic_bp_mmHg: int
    respiratory_rate_bpm: int
    temperature_c: float
    spo2_percent: int
    timestamp_iso: str = Field(default_factory=lambda: datetime.utcnow().isoformat())

class MedicalProfile(BaseModel):
    conditions: List[str] = []
    allergies: List[str] = []
    medications: List[str] = []

class ClinicalCalcInput(BaseModel):
    age: int
    sex: str
    weight_kg: float
    height_cm: float
    serum_creatinine_mg_dl: float

class ClinicalCalcOutput(BaseModel):
    bmi: float
    bsa_m2: float
    creatinine_clearance_ml_min: float
    egfr_ml_min_1_73m2: float
    notes: List[str] = []

class DrugInformation(BaseModel):
    name: str
    indications: List[str] = []
    dosage: str = ""
    adverse_effects: List[str] = []

class InteractionSet(BaseModel):
    interacting_drugs: List[str] = []
    severity: str = "none"
    description: str = ""

class ContraindicationReport(BaseModel):
    drug: str
    reasons: List[str] = []
    severity: str = "none"

class AlternativeTreatment(BaseModel):
    drug: str
    rationale: str

class TriageInput(BaseModel):
    age: int
    sex: str
    symptoms: List[str]
    duration_text: Optional[str] = None

class TriageResult(BaseModel):
    acuity: str
    advice: str
    rulesMatched: List[str] = []
    nextSteps: List[str] = []

class KBHit(BaseModel):
    title: str
    url: str
    score: float
    snippet: str

class AppointmentRequest(BaseModel):
    patient_id: str
    datetime_iso: str
    reason: str

class AppointmentConfirmation(BaseModel):
    appointment_id: str
    status: str
    provider: str

class Patient360(BaseModel):
    patient: Patient
    vitals: VitalSigns
    profile: MedicalProfile
    last_updated_iso: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
