# gateway/app/db.py — SQLite async database layer
from __future__ import annotations

import logging
import os
from pathlib import Path

import aiosqlite

from .config import settings

log = logging.getLogger("gateway.db")

_DB_PATH: str = settings.database_path


def _schema_path() -> str:
    return os.path.join(os.path.dirname(__file__), "schema.sql")


async def init_db() -> None:
    os.makedirs(os.path.dirname(_DB_PATH), exist_ok=True)
    schema_sql = Path(_schema_path()).read_text()
    async with aiosqlite.connect(_DB_PATH) as db:
        await db.executescript(schema_sql)
        await db.commit()
    log.info("SQLite database initialized at %s", _DB_PATH)


async def get_conn() -> aiosqlite.Connection:
    conn = await aiosqlite.connect(_DB_PATH)
    conn.row_factory = aiosqlite.Row
    return conn


def row_to_dict(row) -> dict | None:
    if row is None:
        return None
    return dict(row)
