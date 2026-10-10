"""API bình luận: GET/POST /stories/{id}/comments, DELETE /comments/{id} (Phần B).

Tab "Bình luận" ở màn chi tiết truyện (A3.6, Bước 8) đọc dữ liệu từ đây.
- Xem bình luận: cho phép khách (chưa đăng nhập).
- Gửi / xoá bình luận: bắt buộc đăng nhập (401 khi thiếu/sai token);
  chỉ người viết mới xoá được bình luận của mình (403).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..models import Chapter, Comment, User
from ..schemas import CommentCreate, CommentOut
from .stories import get_story_or_404

router = APIRouter(tags=["comments"])


def comment_outs(db: Session, comments: list[Comment]) -> list[CommentOut]:
    """Ghép bình luận với thông tin người dùng (không N+1)."""
    if not comments:
        return []
    users = {
        u.id: u
        for u in db.execute(
            select(User).where(User.id.in_({c.user_id for c in comments}))
        ).scalars()
    }
    return [
        CommentOut(
            id=c.id,
            storyId=c.story_id,
            chapterId=c.chapter_id,
            userId=c.user_id,
            userName=users[c.user_id].name if c.user_id in users else "",
            avatarUrl=users[c.user_id].avatar_url if c.user_id in users else None,
            content=c.content,
            createdAt=c.created_at,
        )
        for c in comments
    ]


@router.get("/stories/{story_id}/comments", response_model=list[CommentOut])
def list_comments(
    story_id: int,
    db: Session = Depends(get_db),
    viewer: User | None = Depends(security.get_current_user_optional),
) -> list[CommentOut]:
    """Danh sách bình luận của một truyện (mới nhất trước), kể cả khách."""
    story = get_story_or_404(db, story_id, viewer)
    rows = db.execute(
        select(Comment)
        .where(Comment.story_id == story.id)
        .order_by(Comment.created_at.desc(), Comment.id.desc())
    ).scalars().all()
    return comment_outs(db, list(rows))


@router.post("/stories/{story_id}/comments", response_model=CommentOut)
def create_comment(
    story_id: int,
    payload: CommentCreate,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> CommentOut:
    """Gửi bình luận theo truyện (hoặc theo chương nếu gửi chapterId)."""
    story = get_story_or_404(db, story_id, user)

    chapter_id: int | None = None
    if payload.chapter_id is not None:
        chapter = db.get(Chapter, payload.chapter_id)
        if chapter is None or chapter.story_id != story.id:
            raise HTTPException(status_code=400, detail="Chương không thuộc truyện này")
        chapter_id = chapter.id

    comment = Comment(
        story_id=story.id,
        chapter_id=chapter_id,
        user_id=user.id,
        content=payload.content,
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    return comment_outs(db, [comment])[0]


@router.delete("/comments/{comment_id}")
def delete_comment(
    comment_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Xoá bình luận — chỉ người viết bình luận đó (403 nếu của người khác)."""
    comment = db.get(Comment, comment_id)
    if comment is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy bình luận")
    if comment.user_id != user.id:
        raise HTTPException(status_code=403, detail="Bạn chỉ xoá được bình luận của mình")
    db.delete(comment)
    db.commit()
    return {"message": "Đã xoá bình luận"}
