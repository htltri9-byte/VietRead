"""Băm mật khẩu (passlib/bcrypt) và tạo/kiểm tra token JWT (python-jose)."""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from .database import get_db  # import trước để nạp .env
from .models import User

# Băm mật khẩu bằng bcrypt
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

SECRET_KEY = os.getenv("SECRET_KEY", "vietread-dev-secret-change-me")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "10080"))

# Đọc header Authorization: Bearer <token>
_bearer_scheme = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    """Băm mật khẩu người dùng để lưu vào cột PasswordHash."""
    return pwd_context.hash(password)


def verify_password(plain_password: str, password_hash: str) -> bool:
    """So khớp mật khẩu nhập vào với hash đã lưu; trả về False nếu hash hỏng."""
    try:
        return pwd_context.verify(plain_password, password_hash)
    except (ValueError, TypeError):
        return False


def create_access_token(user_id: int) -> str:
    """Ký token JWT chứa user_id (sub) và thời hạn hết hạn (exp)."""
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {"sub": str(user_id), "exp": expire}
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    """Dependency: đọc Bearer token, trả về user đăng nhập; 401 nếu token sai/hết hạn."""
    if credentials is None or not credentials.credentials:
        raise HTTPException(status_code=401, detail="Chưa đăng nhập (thiếu token)")
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = int(payload.get("sub", ""))
    except (JWTError, ValueError, TypeError):
        raise HTTPException(
            status_code=401, detail="Token không hợp lệ hoặc đã hết hạn"
        )
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=401, detail="Token không hợp lệ hoặc đã hết hạn"
        )
    return user


def get_current_user_optional(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)],
    db: Annotated[Session, Depends(get_db)],
) -> User | None:
    """Như get_current_user nhưng không ném lỗi: trả về None khi thiếu/sai token.

    Dùng cho các endpoint GET cho phép cả khách (ví dụ xem truyện nháp của chính mình).
    """
    if credentials is None or not credentials.credentials:
        return None
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = int(payload.get("sub", ""))
    except (JWTError, ValueError, TypeError):
        return None
    return db.get(User, user_id)
