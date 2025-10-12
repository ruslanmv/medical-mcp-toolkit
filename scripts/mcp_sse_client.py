#!/usr/bin/env python3
"""
Production-ready, version-tolerant MCP client for the Medical MCP Toolkit server.

Supports SSE transport (default for this project) and is resilient to SDK symbol changes.

Examples:
  # List tools
  python scripts/mcp_sse_client.py --url http://localhost:9090/sse list-tools

  # Demo triage call
  python scripts/mcp_sse_client.py --url http://localhost:9090/sse triage

  # Invoke any tool with JSON args
  python scripts/mcp_sse_client.py --url http://localhost:9090/sse invoke \
      --tool triageSymptoms \
      --args '{"age":45,"sex":"male","symptoms":["chest pain","sweating"],"duration_text":"2 hours"}'
"""
from __future__ import annotations

import argparse
import asyncio
import importlib
import inspect
import json
import os
import sys
from typing import Any, Dict, Tuple, Callable, Awaitable

# ---- Pretty print ----------------------------------------------------------
def _pprint(obj: Any) -> None:
    """Robust JSON pretty printer (prefers orjson when available)."""
    try:
        import orjson  # type: ignore
        print(orjson.dumps(obj, option=orjson.OPT_INDENT_2).decode("utf-8"))
    except Exception:
        print(json.dumps(obj, indent=2, ensure_ascii=False))


# ---- URL helpers -----------------------------------------------------------
def _normalize_base_url(url: str) -> str:
    """
    Normalize the server base URL:
      - Strip trailing slash ("/sse/" -> "/sse")
    """
    url = (url or "").strip()
    if not url:
        raise ValueError("Missing --url")
    # Remove a single trailing slash except when the URL is only "/"
    if url.endswith("/") and len(url) > 1:
        url = url[:-1]
    return url


# ---- Dynamic import helpers ------------------------------------------------
def _resolve_mcp_connect():
    """
    Obtain an async SSE client/context-manager factory from mcp.client.sse,
    regardless of the version's exported symbol name.

    Expected usage:
        async with connect(url, headers=...) as (read, write):
    """
    try:
        sse_mod = importlib.import_module("mcp.client.sse")
    except Exception as e:  # pragma: no cover
        raise ImportError("Unable to import mcp.client.sse") from e

    # Common symbol names across versions (most SDKs use `sse_client`)
    candidates = ("sse_client", "sse_connect", "connect_sse", "connect")
    for name in candidates:
        fn = getattr(sse_mod, name, None)
        # Accept any callable; many SDKs expose an async *context manager* factory,
        # which is not a coroutinefunction.
        if callable(fn):
            return fn

    # Last resort: scan for any callable with 'sse' and ('client' or 'connect') in the name
    for name, obj in vars(sse_mod).items():
        lname = name.lower()
        if callable(obj) and "sse" in lname and ("client" in lname or "connect" in lname):
            return obj

    raise ImportError(
        "Could not find an SSE connect factory in mcp.client.sse. "
        "Upgrade the 'mcp' package (e.g., pip install -U 'mcp>=1.1,<2')."
    )


def _resolve_client_api():
    """
    Prefer modern ClientSession API; fall back to legacy Client.
    Returns a tuple: (mode, cls)
      - mode = 'session' or 'client'
      - cls  = ClientSession class or Client class
    """
    # Modern API
    try:
        session_mod = importlib.import_module("mcp.client.session")
        ClientSession = getattr(session_mod, "ClientSession", None)
        if ClientSession is not None:
            return "session", ClientSession
    except Exception:
        pass

    # Legacy API
    try:
        mcp_root = importlib.import_module("mcp")
        Client = getattr(mcp_root, "Client", None)
        if Client is not None:
            return "client", Client
    except Exception:
        pass

    # Very old fallback
    try:
        mcp_client_mod = importlib.import_module("mcp.client")
        Client = getattr(mcp_client_mod, "Client", None)
        if Client is not None:
            return "client", Client
    except Exception as e:  # pragma: no cover
        raise ImportError("Unable to import MCP client API") from e

    raise ImportError("No usable MCP client API found (ClientSession or Client).")


# ---- Connection wrapper ----------------------------------------------------
async def _connect(url: str, token: str | None, debug: bool = False):
    """
    Open a connection to the MCP SSE server.

    Returns a tuple of (mode, client_or_session, aclose_callable)
      - mode: 'session' or 'client'
      - client_or_session: an initialized object ready to use
      - aclose_callable: async callable to close the connection/session
    """
    connect = _resolve_mcp_connect()
    mode, client_cls = _resolve_client_api()

    headers: Dict[str, str] = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    base_url = _normalize_base_url(url)
    ctx = connect(base_url, headers=headers)

    cm = ctx if hasattr(ctx, "__aenter__") else None
    if cm is None:
        raise RuntimeError("Resolved connect factory did not return an async context manager.")

    async def _close():
        try:
            await cm.__aexit__(None, None, None)  # type: ignore[attr-defined]
        except Exception:
            if debug:
                print("[debug] error during close; ignoring", file=sys.stderr)
            pass

    # Enter the async context manager (this may raise if writer/reader fail)
    try:
        read, write = await cm.__aenter__()  # type: ignore[attr-defined]
    except Exception as e:
        # Add a friendly hint for the common 404 writer-path mismatch
        msg = str(e)
        if ("404" in msg or "Not Found" in msg) and "/messages" in msg:
            raise RuntimeError(
                "Server returned 404 for the SSE writer endpoint.\n"
                "Ensure your server mounts SSE at '/sse' AND the writer at '/sse/messages/'.\n"
                f"Client base URL: {base_url}\nOriginal error: {e}"
            ) from e
        raise

    if mode == "session":
        # Modern: ClientSession(read, write)
        session = client_cls(read, write)
        await session.initialize()
        return mode, session, _close

    # Legacy: Client(read, write)
    client = client_cls(read, write)
    await client.initialize()
    return mode, client, _close


# ---- Commands --------------------------------------------------------------
async def cmd_list_tools(url: str, token: str | None, debug: bool = False) -> None:
    mode, obj, aclose = await _connect(url, token, debug=debug)
    try:
        tools = await obj.list_tools()
        print("== Tools ==")
        _pprint(tools)
    finally:
        await aclose()


async def cmd_invoke(url: str, token: str | None, tool: str, args: Dict[str, Any], debug: bool = False) -> None:
    mode, obj, aclose = await _connect(url, token, debug=debug)
    try:
        print(f"== Invoking '{tool}' with args ==")
        _pprint(args)
        result = await obj.call_tool(tool, arguments=args)
        print("== Result ==")
        _pprint(result)
    finally:
        await aclose()


async def cmd_triage_demo(url: str, token: str | None, debug: bool = False) -> None:
    demo_args = {
        "age": 45,
        "sex": "male",
        "symptoms": ["chest pain", "sweating"],
        "duration_text": "2 hours",
    }
    await cmd_invoke(url, token, "triageSymptoms", demo_args, debug=debug)


# ---- CLI -------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Production-ready MCP client (version-tolerant SSE) for Medical MCP Toolkit"
    )
    parser.add_argument(
        "--url",
        default=os.getenv("MCP_URL", "http://localhost:9090/sse"),
        help="Server base URL for SSE (default: %(default)s or env MCP_URL). "
             "Pass without trailing slash (both '/sse' and '/sse/' are accepted).",
    )
    parser.add_argument(
        "--token",
        default=os.getenv("BEARER_TOKEN") or os.getenv("TOKEN"),
        help="Bearer token if your server requires it (env BEARER_TOKEN or TOKEN).",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable verbose debug output.",
    )

    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list-tools", help="List available tools")

    p_invoke = sub.add_parser("invoke", help="Invoke a tool with JSON args")
    p_invoke.add_argument("--tool", required=True, help="Tool name")
    p_invoke.add_argument(
        "--args",
        required=True,
        help='JSON string with arguments, e.g. \'{"age":45,"sex":"male",...}\'',
    )

    sub.add_parser("triage", help="Run a demo triageSymptoms call")

    args = parser.parse_args()

    try:
        if args.cmd == "list-tools":
            asyncio.run(cmd_list_tools(args.url, args.token, debug=args.debug))
        elif args.cmd == "invoke":
            try:
                payload = json.loads(args.args)
                if not isinstance(payload, dict):
                    raise ValueError("args must be a JSON object")
            except Exception as e:
                print(f"[error] failed to parse --args JSON: {e}", file=sys.stderr)
                return 2
            asyncio.run(cmd_invoke(args.url, args.token, args.tool, payload, debug=args.debug))
        elif args.cmd == "triage":
            asyncio.run(cmd_triage_demo(args.url, args.token, debug=args.debug))
        else:
            parser.print_help()
            return 2
    except KeyboardInterrupt:
        print("\n[client] interrupted.")
    except Exception as e:
        # Provide a concise, user-friendly error plus the original exception
        print(f"[client] error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
