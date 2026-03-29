from __future__ import annotations
from typing import Union
from pydantic import SecretStr
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHash, VerificationError, VerifyMismatchError

_ph = PasswordHasher(time_cost=3, memory_cost=64 * 1024, parallelism=2, hash_len=32, salt_len=16)
Plain = Union[str, SecretStr]

def _to_plain(pw: Plain) -> str:
    return pw.get_secret_value() if isinstance(pw, SecretStr) else pw

def hash_password(plain_password: Plain) -> str:
    return _ph.hash(_to_plain(plain_password))

def verify_password(plain_password: Plain, password_hash: str) -> bool:
    try:
        return _ph.verify(password_hash, _to_plain(plain_password))
    except (VerifyMismatchError, VerificationError, InvalidHash):
        return False
