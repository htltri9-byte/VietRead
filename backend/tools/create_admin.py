"""Tạo (hoặc nâng quyền) tài khoản Admin cho VietRead — chạy TAY, không hardcode.

Email & mật khẩu nhận từ THAM SỐ DÒNG LỆNG hoặc BIẾN MÔI TRƯỜNG:

    # tham số dòng lệnh
    python tools/create_admin.py admin@vietread.vn 'MatKhauManh@2026'

    # biến môi trường (PowerShell)
    $env:ADMIN_EMAIL='admin@vietread.vn'; $env:ADMIN_PASSWORD='MatKhauManh@2026'
    python tools/create_admin.py

    # chỉ nâng quyền tài khoản đã tồn tại (giữ nguyên mật khẩu)
    python tools/create_admin.py admin@vietread.vn

Cách chạy (từ thư mục backend/, môi trường ảo .venv):
    .venv/Scripts/python.exe tools/create_admin.py admin@vietread.vn 'MatKhau@123'
Linux/macOS: .venv/bin/python tools/create_admin.py ...

Hành vi (idempotent):
- Email chưa có  → tạo user mới Role='admin' với mật khẩu cho vào.
- Email đã có     → đặt Role='admin' (và đổi mật khẩu nếu có truyền mật khẩu).
- Thiếu email     → báo lỗi, không đoán, không dùng mật khẩu mặc định.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Cho phép chạy từ bất kỳ thư mục nào: đưa thư mục backend/ vào sys.path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import security  # noqa: E402  (import sau khi đã thêm sys.path)
from app.database import SessionLocal  # noqa: E402
from app.models import User  # noqa: E402
from sqlalchemy import select  # noqa: E402


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    email = (args[0] if len(args) > 0 else os.getenv("ADMIN_EMAIL", "")).strip().lower()
    password = args[1] if len(args) > 1 else os.getenv("ADMIN_PASSWORD", "")

    if not email or "@" not in email:
        print(
            "LỖI: thiếu email admin. Truyền positional hoặc biến môi trường:\n"
            "  python tools/create_admin.py <email> [mat_khau]\n"
            "  ADMIN_EMAIL=... ADMIN_PASSWORD=... python tools/create_admin.py",
            file=sys.stderr,
        )
        return 2
    if not password and len(args) >= 2:
        print("LỖI: mật khẩu rỗng.", file=sys.stderr)
        return 2

    db = SessionLocal()
    try:
        user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
        if user is None:
            if not password:
                print(
                    f"LỖI: tài khoản {email} chưa tồn tại — cần mật khẩu để tạo mới.",
                    file=sys.stderr,
                )
                return 2
            user = User(
                name=email.split("@")[0],
                email=email,
                password_hash=security.hash_password(password),
                role="admin",
            )
            db.add(user)
            action = "TẠO MỚI"
        else:
            changed = []
            if user.role != "admin":
                user.role = "admin"
                changed.append("nâng quyền lên admin")
            if password:
                user.password_hash = security.hash_password(password)
                changed.append("đổi mật khẩu")
            action = "CẬP NHẬT (" + (", ".join(changed) or "giữ nguyên") + ")"
        db.commit()
        db.refresh(user)
    finally:
        db.close()

    print(f"OK — {action}: {email} (id={user.id}, role={user.role})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
