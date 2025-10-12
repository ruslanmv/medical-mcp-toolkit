from __future__ import annotations
import json
import os
from pathlib import Path
from typing import Any, Dict

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import PlainTextResponse, JSONResponse

# Package imports
from medical_mcp_toolkit.mcp_server import (
    list_tools,
    invoke_tool,
    get_components_schema,
)

app = FastAPI(title="medical-mcp-toolkit", version="1.0.0")

# --- Auth dependency ---------------------------------------------------------

def require_bearer(authorization: str | None = Header(default=None)) -> None:
    required = os.getenv("BEARER_TOKEN")
    if not required:
        # Dev mode: if BEARER_TOKEN not set, allow all
        return
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1].strip()
    if token != required:
        raise HTTPException(status_code=403, detail="Invalid token")


# --- Endpoints --------------------------------------------------------------

@app.get("/health", response_class=PlainTextResponse)
def health() -> str:
    return "ok"


@app.get("/schema")
async def schema(_: None = Depends(require_bearer)) -> JSONResponse:
    return JSONResponse(get_components_schema())


@app.get("/tools")
async def tools(_: None = Depends(require_bearer)) -> Dict[str, Any]:
    return {"tools": sorted(list_tools())}


@app.post("/invoke")
async def invoke(body: Dict[str, Any], _: None = Depends(require_bearer)) -> Dict[str, Any]:
    tool = body.get("tool")
    args = body.get("args", {})
    if not tool or not isinstance(args, dict):
        raise HTTPException(status_code=400, detail="Payload must include 'tool' and dict 'args'")
    try:
        result = await invoke_tool(tool, args)
        return {"ok": True, "tool": tool, "result": result}
    except KeyError:
        raise HTTPException(status_code=404, detail=f"Unknown tool: {tool}")
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=str(exc))
