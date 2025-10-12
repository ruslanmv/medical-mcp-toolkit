# src/medical_mcp_toolkit/http_app.py
from __future__ import annotations
import os
from typing import Any, Dict
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.responses import ORJSONResponse
from .mcp_server import get_components_schema, invoke_tool, list_tools

BEARER = os.getenv("BEARER_TOKEN", "dev-token")
app = FastAPI(title="medical-mcp-toolkit", default_response_class=ORJSONResponse)

def _auth(authorization: str | None = Header(default=None)) -> None:
    if BEARER and BEARER != "dev-token":
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")
        token = authorization.split(" ", 1)[1].strip()
        if token != BEARER:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid token")

@app.get("/health", include_in_schema=False)
def health() -> str:
    return "ok"

@app.get("/schema")
def schema(_: None = Depends(_auth)) -> Dict[str, Any]:
    return get_components_schema()

@app.get("/tools")
def tools(_: None = Depends(_auth)) -> Dict[str, Any]:
    return {"tools": list_tools()}

@app.post("/invoke")
async def invoke(payload: Dict[str, Any], _: None = Depends(_auth)) -> Dict[str, Any]:
    tool = payload.get("tool")
    args = payload.get("args", {}) or {}
    if not tool or not isinstance(tool, str):
        raise HTTPException(status_code=400, detail="Missing 'tool' string")
    if not isinstance(args, dict):
        raise HTTPException(status_code=400, detail="'args' must be an object")
    result = await invoke_tool(tool, args)
    return {"ok": True, "tool": tool, "result": result}
