from __future__ import annotations
from datetime import datetime
from typing import Optional
from .. import db

async def create_user(*, email: str, password_hash: str, password_algo: str = "argon2id", display_name: Optional[str] = None, phone: Optional[str] = None) -> dict | None:
    conn = await db.get_conn()
    try:
        cursor = await conn.execute("SELECT id FROM users WHERE email = ? COLLATE NOCASE", (email,))
        if await cursor.fetchone():
            return None
        await conn.execute("INSERT INTO users (email, password_hash, password_algo, display_name, phone) VALUES (?, ?, ?, ?, ?)", (email, password_hash, password_algo, display_name, phone))
        await conn.commit()
        cursor = await conn.execute("SELECT id, email, is_verified, created_at FROM users WHERE email = ? COLLATE NOCASE", (email,))
        return db.row_to_dict(await cursor.fetchone())
    finally:
        await conn.close()

async def get_user_by_email(email: str) -> dict | None:
    conn = await db.get_conn()
    try:
        cursor = await conn.execute("SELECT * FROM users WHERE email = ? COLLATE NOCASE", (email,))
        return db.row_to_dict(await cursor.fetchone())
    finally:
        await conn.close()

async def get_user_by_id(user_id: str) -> dict | None:
    conn = await db.get_conn()
    try:
        cursor = await conn.execute("SELECT * FROM users WHERE id = ?", (user_id,))
        return db.row_to_dict(await cursor.fetchone())
    finally:
        await conn.close()

async def insert_session(*, user_id: str, token_hash: str, expires_at: datetime, ip_address: Optional[str], user_agent: Optional[str]) -> dict:
    conn = await db.get_conn()
    try:
        await conn.execute("INSERT INTO auth_sessions (user_id, session_token_hash, ip_address, user_agent, expires_at) VALUES (?, ?, ?, ?, ?)", (user_id, token_hash, ip_address, user_agent, expires_at.isoformat()))
        await conn.commit()
        cursor = await conn.execute("SELECT id, user_id, expires_at FROM auth_sessions WHERE session_token_hash = ?", (token_hash,))
        row = await cursor.fetchone()
        if not row:
            raise RuntimeError("Session insertion failed")
        return db.row_to_dict(row)
    finally:
        await conn.close()

async def get_session_by_token_hash(token_hash: str) -> dict | None:
    conn = await db.get_conn()
    try:
        cursor = await conn.execute("SELECT id, user_id, expires_at FROM auth_sessions WHERE session_token_hash = ? AND (expires_at IS NULL OR expires_at > datetime('now')) AND revoked_at IS NULL", (token_hash,))
        return db.row_to_dict(await cursor.fetchone())
    finally:
        await conn.close()

async def delete_session_by_token_hash(token_hash: str) -> None:
    conn = await db.get_conn()
    try:
        await conn.execute("UPDATE auth_sessions SET revoked_at = datetime('now') WHERE session_token_hash = ?", (token_hash,))
        await conn.commit()
    finally:
        await conn.close()

async def update_password_hash(user_id: str, new_hash: str, algo: str = "argon2id") -> None:
    conn = await db.get_conn()
    try:
        await conn.execute("UPDATE users SET password_hash = ?, password_algo = ? WHERE id = ?", (new_hash, algo, user_id))
        await conn.commit()
    finally:
        await conn.close()

async def revoke_all_sessions_for_user(user_id: str) -> None:
    conn = await db.get_conn()
    try:
        await conn.execute("UPDATE auth_sessions SET revoked_at = datetime('now') WHERE user_id = ? AND revoked_at IS NULL", (user_id,))
        await conn.commit()
    finally:
        await conn.close()
