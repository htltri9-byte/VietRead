"""POST /dictionary/names — thêm tên riêng cho từ điển dịch offline, không cần restart.

Chỉ làm backend (không cần sửa UI Flutter): ghi nối một dòng vào
`backend/dictionaries/names.txt` rồi nạp lại vào bộ nhớ bằng
`vietphrase.reload_names()`.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, field_validator

from .. import vietphrase

router = APIRouter(prefix="/dictionary", tags=["dictionary"])


class NameAdd(BaseModel):
    """Body POST /dictionary/names: { "zh": "李明", "vi": "Lý Minh" }."""

    zh: str = Field(min_length=1, max_length=64, description="Tên tiếng Trung")
    vi: str = Field(min_length=1, max_length=128, description="Cách đọc tiếng Việt")

    @field_validator("zh", "vi")
    @classmethod
    def _strip(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Không được để trống")
        if "=" in value or "\n" in value or "\r" in value:
            raise ValueError("Không được chứa ký tự = hoặc xuống dòng")
        return value


@router.post("/names")
def add_name(body: NameAdd) -> dict:
    """Ghi thêm dòng `zh=vi` vào names.txt và nạp lại ngay vào bộ nhớ."""
    path = Path(vietphrase.DICT_DIR) / "names.txt"
    path.parent.mkdir(parents=True, exist_ok=True)

    # Đảm bảo file kết thúc bằng xuống dòng trước khi nối thêm
    need_newline = False
    if path.exists() and path.stat().st_size > 0:
        with open(path, "rb") as fh:
            fh.seek(-1, 2)
            need_newline = fh.read(1) != b"\n"

    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        if need_newline:
            fh.write("\n")
        fh.write(f"{body.zh}={body.vi}\n")

    try:
        count = vietphrase.reload_names()
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Không ghi được names.txt: {exc}")

    return {"ok": True, "zh": body.zh, "vi": body.vi, "names": count}
