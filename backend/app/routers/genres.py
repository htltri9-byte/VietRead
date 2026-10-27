"""API thể loại: GET /genres → [ { id, name } ]."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Genre
from ..schemas import GenreOut

router = APIRouter(tags=["genres"])


@router.get("/genres", response_model=list[GenreOut])
def list_genres(db: Session = Depends(get_db)) -> list[GenreOut]:
    """Toàn bộ thể loại, sắp xếp theo tên — dùng cho chip lọc ở trang chủ."""
    rows = db.execute(select(Genre).order_by(Genre.name)).scalars().all()
    return [GenreOut(id=g.id, name=g.name) for g in rows]
