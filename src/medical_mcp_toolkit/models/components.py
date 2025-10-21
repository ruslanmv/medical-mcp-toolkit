# src/medical_mcp_toolkit/models/components.py
from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, Field


# =========================
# Enums mirroring the DB
# =========================
class SexEnum(str, Enum):
    male = "male"
    female = "female"
    intersex = "intersex"
    other = "other"
    unknown = "unknown"


class AcuityLevel(str, Enum):
    EMERGENT = "EMERGENT"
    URGENT = "URGENT"
    ROUTINE = "ROUTINE"


class RiskLevel(str, Enum):
    LOW = "LOW"
    MODERATE = "MODERATE"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class InteractionSeverity(str, Enum):
    minor = "minor"
    moderate = "moderate"
    major = "major"
    contraindicated = "contraindicated"


class PregnancyCategory(str, Enum):
    A = "A"
    B = "B"
    C = "C"
    D = "D"
    X = "X"
    Unknown = "Unknown"


class AllergySeverity(str, Enum):
    mild = "mild"
    moderate = "moderate"
    severe = "severe"


class AppointmentStatus(str, Enum):
    scheduled = "scheduled"
    completed = "completed"
    cancelled = "cancelled"
    no_show = "no-show"


class PatientUserRole(str, Enum):
    OWNER = "OWNER"
    CAREGIVER = "CAREGIVER"
    PROXY = "PROXY"


class EncounterType(str, Enum):
    in_person = "in_person"
    telemed = "telemed"
    chat = "chat"


class EncounterStatus(str, Enum):
    open = "open"
    closed = "closed"
    cancelled = "cancelled"


class NoteKind(str, Enum):
    ai_summary = "ai_summary"
    provider_note = "provider_note"
    patient_note = "patient_note"
    system = "system"


# =========================
# Core models
# =========================
class Patient(BaseModel):
    patient_id: str
    name: str
    age: Optional[int] = None
    sex: Optional[SexEnum] = Field(default=SexEnum.unknown)


class VitalSigns(BaseModel):
    # Aligned to DB columns (db.vitals)
    heart_rate_bpm: Optional[int] = None
    systolic_mmhg: Optional[int] = None
    diastolic_mmhg: Optional[int] = None
    resp_rate_min: Optional[int] = None
    temperature_c: Optional[float] = None
    spo2_percent: Optional[float] = None
    weight_kg: Optional[float] = None
    height_cm: Optional[float] = None
    bmi: Optional[float] = None
    serum_creatinine: Optional[float] = None  # mg/dL in practice
    egfr_ml_min_1_73m2: Optional[float] = None
    timestamp_utc: datetime = Field(default_factory=datetime.utcnow)


class MedicalProfile(BaseModel):
    conditions: List[str] = Field(default_factory=list)
    allergies: List[str] = Field(default_factory=list)
    medications: List[str] = Field(default_factory=list)


class ClinicalCalcInput(BaseModel):
    age: int
    sex: SexEnum
    weight_kg: float
    height_cm: float
    serum_creatinine_mg_dl: float


class ClinicalCalcOutput(BaseModel):
    bmi: float
    bsa_m2: float
    creatinine_clearance_ml_min: float
    egfr_ml_min_1_73m2: float
    notes: List[str] = Field(default_factory=list)


class DrugInformation(BaseModel):
    name: str
    indications: List[str] = Field(default_factory=list)
    dosage: str = ""
    adverse_effects: List[str] = Field(default_factory=list)
    # renamed to align with DB: drugs.reference_urls
    reference_urls: List[str] = Field(default_factory=list)


class InteractionSet(BaseModel):
    interacting_drugs: List[str] = Field(default_factory=list)
    severity: InteractionSeverity = InteractionSeverity.minor
    description: str = ""


class ContraindicationReport(BaseModel):
    drug: str
    reasons: List[str] = Field(default_factory=list)
    severity: str = "none"


class AlternativeTreatment(BaseModel):
    drug: str
    rationale: str


class TriageInput(BaseModel):
    age: int
    sex: SexEnum
    symptoms: List[str]
    duration_text: Optional[str] = None


class TriageResult(BaseModel):
    acuity: AcuityLevel
    advice: str
    rulesMatched: List[str] = Field(default_factory=list)
    nextSteps: List[str] = Field(default_factory=list)


class KBHit(BaseModel):
    title: str
    url: str
    score: float
    snippet: str


class AppointmentRequest(BaseModel):
    patient_id: str
    datetime_iso: str
    reason: str
    specialty: str  # required by DB schema


class AppointmentConfirmation(BaseModel):
    appointment_id: str
    status: AppointmentStatus
    provider: str


class PatientUser(BaseModel):
    # New model to reflect DB patient_users table
    id: Optional[UUID] = None
    patient_id: str
    user_id: str
    role: PatientUserRole = PatientUserRole.OWNER
    linked_at: Optional[datetime] = None


class Patient360(BaseModel):
    patient: Patient
    vitals: VitalSigns
    profile: MedicalProfile
    last_updated_iso: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
