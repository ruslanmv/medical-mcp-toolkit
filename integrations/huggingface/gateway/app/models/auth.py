from __future__ import annotations
from pydantic import BaseModel, EmailStr, SecretStr, field_validator

class RegisterIn(BaseModel):
    email: EmailStr
    password: SecretStr
    @field_validator("password")
    @classmethod
    def password_length(cls, v: SecretStr) -> SecretStr:
        if len(v.get_secret_value()) < 8:
            raise ValueError("Password must be at least 8 characters long")
        return v

class LoginIn(BaseModel):
    email: EmailStr
    password: SecretStr

class MeOut(BaseModel):
    id: str
    email: EmailStr
    is_verified: bool = False
