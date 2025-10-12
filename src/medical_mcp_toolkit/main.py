from __future__ import annotations
import asyncio
import logging
import os
from .mcp_server import run_mcp_async

log = logging.getLogger("main")
if not log.handlers:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")

async def main_async(mode: str = "SSE") -> None:
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8080"))
    log.info("[main] starting transport=%s host=%s port=%s", mode, host, port)
    await run_mcp_async(transport=mode.lower(), host=host, port=port)
