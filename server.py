# medical-mcp-toolkit/server.py
from __future__ import annotations

import os
from typing import Any, Dict

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import PlainTextResponse, JSONResponse
from pydantic import BaseModel, Field

# Import the MCP-facing helpers (registry, dispatcher, schema) you already have.
from medical_mcp_toolkit.mcp_server import (
    list_tools,
    invoke_tool,
    get_components_schema,
)

app = FastAPI(
    title="medical-mcp-toolkit",
    version="1.0.0",
    summary="HTTP shim exposing the MCP tool registry over a simple JSON API.",
    description=(
        "This service exposes MCP tools via HTTP for quick testing and integration. "
        "Authentication is a Bearer token checked against the BEARER_TOKEN environment variable. "
        "Use /tools to list tool names and POST /invoke to call one."
    ),
)


# -----------------------------------------------------------------------------
# Auth dependency
# -----------------------------------------------------------------------------
def require_bearer(authorization: str | None = Header(default=None)) -> None:
    """
    Simple bearer auth.
    If BEARER_TOKEN is not set, auth is disabled (dev mode).
    """
    required = os.getenv("BEARER_TOKEN")
    if not required:  # dev mode: allow all
        return

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")

    token = authorization.split(" ", 1)[1].strip()
    if token != required:
        raise HTTPException(status_code=403, detail="Invalid token")


# -----------------------------------------------------------------------------
# Request/response models (for nicer validation & OpenAPI)
# -----------------------------------------------------------------------------
class InvokeRequest(BaseModel):
    tool: str = Field(..., description="Registered tool name (see GET /tools)")
    args: Dict[str, Any] = Field(
        default_factory=dict,
        description="JSON arguments passed to the tool (validated by the tool itself).",
    )


class InvokeResponse(BaseModel):
    ok: bool = True
    tool: str
    result: Any


class ToolsResponse(BaseModel):
    tools: list[str]


# -----------------------------------------------------------------------------
# Endpoints
# -----------------------------------------------------------------------------
@app.get("/health", response_class=PlainTextResponse, summary="Health check")
def health() -> str:
    # Plain text on purpose; use `| jq -R -r .` if you want it unquoted.
    return "ok"


@app.get("/schema", summary="Return the MCP components JSON schema")
async def schema(_: None = Depends(require_bearer)) -> JSONResponse:
    # get_components_schema() already returns a JSON-serializable dict
    return JSONResponse(get_components_schema())


@app.get("/tools", response_model=ToolsResponse, summary="List available tool names")
async def tools(_: None = Depends(require_bearer)) -> Dict[str, Any]:
    return {"tools": sorted(list_tools())}


@app.post("/invoke", response_model=InvokeResponse, summary="Invoke a tool by name")
async def invoke(payload: InvokeRequest, _: None = Depends(require_bearer)) -> Dict[str, Any]:
    """
    Invoke a registered tool. Arguments are forwarded as-is to the tool's implementation.
    Errors are mapped to HTTP statuses with readable messages.
    """
    try:
        result = await invoke_tool(payload.tool, payload.args)
        return {"ok": True, "tool": payload.tool, "result": result}
    except KeyError:
        # Tool not found in the registry
        raise HTTPException(status_code=404, detail=f"Unknown tool: {payload.tool}")
    except HTTPException:
        # Bubble up intentional HTTP errors
        raise
    except Exception as exc:  # noqa: BLE001
        # Catch-all to avoid leaking stack traces to clients
        raise HTTPException(status_code=500, detail=str(exc))


# Optional: a tiny root endpoint with links (handy when opening in a browser)
@app.get("/", response_class=PlainTextResponse, include_in_schema=False)
def root() -> str:
    return (
        "medical-mcp-toolkit HTTP shim\n\n"
        "GET  /health\n"
        "GET  /tools\n"
        "GET  /schema\n"
        "POST /invoke  (Authorization: Bearer <token>)\n"
    )
