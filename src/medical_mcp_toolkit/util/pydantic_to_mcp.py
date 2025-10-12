from __future__ import annotations
from typing import Any, Dict, Type
from pydantic import BaseModel


def model_json_schema(model: Type[BaseModel]) -> Dict[str, Any]:
    """Return JSON Schema for a Pydantic v2 model (draft 2020-12)."""
    return model.model_json_schema()
