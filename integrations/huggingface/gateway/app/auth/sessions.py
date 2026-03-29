from __future__ import annotations
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import NamedTuple, Optional
from fastapi import Request, Response
from ..config import settings
from ..repos import users as user_repo

COOKIE_NAME = settings.session_cookie_name

class SessionData(NamedTuple):
    session_id: str
    user_id: str
    expires_at: datetime

def _now_utc() -> datetime:
    return datetime.now(timezone.utc)

def _hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()

async def create_session(*, user_id: str, request: Request, response: Response) -> None:
    raw_token = secrets.token_urlsafe(32)
    token_hash = _hash_token(raw_token)
    expires = _now_utc() + timedelta(seconds=settings.session_ttl_seconds)
    ip: Optional[str] = request.client.host if request.client else None
    ua: Optional[str] = request.headers.get("user-agent")
    await user_repo.insert_session(user_id=user_id, token_hash=token_hash, expires_at=expires, ip_address=ip, user_agent=ua)
    response.set_cookie(key=COOKIE_NAME, value=raw_token, max_age=settings.session_ttl_seconds,
                        expires=int(expires.timestamp()), path="/", secure=settings.session_secure_cookies,
                        httponly=True, samesite=settings.session_samesite)

async def read_session(request: Request) -> SessionData | None:
    raw_token = request.cookies.get(COOKIE_NAME)
    if not raw_token:
        return None
    token_hash = _hash_token(raw_token)
    session_row = await user_repo.get_session_by_token_hash(token_hash)
    if not session_row:
        return None
    return SessionData(session_id=session_row["id"], user_id=session_row["user_id"], expires_at=session_row["expires_at"])

async def revoke_session(request: Request, response: Response) -> None:
    raw_token = request.cookies.get(COOKIE_NAME)
    if raw_token:
        await user_repo.delete_session_by_token_hash(_hash_token(raw_token))
    response.delete_cookie(COOKIE_NAME, path="/")
