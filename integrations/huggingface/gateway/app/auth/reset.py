from __future__ import annotations
import hashlib, logging, secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Optional, Union
from pydantic import EmailStr
from ..config import settings
from .. import db
from ..repos.users import get_user_by_email, update_password_hash, revoke_all_sessions_for_user
from .passwords import hash_password

log = logging.getLogger(__name__)

def _utcnow() -> datetime:
    return datetime.now(timezone.utc)

def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()

async def _insert_reset_token(user_id: str, token_hash: str, expires_at: datetime) -> None:
    conn = await db.get_conn()
    try:
        await conn.execute("INSERT INTO password_resets (user_id, token_hash, expires_at) VALUES (?, ?, ?)", (user_id, token_hash, expires_at.isoformat()))
        await conn.commit()
    finally:
        await conn.close()

async def _consume_reset_token(token_hash: str) -> Optional[dict[str, Any]]:
    conn = await db.get_conn()
    try:
        cursor = await conn.execute("SELECT id, user_id FROM password_resets WHERE token_hash = ? AND used_at IS NULL AND expires_at > datetime('now') LIMIT 1", (token_hash,))
        row = await cursor.fetchone()
        if not row:
            return None
        row_dict = dict(row)
        await conn.execute("UPDATE password_resets SET used_at = datetime('now') WHERE id = ?", (row_dict["id"],))
        await conn.commit()
        return {"id": row_dict["id"], "user_id": str(row_dict["user_id"])}
    finally:
        await conn.close()

async def request_password_reset(email: Union[str, EmailStr]) -> None:
    try:
        user = await get_user_by_email(str(email))
    except Exception:
        return
    if not user:
        return
    raw_token = secrets.token_urlsafe(32)
    token_hash = _hash_token(raw_token)
    expires_at = _utcnow() + timedelta(seconds=settings.password_reset_ttl_seconds)
    try:
        await _insert_reset_token(user_id=str(user["id"]), token_hash=token_hash, expires_at=expires_at)
    except Exception:
        log.exception("Failed to insert password reset token")
        return
    base = settings.frontend_base_url.rstrip("/") if settings.frontend_base_url else ""
    log.warning("Password reset link for %s: %s/reset-password?token=%s", user["email"], base, raw_token)

async def perform_password_reset(*, raw_token: str, new_password: str) -> None:
    row = await _consume_reset_token(_hash_token(raw_token))
    if not row:
        raise ValueError("Invalid or expired reset link")
    try:
        await update_password_hash(row["user_id"], hash_password(new_password))
        await revoke_all_sessions_for_user(row["user_id"])
    except Exception:
        log.exception("Failed to set new password for user_id=%s", row["user_id"])
