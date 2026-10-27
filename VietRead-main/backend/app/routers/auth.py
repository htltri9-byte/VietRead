"""API xác thực: POST /auth/register và POST /auth/login → { token, user }."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..models import User
from ..schemas import LoginRequest, RegisterRequest, TokenResponse, UserOut, user_to_out

router = APIRouter(prefix="/auth", tags=["auth"])


def _issue_token(user: User) -> TokenResponse:
    """Tạo response { token, user } cho người dùng vừa đăng ký/đăng nhập."""
    return TokenResponse(token=security.create_access_token(user.id), user=user_to_out(user))


@router.post("/register", response_model=TokenResponse)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """Đăng ký tài khoản mới; email trùng → 400, thành công → { token, user }."""
    exists = db.execute(
        select(User.id).where(User.email == payload.email)
    ).scalar_one_or_none()
    if exists is not None:
        raise HTTPException(status_code=400, detail="Email đã được sử dụng")

    user = User(
        name=payload.name,
        email=payload.email,
        password_hash=security.hash_password(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _issue_token(user)


@router.get("/me", response_model=UserOut)
def me(current_user: User = Depends(security.get_current_user)) -> UserOut:
    """Kiểm tra token: trả về user của request đang kèm Authorization: Bearer <token>."""
    return user_to_out(current_user)


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """Đăng nhập bằng email + mật khẩu; sai thông tin → 401."""
    user = db.execute(
        select(User).where(User.email == payload.email)
    ).scalar_one_or_none()
    if user is None or not security.verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Email hoặc mật khẩu không đúng")
    return _issue_token(user)
