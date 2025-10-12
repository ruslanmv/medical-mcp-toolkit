#!/usr/bin/env python3
"""
Fast, dependency-light probe that talks directly to an MCP **SSE** server using
raw HTTP SSE + JSON-RPC (no mcp client libs).

Endpoints
---------
GET  /health  -> initialize + tools/list (all pages) -> { ok, tools_count, sse_base }
GET  /tools   -> initialize + tools/list (all pages) -> { ok, count, tools }
POST /invoke  -> initialize + tools/call(name,args)  -> raw JSON-RPC result

Run
---
uv run uvicorn scripts.mcp_probe_api:app --host 0.0.0.0 --port 9191

Environment
-----------
MCP_URL               default http://localhost:9090/sse
BEARER_TOKEN|TOKEN    bearer (optional)
LOG_LEVEL             DEBUG/INFO/WARNING/ERROR (default INFO)
PROTOCOL_VERSION      default 2024-11-05
PROBE_TIMEOUT_INIT    default 12
PROBE_TIMEOUT_TOOLS   default 12
PROBE_TIMEOUT_INVOKE  default 20
CONNECT_TIMEOUT       default 10
READ_TIMEOUT          default 25
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlsplit, urlunsplit

import httpx
from fastapi import FastAPI, Depends, Header, HTTPException, Query, Request, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# -----------------------------
# Logging
# -----------------------------
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
log = logging.getLogger("mcp_probe")

# -----------------------------
# Defaults / timeouts
# -----------------------------
DEFAULT_MCP_URL = os.getenv("MCP_URL", "http://localhost:9090/sse")
DEFAULT_TOKEN = os.getenv("BEARER_TOKEN") or os.getenv("TOKEN")
PROTOCOL_VERSION = os.getenv("PROTOCOL_VERSION", "2024-11-05")

TIMEOUT_INIT = float(os.getenv("PROBE_TIMEOUT_INIT", "12"))
TIMEOUT_TOOLS = float(os.getenv("PROBE_TIMEOUT_TOOLS", "12"))
TIMEOUT_INVOKE = float(os.getenv("PROBE_TIMEOUT_INVOKE", "20"))
CONNECT_TIMEOUT = float(os.getenv("CONNECT_TIMEOUT", "10"))
READ_TIMEOUT = float(os.getenv("READ_TIMEOUT", "25"))

# -----------------------------
# FastAPI
# -----------------------------
app = FastAPI(
    title="Medical MCP Probe API",
    version="1.1.1",
    description="Tiny FastAPI app that connects to the MCP SSE server via raw SSE + JSON-RPC.",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# -----------------------------
# Models
# -----------------------------
class InvokeRequest(BaseModel):
    tool: str
    args: Dict[str, Any] = {}

class HealthResponse(BaseModel):
    ok: bool
    sse_base: str
    tools_count: int
    detail: Optional[str] = None

# -----------------------------
# Helpers
# -----------------------------
def _normalize_base_url(url: str) -> str:
    url = (url or "").strip()
    if not url:
        raise ValueError("Missing MCP base URL")
    if url.endswith("/") and len(url) > 1:
        url = url[:-1]
    return url

def _origin_of(url: str) -> str:
    sp = urlsplit(url)
    return urlunsplit((sp.scheme, sp.netloc, "", "", ""))

def _join_origin_path(origin: str, path_or_rel: str) -> str:
    if path_or_rel.startswith(("http://", "https://")):
        return path_or_rel
    if not path_or_rel.startswith("/"):
        path_or_rel = "/" + path_or_rel
    return origin + path_or_rel

def _toggle_trailing_slash(url: str) -> str:
    sp = urlsplit(url)
    path = sp.path
    if path.endswith("/"):
        path = path[:-1] or "/"
    else:
        path = path + "/"
    return urlunsplit((sp.scheme, sp.netloc, path, sp.query, sp.fragment))

def _swap_sse_messages_to_root(url: str) -> str:
    sp = urlsplit(url)
    path = sp.path.replace("/sse/messages", "/messages")
    return urlunsplit((sp.scheme, sp.netloc, path, sp.query, sp.fragment))

def _pretty(obj: Any) -> str:
    try:
        import orjson  # type: ignore
        return orjson.dumps(obj, option=orjson.OPT_INDENT_2).decode("utf-8")
    except Exception:
        return json.dumps(obj, indent=2, ensure_ascii=False)

def _auth_headers(token: Optional[str]) -> Dict[str, str]:
    return {"Authorization": f"Bearer {token}"} if token else {}

# -----------------------------
# Minimal async SSE session
# -----------------------------
class SseSession:
    """
    Minimal SSE client:
      1) GET base_url (Accept: text/event-stream)
      2) First 'data:' event announces writer URL (string or JSON {"endpoint": "/messages/..."}).
      3) POST JSON-RPC to writer endpoint.
      4) Read 'data:' events and match JSON-RPC responses by "id".
    """

    def __init__(self, base_url: str, token: Optional[str]) -> None:
        self.base_url = _normalize_base_url(base_url)
        self.origin = _origin_of(self.base_url)
        self.token = token
        self.client = httpx.AsyncClient(
            timeout=httpx.Timeout(
                connect=CONNECT_TIMEOUT, read=READ_TIMEOUT, write=15.0, pool=15.0
            ),
            headers={**_auth_headers(token)},
        )
        self._stream_cm = None
        self._stream: Optional[httpx.Response] = None
        self._lines_iter = None  # single async line iterator
        self.writer_url: Optional[str] = None

    async def __aenter__(self) -> "SseSession":
        log.info("[mcp_probe] [sse] GET %s", self.base_url)
        self._stream_cm = self.client.stream(
            "GET", self.base_url, headers={"Accept": "text/event-stream"}
        )
        self._stream = await self._stream_cm.__aenter__()  # streaming response
        if self._stream.status_code != 200:
            raise RuntimeError(f"SSE GET failed: {self._stream.status_code}")

        # One iterator for the whole session
        self._lines_iter = self._stream.aiter_lines().__aiter__()

        # First event: writer endpoint
        self.writer_url = await self._read_first_writer_event()
        log.info("[mcp_probe] [sse] writer: %s", self.writer_url)
        return self

    async def __aexit__(self, exc_type, exc, tb):
        try:
            if self._stream_cm is not None:
                await self._stream_cm.__aexit__(exc_type, exc, tb)
        finally:
            await self.client.aclose()

    async def _next_line_with_deadline(self, deadline: float) -> str:
        assert self._lines_iter is not None
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise asyncio.TimeoutError()
        try:
            return await asyncio.wait_for(self._lines_iter.__anext__(), timeout=remaining)
        except StopAsyncIteration:
            raise RuntimeError("SSE stream closed")

    async def _read_next_event(self, deadline: float) -> str:
        """Read one full SSE event body (joined 'data:' lines) with a deadline."""
        data_lines: List[str] = []
        while True:
            line = await self._next_line_with_deadline(deadline)
            if line == "":
                body = "\n".join(data_lines).strip()
                if body:
                    return body
                data_lines.clear()
                continue
            if line.startswith("data:"):
                data_lines.append(line[5:].lstrip())

    async def _read_first_writer_event(self) -> str:
        deadline = time.monotonic() + READ_TIMEOUT
        body = await self._read_next_event(deadline)

        # Accept plain string (path/absolute) OR JSON {"endpoint": "..."} / {"writer": "..."}
        writer = None
        if body and body[:1] in ("{", "["):
            try:
                msg = json.loads(body)
                if isinstance(msg, dict):
                    writer = msg.get("endpoint") or msg.get("writer") or msg.get("messagesUrl")
            except json.JSONDecodeError:
                pass
        if writer is None:
            writer = body

        return _join_origin_path(self.origin, writer)

    async def post_jsonrpc(self, payload: Dict[str, Any]) -> int:
        """POST JSON-RPC with fallbacks; return HTTP status."""
        if not self.writer_url:
            raise RuntimeError("Writer URL not initialized")

        # Try 1: as-is
        status = await self._post_once(self.writer_url, payload)
        if 200 <= status < 300:
            return status

        # Try 2: toggle trailing slash
        alt = _toggle_trailing_slash(self.writer_url)
        if alt != self.writer_url:
            status = await self._post_once(alt, payload)
            if 200 <= status < 300:
                self.writer_url = alt
                return status

        # Try 3: swap /sse/messages <-> /messages
        alt2 = _swap_sse_messages_to_root(self.writer_url)
        if alt2 != self.writer_url:
            status = await self._post_once(alt2, payload)
            if 200 <= status < 300:
                self.writer_url = alt2
                return status

        # Try 3b: toggle slash after swap
        alt2b = _toggle_trailing_slash(alt2)
        if alt2b != alt2:
            status = await self._post_once(alt2b, payload)
            if 200 <= status < 300:
                self.writer_url = alt2b
                return status

        return status

    async def _post_once(self, url: str, payload: Dict[str, Any]) -> int:
        try:
            log.debug("[rpc→] POST %s %s", url, _pretty(payload))
            r = await self.client.post(
                url,
                headers={"Content-Type": "application/json"},
                json=payload,
                follow_redirects=True,
            )
            log.debug("[rpc←] HTTP %s", r.status_code)
            return r.status_code
        except Exception as e:
            log.warning("[rpc] POST failed to %s: %r", url, e)
            return 599  # client-side error

    async def recv_result_for_id(self, req_id: int, timeout: float) -> Dict[str, Any]:
        """Read SSE events until we find a JSON-RPC response with matching id."""
        deadline = time.monotonic() + timeout
        while True:
            raw = await self._read_next_event(deadline)
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                log.debug("[sse] non-JSON event: %r", raw)
                continue

            if isinstance(msg, dict) and msg.get("id") == req_id:
                log.debug("[sse] matched id=%s -> %s", req_id, _pretty(msg))
                return msg
            # Ignore notifications / unrelated ids

# -----------------------------
# Core flows
# -----------------------------
async def _initialize(sess: SseSession, req_id: int = 0) -> Dict[str, Any]:
    st = await sess.post_jsonrpc(
        {
            "jsonrpc": "2.0",
            "id": req_id,
            "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "probe", "version": "1"},
            },
        }
    )
    if not (200 <= st < 300):
        raise RuntimeError(f"initialize POST failed: HTTP {st}")
    return await sess.recv_result_for_id(req_id, timeout=TIMEOUT_INIT)

async def _list_all_tools_via_sse(base_url: str, token: Optional[str]) -> Dict[str, Any]:
    """
    initialize -> tools/list (paged) -> accumulate all tools
    FIX: do NOT send 'cursor' when it is None (servers may reject null with -32602).
         For page 1, send params {}. For next pages, send {'cursor': '<string>'}.
         One-time fallback (page 1 only): retry with {'cursor': None} if {} fails.
    """
    async with SseSession(base_url, token) as sess:
        init_resp = await _initialize(sess, req_id=0)

        tools: List[Dict[str, Any]] = []
        pages: List[Dict[str, Any]] = []
        cursor: Optional[str] = None
        req_id = 1
        first_page_fallback_tried = False

        while True:
            params: Dict[str, Any] = {} if cursor is None else {"cursor": cursor}
            payload = {
                "jsonrpc": "2.0",
                "id": req_id,
                "method": "tools/list",
                "params": params,
            }

            st = await sess.post_jsonrpc(payload)
            if not (200 <= st < 300):
                raise RuntimeError(f"tools/list POST failed: HTTP {st}")

            resp = await sess.recv_result_for_id(req_id, timeout=TIMEOUT_TOOLS)

            # If the server complains about params on the first page, try the null-cursor shape once.
            if "error" in resp:
                code = resp["error"].get("code")
                msg = resp["error"].get("message")
                if cursor is None and code == -32602 and not first_page_fallback_tried:
                    first_page_fallback_tried = True
                    log.info("[mcp_probe] tools/list rejected {}; retrying with {'cursor': None}")
                    # Retry same id with cursor=None (some servers oddly require the field)
                    st2 = await sess.post_jsonrpc(
                        {
                            "jsonrpc": "2.0",
                            "id": req_id,
                            "method": "tools/list",
                            "params": {"cursor": None},
                        }
                    )
                    if not (200 <= st2 < 300):
                        raise RuntimeError(f"tools/list POST failed (fallback): HTTP {st2}")
                    resp = await sess.recv_result_for_id(req_id, timeout=TIMEOUT_TOOLS)
                else:
                    raise RuntimeError(f"tools/list error: code={code} msg={msg}")

            pages.append(resp)
            result = resp.get("result") or {}
            page_tools = result.get("tools") or []
            tools.extend(page_tools)

            next_cursor = result.get("nextCursor")
            if not next_cursor:
                break

            cursor = next_cursor
            req_id += 1  # next page id

        return {"ok": True, "init": init_resp, "tools": tools, "pages": pages, "count": len(tools)}

async def _call_tool_via_sse(base_url: str, token: Optional[str], name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    """initialize -> tools/call"""
    async with SseSession(base_url, token) as sess:
        _ = await _initialize(sess, req_id=0)

        call_id = 1
        payload = {
            "jsonrpc": "2.0",
            "id": call_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": args or {}},
        }
        st = await sess.post_jsonrpc(payload)
        if not (200 <= st < 300):
            raise RuntimeError(f"tools/call POST failed: HTTP {st}")

        resp = await sess.recv_result_for_id(call_id, timeout=TIMEOUT_INVOKE)
        return resp  # may be result or error (pass-through)

# -----------------------------
# Dependency to collect config
# -----------------------------
def _resolve_probe_config(
    mcp_url: Optional[str] = Query(default=None, description="Override MCP SSE base URL"),
    token_qs: Optional[str] = Query(default=None, alias="token", description="Bearer token"),
    auth_header: Optional[str] = Header(default=None, alias="Authorization"),
) -> Tuple[str, Optional[str]]:
    """
    Resolve (url, token) with precedence:
      query ?mcp_url & ?token > Authorization: Bearer ... > env defaults
    """
    url = _normalize_base_url(mcp_url or DEFAULT_MCP_URL)
    token: Optional[str] = None

    if token_qs:
        token = token_qs
    elif auth_header and auth_header.lower().startswith("bearer "):
        token = auth_header[7:].strip()
    elif DEFAULT_TOKEN:
        token = DEFAULT_TOKEN

    log.debug("[cfg] url=%s has_token=%s", url, bool(token))
    return url, token

# -----------------------------
# Routes
# -----------------------------
@app.middleware("http")
async def _log_requests(request: Request, call_next):
    info = f"{request.method} {request.url.path}"
    log.debug("→ %s", info)
    try:
        response = await call_next(request)
        log.debug("← %s %s", info, response.status_code)
        return response
    except Exception as e:
        log.error("✗ %s failed: %s", info, e)
        raise

@app.get("/health", response_model=HealthResponse)
async def health(cfg: Tuple[str, Optional[str]] = Depends(_resolve_probe_config)):
    url, token = cfg
    try:
        data = await _list_all_tools_via_sse(url, token)
        return HealthResponse(ok=True, sse_base=url, tools_count=data["count"])
    except Exception as e:
        return HealthResponse(ok=False, sse_base=url, tools_count=0, detail=str(e))

@app.get("/tools")
async def tools(cfg: Tuple[str, Optional[str]] = Depends(_resolve_probe_config)):
    url, token = cfg
    try:
        data = await _list_all_tools_via_sse(url, token)
        return {
            "ok": True,
            "sse_base": url,
            "protocol": PROTOCOL_VERSION,
            "count": data["count"],
            "tools": data["tools"],
        }
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e))

@app.post("/invoke")
async def invoke(req: InvokeRequest, cfg: Tuple[str, Optional[str]] = Depends(_resolve_probe_config)):
    url, token = cfg
    try:
        return await _call_tool_via_sse(url, token, req.tool, req.args)
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e))

@app.get("/")
async def root():
    return {
        "name": "Medical MCP Probe API",
        "endpoints": ["/health", "/tools", "/invoke"],
        "defaults": {"MCP_URL": DEFAULT_MCP_URL, "BEARER_TOKEN/TOKEN": bool(DEFAULT_TOKEN)},
        "log_level": LOG_LEVEL,
        "protocol_version": PROTOCOL_VERSION,
        "timeouts": {
            "init": TIMEOUT_INIT,
            "list_tools": TIMEOUT_TOOLS,
            "invoke": TIMEOUT_INVOKE,
            "connect": CONNECT_TIMEOUT,
            "read": READ_TIMEOUT,
        },
    }

if __name__ == "__main__":
    try:
        import uvicorn  # type: ignore
    except ImportError:
        raise SystemExit("uvicorn is required. Please install it.")
    port = int(os.getenv("PROBE_PORT", "9191"))
    log.info("🚀 Starting MCP Probe API on http://0.0.0.0:%s (LOG_LEVEL=%s)", port, LOG_LEVEL)
    uvicorn.run(app, host="0.0.0.0", port=port)
