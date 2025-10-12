from __future__ import annotations
from enum import Enum

class Sex(str, Enum):
    male = "male"
    female = "female"
    intersex = "intersex"
    other = "other"
    unknown = "unknown"

class AcuityLevel(str, Enum):
    EMERGENT = "EMERGENT"
    URGENT = "URGENT"
    ROUTINE = "ROUTINE"

class RiskLevel(str, Enum):
    LOW = "LOW"
    MODERATE = "MODERATE"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"
