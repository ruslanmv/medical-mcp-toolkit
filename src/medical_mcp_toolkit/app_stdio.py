import asyncio
from .mcp_server import run_mcp_async

if __name__ == "__main__":
    asyncio.run(run_mcp_async(transport="stdio"))
