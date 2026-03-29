from __future__ import annotations
from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel, EmailStr, SecretStr
from ..models.auth import RegisterIn, LoginIn, MeOut
from ..repos.users import create_user, get_user_by_email
from .passwords import hash_password, verify_password
from .sessions import create_session, revoke_session
from ..deps import get_current_user
from .reset import request_password_reset, perform_password_reset

router = APIRouter()

@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterIn):
    pw_hash = hash_password(payload.password)
    row = await create_user(email=str(payload.email), password_hash=pw_hash)
    if row:
        return {"ok": True, "created": True}
    raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

@router.post("/login", response_model=MeOut)
async def login(payload: LoginIn, request: Request, response: Response):
    user = await get_user_by_email(str(payload.email))
    if not user or not verify_password(payload.password, user["password_hash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    if not user.get("is_active", True):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Inactive account")
    await create_session(user_id=str(user["id"]), request=request, response=response)
    return MeOut(id=str(user["id"]), email=user["email"], is_verified=bool(user.get("is_verified", False)))

@router.post("/logout")
async def logout(request: Request, response: Response):
    await revoke_session(request, response)
    return {"ok": True}

@router.get("/me", response_model=MeOut)
async def me(user=Depends(get_current_user)):
    return MeOut(id=str(user["id"]), email=user["email"], is_verified=bool(user.get("is_verified", False)))

class ForgotPasswordIn(BaseModel):
    email: EmailStr

class ResetPasswordIn(BaseModel):
    token: str
    new_password: SecretStr

@router.post("/forgot-password")
async def forgot_password(payload: ForgotPasswordIn):
    await request_password_reset(payload.email)
    return {"ok": True}

@router.post("/reset-password")
async def reset_password(payload: ResetPasswordIn):
    try:
        await perform_password_reset(raw_token=payload.token, new_password=payload.new_password.get_secret_value())
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"ok": True}
