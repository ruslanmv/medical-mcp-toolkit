from __future__ import annotations

from fastapi import APIRouter, Depends
from ..deps import get_current_user
from ..models.me import ChatSendIn
from .agent import run_agent

router = APIRouter()


@router.post("/send")
async def chat_send(payload: ChatSendIn, user=Depends(get_current_user)):
    args = payload.args or {}
    message = payload.message or ""
    if message:
        args.setdefault("query", message)
    result = await run_agent(message=message, args=args)
    return result
