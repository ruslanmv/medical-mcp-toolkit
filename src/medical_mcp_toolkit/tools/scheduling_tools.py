from __future__ import annotations
from datetime import datetime
from ..models.components import AppointmentRequest, AppointmentConfirmation, Patient360
from .patient_tools import getPatient, getPatientVitals, getPatientMedicalProfile

def scheduleAppointment(patient_id: str, datetime_iso: str, reason: str) -> AppointmentConfirmation:
    # demo: accept everything
    appt_id = f"APT-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    return AppointmentConfirmation(appointment_id=appt_id, status="confirmed", provider="Dr. Smith")

def getPatient360(patient_id: str) -> Patient360:
    p = getPatient(patient_id=patient_id)
    v = getPatientVitals(patient_id=patient_id)
    prof = getPatientMedicalProfile(patient_id=patient_id)
    return Patient360(patient=p, vitals=v, profile=prof)
