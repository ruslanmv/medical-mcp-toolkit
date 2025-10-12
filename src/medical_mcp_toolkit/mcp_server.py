# src/medical_mcp_toolkit/mcp_server.py
from __future__ import annotations

import os
import inspect
import json
import logging
from pathlib import Path
from typing import Any, Dict, Callable, Awaitable, List

# -----------------------------------------------------------------------------
# FastMCP (SSE/STDIO)
# -----------------------------------------------------------------------------
try:
    from mcp.server.fastmcp import FastMCP  # type: ignore
except Exception as exc:  # pragma: no cover
    raise RuntimeError("FastMCP is not available. Install the 'mcp' package.") from exc

# -----------------------------------------------------------------------------
# Business models (used by tool impls; handlers return dicts/arrays to MCP)
# -----------------------------------------------------------------------------
from .models.components import (  # noqa: F401
    Patient,
    VitalSigns,
    MedicalProfile,
    ClinicalCalcInput,
    ClinicalCalcOutput,
    DrugInformation,
    InteractionSet,
    ContraindicationReport,
    AlternativeTreatment,
    TriageInput,
    TriageResult,
    KBHit,
    AppointmentRequest,
    AppointmentConfirmation,
    Patient360,
)

# ---- Tool implementations (camelCase) --------------------------------------
from .tools.patient_tools import (
    getPatient,
    getPatientVitals,
    getPatientMedicalProfile,
    calcClinicalScores,
)
from .tools.drug_tools import (
    getDrugInfo,
    getDrugInteractions,
    getDrugContraindications,
    getDrugAlternatives,
)
from .tools.triage_tools import (
    triageSymptoms,
    searchMedicalKB,
)
from .tools.scheduling_tools import (
    scheduleAppointment,
    getPatient360,
)

# =============================================================================
# Logging
# =============================================================================
LOG_LEVEL = os.getenv("MCP_LOG_LEVEL", "INFO").upper()
log = logging.getLogger("mcp_server")
if not log.handlers:
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL, logging.INFO),
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    )

# align uvicorn logs with MCP_LOG_LEVEL (when we run the SSE ASGI fallback)
logging.getLogger("uvicorn.error").setLevel(getattr(logging, LOG_LEVEL, logging.INFO))
logging.getLogger("uvicorn.access").setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

# =============================================================================
# Public registry used by optional HTTP shim (/tools, /invoke)
# =============================================================================
# NOTE: Return type is Any because some tools return dicts and some (e.g. getDrugAlternatives)
# return a bare array per the contract.
_TOOL_REGISTRY: Dict[str, Callable[[Dict[str, Any]], Awaitable[Any]]] = {}

def _register_tool(name: str, fn: Callable[[Dict[str, Any]], Awaitable[Any]]) -> None:
    log.debug("[registry] registering tool '%s' -> %s", name, getattr(fn, "__name__", fn))
    _TOOL_REGISTRY[name] = fn

# --------------------- Patient wrappers -------------------------------------
async def _w_getPatient(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:getPatient] payload=%s", payload)
    out = getPatient(**payload).model_dump()
    log.debug("[tool:getPatient] -> %s", out)
    return out

async def _w_getPatientVitals(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:getPatientVitals] payload=%s", payload)
    out = getPatientVitals(**payload).model_dump()
    log.debug("[tool:getPatientVitals] -> %s", out)
    return out

async def _w_getPatientMedicalProfile(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:getPatientMedicalProfile] payload=%s", payload)
    out = getPatientMedicalProfile(**payload).model_dump()
    log.debug("[tool:getPatientMedicalProfile] -> %s", out)
    return out

async def _w_calcClinicalScores(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:calcClinicalScores] payload=%s", payload)
    out = calcClinicalScores(**payload).model_dump()
    log.debug("[tool:calcClinicalScores] -> %s", out)
    return out

# --------------------- Drug wrappers ----------------------------------------
async def _w_getDrugInfo(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:getDrugInfo] payload=%s", payload)
    out = getDrugInfo(**payload).model_dump()
    log.debug("[tool:getDrugInfo] -> %s", out)
    return out

async def _w_getDrugInteractions(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:getDrugInteractions] payload=%s", payload)
    out = getDrugInteractions(**payload).model_dump()
    log.debug("[tool:getDrugInteractions] -> %s", out)
    return out

async def _w_getDrugContraindications(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:getDrugContraindications] payload=%s", payload)
    out = getDrugContraindications(**payload).model_dump()
    log.debug("[tool:getDrugContraindications] -> %s", out)
    return out

async def _w_getDrugAlternatives(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Contract: return a bare array of AlternativeTreatment.
    """
    log.debug("[tool:getDrugAlternatives] payload=%s", payload)
    models = getDrugAlternatives(**payload)
    out = [m.model_dump() for m in models]
    log.debug("[tool:getDrugAlternatives] -> %s", out)
    return out

# --------------------- Triage / KB wrappers ---------------------------------
async def _w_triageSymptoms(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:triageSymptoms] payload=%s", payload)
    out = triageSymptoms(**payload).model_dump()
    log.debug("[tool:triageSymptoms] -> %s", out)
    return out

async def _w_searchMedicalKB(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:searchMedicalKB] payload=%s", payload)
    res = searchMedicalKB(**payload)  # {"hits": list[KBHit]}
    hits = res.get("hits", [])
    out: List[Dict[str, Any]] = []
    for h in hits:
        out.append(h.model_dump() if hasattr(h, "model_dump") else h)
    final = {"hits": out}
    log.debug("[tool:searchMedicalKB] -> %s", final)
    return final

# --------------------- Scheduling / P360 wrappers ---------------------------
async def _w_scheduleAppointment(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:scheduleAppointment] payload=%s", payload)
    out = scheduleAppointment(**payload).model_dump()
    log.debug("[tool:scheduleAppointment] -> %s", out)
    return out

async def _w_getPatient360(payload: Dict[str, Any]) -> Dict[str, Any]:
    log.debug("[tool:getPatient360] payload=%s", payload)
    out = getPatient360(**payload).model_dump()
    log.debug("[tool:getPatient360] -> %s", out)
    return out

# ---- Registry init ---------------------------------------------------------
_register_tool("getPatient", _w_getPatient)
_register_tool("getPatientVitals", _w_getPatientVitals)
_register_tool("getPatientMedicalProfile", _w_getPatientMedicalProfile)
_register_tool("calcClinicalScores", _w_calcClinicalScores)
_register_tool("getDrugInfo", _w_getDrugInfo)
_register_tool("getDrugInteractions", _w_getDrugInteractions)
_register_tool("getDrugContraindications", _w_getDrugContraindications)
_register_tool("getDrugAlternatives", _w_getDrugAlternatives)
_register_tool("triageSymptoms", _w_triageSymptoms)
_register_tool("searchMedicalKB", _w_searchMedicalKB)
_register_tool("scheduleAppointment", _w_scheduleAppointment)
_register_tool("getPatient360", _w_getPatient360)
log.info("[registry] %d tools registered: %s", len(_TOOL_REGISTRY), ", ".join(sorted(_TOOL_REGISTRY.keys())))

async def invoke_tool(name: str, args: Dict[str, Any]) -> Any:
    log.debug("[invoke] tool=%s args=%s", name, args)
    fn = _TOOL_REGISTRY[name]
    result = await fn(args)
    log.debug("[invoke] tool=%s -> %s", name, result)
    return result

def list_tools() -> List[str]:
    return list(_TOOL_REGISTRY.keys())

# ---- Schemas ---------------------------------------------------------------
# NOTE: repo structure: <root>/schemas/components.schema.json
# __file__ is .../src/medical_mcp_toolkit/mcp_server.py
# parents[3] == project root
_SCHEMAS_PATH = Path(__file__).resolve().parents[3] / "schemas" / "components.schema.json"

def get_components_schema() -> Dict[str, Any]:
    log.debug("[schema] loading %s", _SCHEMAS_PATH)
    with _SCHEMAS_PATH.open("r", encoding="utf-8") as f:
        data = json.load(f)
    log.debug("[schema] loaded keys=%s", list(data.keys()))
    return data

# =============================================================================
# SSE transport helpers
# =============================================================================
def _filter_kwargs(fn: Callable[..., Any], **kwargs: Any) -> Dict[str, Any]:
    """
    Return only kwargs accepted by the callable's signature.
    Also logs what is available and what will be used.
    """
    try:
        sig = inspect.signature(fn)
        accepted = set(sig.parameters)
        out = {k: v for k, v in kwargs.items() if k in accepted}
        log.debug("[introspect] %s accepts %s → using %s",
                  getattr(fn, "__name__", fn), sorted(accepted), out)
        return out
    except Exception:
        return {}

def _supports_params(fn: Callable[..., Any], *names: str) -> bool:
    try:
        sig = inspect.signature(fn)
    except Exception:
        return False
    accepted = set(sig.parameters)
    ok = all(n in accepted for n in names)
    log.debug("[introspect] %s has params %s ? %s", getattr(fn, "__name__", fn), names, ok)
    return ok

class _ASGILogger:
    """Tiny ASGI middleware to log method, path, query, and response status."""
    def __init__(self, app: Any) -> None:
        self.app = app
        self._log = logging.getLogger("mcp_server.asgi")

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        method = scope.get("method", "?")
        path = scope.get("path", "?")
        query = scope.get("query_string", b"").decode() if scope.get("query_string") else ""
        status_holder: Dict[str, Any] = {"status": None}

        async def _send(message):
            if message["type"] == "http.response.start":
                status_holder["status"] = message.get("status")
            return await send(message)

        try:
            await self.app(scope, receive, _send)
        finally:
            self._log.info("[http] %s %s%s -> %s",
                           method, path, f"?{query}" if query else "", status_holder["status"])

class _SuppressClosedResource:
    """
    ASGI middleware that suppresses anyio.ClosedResourceError raised by the
    underlying SSE app when the client has already closed its read stream.
    This avoids scary stacktraces in logs without touching the 'mcp' package.
    """
    def __init__(self, app: Any) -> None:
        self.app = app
        self._log = logging.getLogger("mcp_server.suppress")
        self._closed_exc = None
        try:
            import anyio  # type: ignore
            self._closed_exc = anyio.ClosedResourceError  # type: ignore[attr-defined]
        except Exception:
            self._closed_exc = None

    async def __call__(self, scope, receive, send):
        try:
            await self.app(scope, receive, send)
        except Exception as exc:
            if (self._closed_exc and isinstance(exc, self._closed_exc)) or exc.__class__.__name__ == "ClosedResourceError":
                self._log.debug("[sse] client stream already closed; suppressed %r", exc)
                return
            raise

def _compute_paths_from_signature(sse_app: Callable[..., Any]) -> Dict[str, Any]:
    """
    Best-effort deduction of the effective paths we will instruct FastMCP to use.
    We intentionally DO NOT pass mount_path to avoid writer mis-location.
    """
    sse_path = "/sse"
    message_path = os.getenv("MCP_MESSAGE_PATH", "/messages/")  # allow override
    try:
        sig = inspect.signature(sse_app)
        params = set(sig.parameters)
        log.debug("[serve] sse_app signature params=%s", sorted(params))
        # We only set params that are supported on this build
        kwargs: Dict[str, Any] = {}
        if "sse_path" in params:
            kwargs["sse_path"] = sse_path
        if "message_path" in params:
            kwargs["message_path"] = message_path
        return {"sse_path": sse_path, "message_path": message_path, "kwargs": kwargs}
    except Exception as exc:
        log.debug("[serve] failed to inspect sse_app signature: %r", exc)
        return {"sse_path": sse_path, "message_path": message_path, "kwargs": {}}

async def _serve_sse(mcp: Any, host: str, port: int) -> None:
    """
    Serve SSE with a guaranteed layout:
      GET  /sse
      POST /messages/   (writer; trailing slash typical for older builds)

    Strategy:
      - Prefer instance runner ONLY if it accepts 'message_path' (so we can
        guarantee the writer path). Otherwise fall back to sse_app where we
        can explicitly set sse_path/message_path and avoid any mount mismatch.
    """
    log.info("[boot] transport=sse host=%s port=%s", host, port)

    run_sse_async = getattr(mcp, "run_sse_async", None)
    has_instance = callable(run_sse_async)
    can_control_message_path = has_instance and _supports_params(run_sse_async, "message_path")  # type: ignore[arg-type]
    log.info("[sse] instance_runner=%s can_control_message_path=%s", has_instance, can_control_message_path)

    if has_instance and can_control_message_path:
        # Use the instance runner and set the exact desired paths.
        kwargs = _filter_kwargs(
            run_sse_async,  # type: ignore[arg-type]
            host=host,
            port=port,
            sse_path="/sse",
            message_path=os.getenv("MCP_MESSAGE_PATH", "/messages/"),
        )
        # IMPORTANT: do NOT pass mount_path; some builds ignore it for routing.
        kwargs.pop("mount_path", None)
        log.info("[sse] FastMCP.run_sse_async kwargs=%s", kwargs)
        await run_sse_async(**kwargs)  # type: ignore[misc]
        return

    # 2) Fallback: explicit ASGI via sse_app
    try:
        import uvicorn  # type: ignore
    except Exception as exc:  # pragma: no cover
        raise RuntimeError("uvicorn is required to serve the SSE app.") from exc

    if not hasattr(mcp, "sse_app"):
        raise RuntimeError("FastMCP missing .sse_app(); cannot create SSE ASGI app.")

    # Determine safe kwargs to avoid path mismatches (no mount_path)
    paths = _compute_paths_from_signature(mcp.sse_app)
    sse_path = paths["sse_path"]
    message_path = paths["message_path"]
    kwargs = paths["kwargs"]
    kwargs.pop("mount_path", None)

    log.info("[sse] building ASGI app with kwargs=%s", kwargs)
    try:
        asgi_app = mcp.sse_app(**kwargs) if kwargs else mcp.sse_app()  # type: ignore[misc]
    except Exception as exc:
        log.warning("[sse] sse_app(**kwargs) failed (%r). Trying legacy sse_app('/sse').", exc)
        asgi_app = mcp.sse_app(sse_path)  # type: ignore[misc]

    # Wrap: suppress ClosedResourceError noise → HTTP logger → app
    asgi_app = _SuppressClosedResource(asgi_app)
    asgi_app = _ASGILogger(asgi_app)

    uv_level = os.getenv("UVICORN_LOG_LEVEL", "info")
    log.info("[sse] effective endpoints: GET %s   POST %s", sse_path, message_path)
    log.info("[sse] starting uvicorn (level=%s) ...", uv_level)

    config = uvicorn.Config(asgi_app, host=host, port=port, log_level=uv_level, access_log=True)
    server = uvicorn.Server(config)
    await server.serve()

async def _run_stdio(mcp: Any) -> None:
    runner = getattr(mcp, "run_stdio_async", None)
    if not callable(runner):
        raise RuntimeError("FastMCP missing run_stdio_async()")
    log.info("[stdio] FastMCP.run_stdio_async() starting ...")
    await runner()  # type: ignore[misc]

# =============================================================================
# MCP bootstrap
# =============================================================================
async def run_mcp_async(transport: str = "sse", host: str = "0.0.0.0", port: int = 9090) -> None:
    """
    Start the MCP server using FastMCP.
    The server will expose:
      - SSE at  GET  /sse
      - Writer at POST /messages/    (default; controlled by MCP_MESSAGE_PATH)
    """
    log.info("[boot] transport=%s host=%s port=%s", transport, host, port)

    ctor_kwargs: Dict[str, Any] = _filter_kwargs(FastMCP, host=host, port=port)
    log.debug("[boot] FastMCP ctor kwargs=%s", ctor_kwargs)
    mcp = FastMCP("medical-mcp-toolkit", **ctor_kwargs)  # type: ignore[misc]
    log.info("[boot] FastMCP instance created: %s", mcp)

    # Register tools
    @mcp.tool(name="getPatient", description="Retrieve patient demographics")
    async def _t_get_patient(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_getPatient(payload)

    @mcp.tool(name="getPatientVitals", description="Retrieve latest vital signs")
    async def _t_get_patient_vitals(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_getPatientVitals(payload)

    @mcp.tool(name="getPatientMedicalProfile", description="Retrieve medical profile")
    async def _t_get_patient_med_profile(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_getPatientMedicalProfile(payload)

    @mcp.tool(name="calcClinicalScores", description="Calculate BMI/BSA/CrCl/eGFR")
    async def _t_calc_clinical_scores(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_calcClinicalScores(payload)

    @mcp.tool(name="getDrugInfo", description="Drug monograph")
    async def _t_get_drug_info(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_getDrugInfo(payload)

    @mcp.tool(name="getDrugInteractions", description="Drug-drug interactions")
    async def _t_get_drug_interactions(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_getDrugInteractions(payload)

    @mcp.tool(name="getDrugContraindications", description="Patient-specific contraindications")
    async def _t_get_drug_contraindications(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_getDrugContraindications(payload)

    @mcp.tool(name="getDrugAlternatives", description="Therapeutic alternatives")
    async def _t_get_drug_alternatives(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
        return await _w_getDrugAlternatives(payload)

    @mcp.tool(name="triageSymptoms", description="Acuity triage")
    async def _t_triage(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_triageSymptoms(payload)

    @mcp.tool(name="searchMedicalKB", description="KB semantic search")
    async def _t_kb(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_searchMedicalKB(payload)

    @mcp.tool(name="scheduleAppointment", description="Book appointment")
    async def _t_sched(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_scheduleAppointment(payload)

    @mcp.tool(name="getPatient360", description="Patient 360 view")
    async def _t_p360(payload: Dict[str, Any]) -> Dict[str, Any]:
        return await _w_getPatient360(payload)

    # Log from our own registry (some FastMCP builds don't expose mcp.tools)
    log.info(
        "[boot] %d tools registered with FastMCP: %s",
        len(_TOOL_REGISTRY),
        ", ".join(sorted(_TOOL_REGISTRY.keys())),
    )

    t = (transport or "sse").lower()
    if t == "sse":
        await _serve_sse(mcp, host=host, port=port)
    elif t == "stdio":
        await _run_stdio(mcp)
    else:
        raise ValueError(f"Unknown transport '{transport}'. Use 'sse' or 'stdio'.")
