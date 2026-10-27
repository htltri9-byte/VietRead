"""Từ điển cá nhân — thêm / liệt kê / xoá tên riêng cho từ điển dịch offline.

- ``POST   /dictionary/names`` — thêm ``zh=vi`` (+ tags tuỳ chọn) vào
  ``dictionaries/names.txt`` và nạp lại ngay bằng ``vietphrase.reload_names()``
  → từ mới được dùng để dịch các chương **tiếp theo** (import link/văn bản,
  dịch lại), không cần restart.
- ``GET    /dictionary/names`` — danh sách từ của người đang đăng nhập.
- ``DELETE /dictionary/names/{wordId}`` — xoá một từ của chính mình (gỡ luôn
  dòng trong ``names.txt`` rồi nạp lại).

Bảng ``DictionaryWords`` chỉ là sổ theo dõi của từng người dùng; từ điển dịch
thật vẫn nằm trong ``names.txt`` (dùng chung cho toàn bộ chương được dịch).
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import marking, security, vietphrase
from ..database import get_db
from ..models import DictionaryWord, User
from ..schemas import DictionaryWordOut

router = APIRouter(prefix="/dictionary", tags=["dictionary"])


class NameAdd(BaseModel):
    """Body POST /dictionary/names: { "zh": "李明", "vi": "Lý Minh", "tags" }. """

    model_config = ConfigDict(populate_by_name=True)

    zh: str = Field(min_length=1, max_length=100, description="Tên tiếng Trung")
    vi: str = Field(min_length=1, max_length=200, description="Cách đọc tiếng Việt")
    tags: str | None = Field(default=None, max_length=200, alias="tags")

    @field_validator("zh", "vi")
    @classmethod
    def _strip(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Không được để trống")
        if "=" in value or "\n" in value or "\r" in value:
            raise ValueError("Không được chứa ký tự = hoặc xuống dòng")
        if "{" in value or "}" in value:
            raise ValueError("Không được chứa dấu { hoặc } (dấu marker nhiều nghĩa)")
        return value

    @field_validator("tags")
    @classmethod
    def _clean_tags(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = ",".join(part.strip() for part in value.split(",") if part.strip())
        if not value:
            return None
        if "\n" in value or "\r" in value:
            raise ValueError("Tags không được xuống dòng")
        return value


def _names_file() -> Path:
    return Path(vietphrase.DICT_DIR) / "names.txt"


def _detect_encoding(path: Path) -> str:
    """Tự nhận encoding theo BOM — khớp [vietphrase._detect_encoding]."""
    with open(path, "rb") as fh:
        start = fh.read(4)
    if start[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return "utf-16"
    if start[:3] == b"\xef\xbb\xbf":
        return "utf-8-sig"
    return "utf-8"


def _remove_name_from_file(zh: str) -> bool:
    """Gỡ mọi dòng `zh=...` trong names.txt — trả True nếu có dòng bị gỡ."""
    path = _names_file()
    if not path.exists():
        return False
    encoding = _detect_encoding(path)
    with open(path, encoding=encoding) as fh:
        lines = fh.readlines()
    kept = [line for line in lines if line.split("=", 1)[0].strip() != zh]
    if len(kept) == len(lines):
        return False
    with open(path, "w", encoding=encoding, newline="") as fh:
        fh.writelines(kept)
    return True


def _word_out(row: DictionaryWord) -> DictionaryWordOut:
    return DictionaryWordOut(
        id=row.id,
        zh=row.zh,
        vi=row.vi,
        tags=row.tags,
        createdAt=row.created_at,
    )


def _require_word(db: Session, user: User, word_id: int) -> DictionaryWord:
    """Lấy từ của người đang đăng nhập; không có → 404."""
    row = db.get(DictionaryWord, word_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Không tìm thấy từ trong từ điển")
    return row


@router.post("/names")
def add_name(
    body: NameAdd,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Thêm một từ vào từ điển (cần đăng nhập) — ghi `names.txt` + nạp lại ngay.

    Từ mới được dùng để dịch các chương dịch **sau này** (import link/văn bản,
    "Dịch lại có gợi ý nghĩa"); chương đã lưu trước đó cần dịch lại mới đổi.
    """
    existing = db.execute(
        select(DictionaryWord).where(
            DictionaryWord.user_id == user.id, DictionaryWord.zh == body.zh
        )
    ).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(
            status_code=400,
            detail=f"Từ '{body.zh}' đã có trong từ điển của bạn",
        )

    path = _names_file()
    path.parent.mkdir(parents=True, exist_ok=True)

    # Trùng dòng cũ trong names.txt (thêm trực tiếp từ script/phiên khác) →
    # gỡ trước để từ mới là ý nghĩa cuối cùng được nạp.
    _remove_name_from_file(body.zh)

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

    row = DictionaryWord(user_id=user.id, zh=body.zh, vi=body.vi, tags=body.tags)
    db.add(row)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(
            status_code=400, detail=f"Từ '{body.zh}' đã có trong từ điển của bạn"
        ) from exc
    db.refresh(row)

    try:
        count = vietphrase.reload_names()
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Không ghi được names.txt: {exc}") from exc

    return {
        "ok": True,
        "zh": row.zh,
        "vi": row.vi,
        "tags": row.tags,
        "word": _word_out(row).model_dump(mode="json", by_alias=True),
        "names": count,
    }


@router.get("/names", response_model=list[DictionaryWordOut])
def list_names(
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> list[DictionaryWordOut]:
    """Danh sách từ của người đang đăng nhập (mới thêm trước)."""
    rows = (
        db.execute(
            select(DictionaryWord)
            .where(DictionaryWord.user_id == user.id)
            .order_by(DictionaryWord.id.desc())
        )
        .scalars()
        .all()
    )
    return [_word_out(row) for row in rows]


@router.delete("/names/{word_id}")
def delete_name(
    word_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Xoá một từ của chính mình — gỡ khỏi names.txt rồi nạp lại ngay."""
    row = _require_word(db, user, word_id)
    zh = row.zh
    db.delete(row)
    db.commit()

    _remove_name_from_file(zh)
    try:
        vietphrase.reload_names()
    except OSError:
        # names.txt không ghi được vẫn xoá được sổ theo dõi — báo rõ cho user
        raise HTTPException(
            status_code=500,
            detail="Đã xoá khỏi danh sách nhưng không ghi được names.txt",
        )
    return {"message": "Đã xoá khỏi từ điển"}


@router.post("/mark-lists/reload")
def reload_mark_lists(user: User = Depends(security.get_current_user)) -> dict:
    """Nạp lại 3 file danh sách marker — không cần restart server.

    `dictionaries/no_mark.txt` (trợ từ… không đánh dấu), `ambiguous.txt`
    (danh sách trắng đa nghĩa), `synonyms.txt` (danh sách đen đồng nghĩa).
    (Các file này cũng tự nạp lại khi mtime đổi — endpoint để chủ động + báo số.)
    """
    lists = marking.reload_lists()
    return {
        "ok": True,
        "noMark": len(lists.no_mark),
        "ambiguous": len(lists.ambiguous),
        "synonyms": len(lists.synonyms),
    }


__all__ = ["router", "NameAdd"]
