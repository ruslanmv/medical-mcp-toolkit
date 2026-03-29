# gateway/app/config.py — HuggingFace Spaces version (SQLite + HF Inference)
from __future__ import annotations

import json
import os
from typing import List, Optional

from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator


class Settings(BaseSettings):
    env: str = "dev"
    log_level: str = "INFO"
    database_path: str = "/app/data/medical.db"
    allowed_origins: List[str] = ["*"]
    allow_credentials: bool = True
    session_cookie_name: str = "sid"
    session_ttl_seconds: int = 60 * 60 * 24 * 30
    session_secure_cookies: bool = True
    session_samesite: str = "none"
    cookie_secret: str = "hf-space-medical-hospital-secret-32B"
    hf_token: Optional[str] = os.environ.get("HF_TOKEN", "")
    hf_model_id: str = "mistralai/Mistral-7B-Instruct-v0.3"
    frontend_base_url: str = ""
    password_reset_ttl_seconds: int = 3600

    model_config = SettingsConfigDict(
        env_file=".env", env_prefix="", case_sensitive=False, extra="ignore",
    )

    @field_validator("allowed_origins", mode="before")
    @classmethod
    def _parse_allowed_origins(cls, v):
        if isinstance(v, list):
            return v
        if isinstance(v, str):
            s = v.strip()
            if s.startswith("[") and s.endswith("]"):
                try:
                    parsed = json.loads(s)
                    if isinstance(parsed, list):
                        return [str(x).strip() for x in parsed if str(x).strip()]
                except Exception:
                    pass
            return [s2.strip() for s2 in s.split(",") if s2.strip()]
        return v


settings = Settings()
