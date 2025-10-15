# medical-mcp-toolkit/server.py
from __future__ import annotations

import logging
import os
import time
import uuid
from typing import Any, Dict

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, PlainTextResponse
from pydantic import BaseModel, Field, ValidationError
from starlette.middleware.cors import CORSMiddleware

# Import the MCP-facing helpers (registry, dispatcher, schema)
from medical_mcp_toolkit.mcp_server import (
    get_components_schema,
    invoke_tool,
    list_tools,
)

# -----------------------------------------------------------------------------
# Bootstrapping & Logging
# -----------------------------------------------------------------------------
load_dotenv()  # load .env if present

LOG_LEVEL = os.getenv("LOG_LEVEL", os.getenv("MCP_LOG_LEVEL", "INFO")).upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
log = logging.getLogger("server")

# -----------------------------------------------------------------------------
# FastAPI app
# -----------------------------------------------------------------------------
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

# Optional CORS (comma-separated origins in CORS_ALLOW_ORIGINS, or * to allow all)
_cors_origins = os.getenv("CORS_ALLOW_ORIGINS", "").strip()
if _cors_origins:
    allow_origins = (
        ["*"] if _cors_origins == "*" else [o.strip() for o in _cors_origins.split(",") if o.strip()]
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allow_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    log.info("CORS enabled for origins: %s", allow_origins)

# -----------------------------------------------------------------------------
# Middleware: request ID & access logging
# -----------------------------------------------------------------------------
@app.middleware("http")
async def add_request_context_and_logging(request: Request, call_next):
    req_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex
    request.state.request_id = req_id  # make available to handlers
    start = time.perf_counter()

    try:
        response = await call_next(request)
    except Exception:
        # Ensure we still log below if an exception bubbles up to our handlers
        raise
    finally:
        duration_ms = round((time.perf_counter() - start) * 1000.0, 2)
        # status_code may not exist if call_next raised; guard with getattr
        status = getattr(locals().get("response", None), "status_code", 500)
        log.info(
            "http %s %s -> %s in %sms (req_id=%s)",
            request.method,
            request.url.path,
            status,
            duration_ms,
            req_id,
        )

    response.headers["X-Request-ID"] = req_id
    return response


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


class ErrorResponse(BaseModel):
    code: str
    message: str
    request_id: str | None = None
    details: Dict[str, Any] | None = None


# -----------------------------------------------------------------------------
# Exception handlers (uniform JSON errors with request_id)
# -----------------------------------------------------------------------------
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    payload = ErrorResponse(
        code=str(exc.status_code),
        message=str(exc.detail),
        request_id=getattr(request.state, "request_id", None),
    ).model_dump()
    return JSONResponse(status_code=exc.status_code, content=payload)


@app.exception_handler(RequestValidationError)
async def request_validation_exception_handler(request: Request, exc: RequestValidationError):
    payload = ErrorResponse(
        code="422",
        message="Request validation error",
        request_id=getattr(request.state, "request_id", None),
        details={"errors": exc.errors()},
    ).model_dump()
    return JSONResponse(status_code=422, content=payload)


@app.exception_handler(ValidationError)
async def pydantic_validation_exception_handler(request: Request, exc: ValidationError):
    payload = ErrorResponse(
        code="422",
        message="Validation error",
        request_id=getattr(request.state, "request_id", None),
        details={"errors": exc.errors()},
    ).model_dump()
    return JSONResponse(status_code=422, content=payload)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    # Log full stack for operators; return safe message to clients
    log.exception("Unhandled error (req_id=%s): %r", getattr(request.state, "request_id", None), exc)
    payload = ErrorResponse(
        code="500",
        message="Internal server error",
        request_id=getattr(request.state, "request_id", None),
    ).model_dump()
    return JSONResponse(status_code=500, content=payload)


# -----------------------------------------------------------------------------
# Lifespan events
# -----------------------------------------------------------------------------
@app.on_event("startup")
async def on_startup():
    try:
        tools = sorted(list_tools())
        log.info("Startup complete. %d tools registered: %s", len(tools), ", ".join(tools))
    except Exception as exc:  # pragma: no cover
        log.warning("Startup: failed to list tools: %r", exc)


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
