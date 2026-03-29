from __future__ import annotations

from fastapi import Depends, HTTPException, Request, status

from .auth import sessions
from .repos import users as user_repo


async def get_current_session(request: Request) -> sessions.SessionData:
    session = await sessions.read_session(request)
    if not session:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    return session


async def get_current_user(session: sessions.SessionData = Depends(get_current_session)) -> dict:
    user = await user_repo.get_user_by_id(session.user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user
