from __future__ import annotations
from typing import Any, Dict, Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from ..deps import get_current_user
from ..models.patient import PatientProfileOut, PatientUpdateIn
from ..repos.patients import get_patient_id_for_user, fetch_profile_by_patient_id, update_patient_by_id, create_patient_and_link
from ..repos import encounters as enc_repo

router = APIRouter()

@router.get("/patient", response_model=PatientProfileOut | None)
async def get_patient_profile(user=Depends(get_current_user)):
    pid = await get_patient_id_for_user(str(user["id"]))
    if not pid:
        return None
    return await fetch_profile_by_patient_id(pid)

@router.put("/patient")
async def upsert_patient(payload: PatientUpdateIn, user=Depends(get_current_user)):
    user_id = str(user["id"])
    pid = await get_patient_id_for_user(user_id)
    if not pid:
        try:
            pid = await create_patient_and_link(user_id, payload)
        except ValueError as e:
            raise HTTPException(status_code=422, detail=str(e)) from e
    else:
        await update_patient_by_id(pid, payload)
    return {"ok": True}

class IntakeSaveIn(BaseModel):
    chief_complaint: str = Field(..., min_length=1)
    content: Optional[str] = ""
    data: Dict[str, Any] = Field(default_factory=dict)

class IntakeOut(BaseModel):
    encounter_id: str
    note_id: str
    chief_complaint: Optional[str] = None
    content: Optional[str] = None
    data: Dict[str, Any]

@router.get("/intake", response_model=IntakeOut | None)
async def get_latest_intake(user=Depends(get_current_user)):
    pid = await get_patient_id_for_user(str(user["id"]))
    if not pid:
        return None
    row = await enc_repo.fetch_latest_patient_intake_for_patient(pid)
    if not row:
        return None
    return IntakeOut(encounter_id=str(row["encounter_id"]), note_id=str(row["note_id"]), chief_complaint=row.get("chief_complaint"), content=row.get("content"), data=row.get("data") or {})

@router.post("/intake")
async def save_intake(payload: IntakeSaveIn, user=Depends(get_current_user)):
    user_id = str(user["id"])
    pid = await get_patient_id_for_user(user_id)
    if not pid:
        raise HTTPException(status_code=409, detail="Please complete your profile before starting a clinical intake.")
    encounter_id = await enc_repo.create_or_get_open_encounter(patient_id=pid, chief_complaint=payload.chief_complaint)
    note_id = await enc_repo.insert_patient_note(encounter_id=encounter_id, author_user_id=user_id, content=payload.content or "", data=payload.data or {})
    return {"ok": True, "encounter_id": encounter_id, "note_id": note_id}
