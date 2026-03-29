from __future__ import annotations
import json
from typing import Any, Dict, Optional
from .. import db

async def create_or_get_open_encounter(patient_id: str, chief_complaint: str) -> str:
    conn = await db.get_conn()
    try:
        cursor = await conn.execute("SELECT id FROM encounters WHERE patient_id = ? AND status = 'open' ORDER BY started_at DESC LIMIT 1", (patient_id,))
        row = await cursor.fetchone()
        if row:
            return str(dict(row)["id"])
        await conn.execute("INSERT INTO encounters (patient_id, encounter_type, status, chief_complaint) VALUES (?, 'chat', 'open', ?)", (patient_id, chief_complaint))
        await conn.commit()
        cursor = await conn.execute("SELECT id FROM encounters WHERE patient_id = ? AND status = 'open' ORDER BY started_at DESC LIMIT 1", (patient_id,))
        return str(dict(await cursor.fetchone())["id"])
    finally:
        await conn.close()

async def insert_patient_note(*, encounter_id: str, author_user_id: str, content: str, data: Dict[str, Any]) -> str:
    conn = await db.get_conn()
    try:
        await conn.execute("INSERT INTO encounter_notes (encounter_id, author_user_id, kind, content, data) VALUES (?, ?, 'patient_note', ?, ?)", (encounter_id, author_user_id, content, json.dumps(data or {})))
        await conn.commit()
        cursor = await conn.execute("SELECT id FROM encounter_notes WHERE encounter_id = ? ORDER BY created_at DESC LIMIT 1", (encounter_id,))
        return str(dict(await cursor.fetchone())["id"])
    finally:
        await conn.close()

async def fetch_latest_patient_intake_for_patient(patient_id: str) -> Optional[Dict[str, Any]]:
    conn = await db.get_conn()
    try:
        cursor = await conn.execute("SELECT n.id AS note_id, e.id AS encounter_id, e.chief_complaint, n.content, n.data, n.created_at FROM encounter_notes n JOIN encounters e ON e.id = n.encounter_id WHERE e.patient_id = ? AND n.kind = 'patient_note' ORDER BY n.created_at DESC LIMIT 1", (patient_id,))
        row = await cursor.fetchone()
        if not row:
            return None
        result = dict(row)
        if isinstance(result.get("data"), str):
            try:
                result["data"] = json.loads(result["data"])
            except (json.JSONDecodeError, TypeError):
                result["data"] = {}
        return result
    finally:
        await conn.close()
