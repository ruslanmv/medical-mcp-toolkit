from __future__ import annotations

from typing import Any, Optional

try:
    import psycopg
    from psycopg_pool import AsyncConnectionPool  # type: ignore
except Exception:  # pragma: no cover
    psycopg = None
    AsyncConnectionPool = None  # type: ignore

from .config import get_db_dsn

_pool: Optional["AsyncConnectionPool"] = None

async def get_pool() -> "AsyncConnectionPool":
    global _pool
    if _pool is None:
        dsn = get_db_dsn()
        if not dsn:
            raise RuntimeError("DATABASE_URL not configured")
        _pool = AsyncConnectionPool(dsn, min_size=1, max_size=10, open=True)  # type: ignore
    return _pool

async def fetchrow(sql: str, *args: Any) -> Optional[dict]:
    pool = await get_pool()
    async with pool.connection() as conn:  # type: ignore[union-attr]
        async with conn.cursor(row_factory=psycopg.rows.dict_row) as cur:  # type: ignore
            await cur.execute(sql, args)
            return await cur.fetchone()

async def fetch(sql: str, *args: Any) -> list[dict]:
    pool = await get_pool()
    async with pool.connection() as conn:  # type: ignore[union-attr]
        async with conn.cursor(row_factory=psycopg.rows.dict_row) as cur:  # type: ignore
            await cur.execute(sql, args)
            rows = await cur.fetchall()
            return list(rows)

async def execute(sql: str, *args: Any) -> int:
    pool = await get_pool()
    async with pool.connection() as conn:  # type: ignore[union-attr]
        async with conn.cursor() as cur:  # type: ignore
            await cur.execute(sql, args)
            return cur.rowcount or 0
