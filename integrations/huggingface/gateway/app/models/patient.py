from __future__ import annotations
from datetime import date
from typing import Any, Literal, Optional
from pydantic import BaseModel, EmailStr, Field

Sex = Literal["male", "female", "intersex", "other", "unknown"]

class PatientUpdateIn(BaseModel):
    first_name: Optional[str] = None
    middle_name: Optional[str] = None
    last_name: Optional[str] = None
    date_of_birth: Optional[date] = None
    sex: Optional[Sex] = None
    phone: Optional[str] = None
    email: Optional[EmailStr] = None
    address_line1: Optional[str] = None
    address_line2: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    postal_code: Optional[str] = None
    country_code: Optional[str] = Field(default=None, min_length=2, max_length=2)

class PatientProfileOut(BaseModel):
    patient_id: str
    external_key: Optional[str] = None
    mrn: Optional[str] = None
    national_id: Optional[str] = None
    first_name: Optional[str] = None
    middle_name: Optional[str] = None
    last_name: Optional[str] = None
    suffix: Optional[str] = None
    date_of_birth: Optional[date] = None
    sex: Optional[Sex] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    address_line1: Optional[str] = None
    address_line2: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    postal_code: Optional[str] = None
    country_code: Optional[str] = None
    pregnant: Optional[bool] = None
    breastfeeding: Optional[bool] = None
    insurance_id: Optional[str] = None
    risk_flags: Optional[Any] = None
    conditions: Optional[Any] = None
    allergies: Optional[Any] = None
    medications: Optional[Any] = None
    latest_vitals: Optional[Any] = None
    meta: Optional[Any] = None
