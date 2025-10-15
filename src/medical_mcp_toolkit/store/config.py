from __future__ import annotations
import os
from dotenv import load_dotenv

load_dotenv()

def get_db_dsn() -> str | None:
    return os.getenv("DATABASE_URL")

def have_db() -> bool:
    return bool(get_db_dsn())
