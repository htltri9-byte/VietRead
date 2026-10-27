"""Kết nối tới SQL Server qua SQLAlchemy + pyodbc, khai báo session."""

from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker

# Đọc biến môi trường từ backend/.env (file này không commit lên git)
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(ENV_FILE)

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
if not DATABASE_URL:
    raise RuntimeError(
        "Thiếu biến DATABASE_URL. Hãy copy backend/.env.example thành backend/.env "
        "và điền chuỗi kết nối SQL Server (xem backend/README.md)."
    )

# pool_pre_ping: kiểm tra kết nối trước mỗi lần dùng lại pool (tránh kết nối chết)
engine = create_engine(DATABASE_URL, pool_pre_ping=True, future=True)

# Factory tạo Session cho mỗi request
SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    """Lớp cơ sở cho toàn bộ model ORM."""


def get_db():
    """Dependency FastAPI: mở một session CSDL và đóng lại khi xong request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def ping_database() -> None:
    """Gửi câu SELECT 1 để kiểm tra kết nối SQL Server; ném lỗi nếu mất kết nối."""
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
