import asyncio
from .mcp_server import run_mcp_async

if __name__ == "__main__":
    asyncio.run(run_mcp_async(transport="sse", host="0.0.0.0", port=9090))
