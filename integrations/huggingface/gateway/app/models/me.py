from __future__ import annotations
from pydantic import BaseModel
from typing import Any, Dict, Optional

class ChatSendIn(BaseModel):
    message: Optional[str] = None
    args: Dict[str, Any] = {}
