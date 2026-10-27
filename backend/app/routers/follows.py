"""API theo dõi truyện: POST/DELETE /follows/{id}, GET /me/follows (Phần B).

Tab "Theo dõi" ở Tủ sách (A3.7, Bước 7) đọc dữ liệu từ đây.
Bắt buộc đăng nhập (401 khi thiếu/sai token).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..models import Follow, Story, User
from ..schemas import StoryOut
from .stories import get_story_or_404, story_outs

router = APIRouter(tags=["follows"])


@router.post("/follows/{story_id}")
def follow_story(
    story_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Theo dõi một truyện (idempotent: theo dõi lần 2 vẫn trả 200)."""
    story = get_story_or_404(db, story_id, user)
    row = db.get(Follow, {"user_id": user.id, "story_id": story.id})
    if row is None:
        db.add(Follow(user_id=user.id, story_id=story.id))
        db.commit()
    return {"message": "Đã theo dõi truyện"}


@router.delete("/follows/{story_id}")
def unfollow_story(
    story_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Bỏ theo dõi (idempotent: chưa theo dõi vẫn trả 200)."""
    story = get_story_or_404(db, story_id, user)
    row = db.get(Follow, {"user_id": user.id, "story_id": story.id})
    if row is not None:
        db.delete(row)
        db.commit()
    return {"message": "Đã bỏ theo dõi truyện"}


@router.get("/me/follows", response_model=list[StoryOut])
def list_my_follows(
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> list[StoryOut]:
    """Danh sách truyện mà người đang đăng nhập đang theo dõi (mới nhất trước)."""
    story_ids = db.execute(
        select(Follow.story_id)
        .where(Follow.user_id == user.id)
        .order_by(Follow.created_at.desc())
    ).scalars().all()

    # Giữ nguyên thứ tự created_at.desc() và bỏ truyện đã bị xoá / CHƯA duyệt
    # (chỉ truyện approved mới hiện với tư cách công khai — cùng điều kiện với
    # get_story_or_404 qua moderation.can_view).
    stories: list[Story] = []
    for story_id in story_ids:
        story = db.get(Story, story_id)
        if story is not None and story.moderation_status == "approved":
            stories.append(story)
    return story_outs(db, stories)
