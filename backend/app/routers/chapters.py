"""API chương truyện: GET/POST /stories/{id}/chapters và GET/PUT/DELETE /chapters/{id}."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete as sa_delete
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..models import Chapter, Comment, Story, User
from ..schemas import ChapterCreate, ChapterOut, ChapterSummaryOut, ChapterUpdate
from .stories import get_story_or_404, require_owner, utc_now

router = APIRouter(tags=["chapters"])

CHAPTER_PAGE_SIZE = 50


def _chapter_out(chapter: Chapter) -> ChapterOut:
    """Chuyển chương sang JSON { id, storyId, index, title, content }."""
    return ChapterOut(
        id=chapter.id,
        storyId=chapter.story_id,
        index=chapter.chapter_index,
        title=chapter.title,
        content=chapter.content,
    )


def _summary_out(chapter: Chapter) -> ChapterSummaryOut:
    """Chuyển chương sang JSON { id, storyId, index, title, updatedAt } (không nội dung)."""
    return ChapterSummaryOut(
        id=chapter.id,
        storyId=chapter.story_id,
        index=chapter.chapter_index,
        title=chapter.title,
        updatedAt=chapter.updated_at,
    )


def _owned_story(db: Session, story_id: int, user: User) -> Story:
    """Lấy truyện để chỉnh sửa: phải tồn tại và người gọi là tác giả."""
    story = db.get(Story, story_id)
    if story is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
    require_owner(story, user)
    return story


@router.get("/stories/{story_id}/chapters", response_model=list[ChapterSummaryOut])
def list_chapters(
    story_id: int,
    db: Session = Depends(get_db),
    viewer: User | None = Depends(security.get_current_user_optional),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=CHAPTER_PAGE_SIZE, ge=1, le=200, alias="pageSize"),
) -> list[ChapterSummaryOut]:
    """Danh sách chương của một truyện, xếp theo ChapterIndex, có phân trang."""
    get_story_or_404(db, story_id, viewer)
    rows = (
        db.execute(
            select(Chapter)
            .where(Chapter.story_id == story_id)
            .order_by(Chapter.chapter_index)
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )
    return [_summary_out(ch) for ch in rows]


@router.get("/chapters/{chapter_id}", response_model=ChapterOut)
def get_chapter(
    chapter_id: int,
    db: Session = Depends(get_db),
    viewer: User | None = Depends(security.get_current_user_optional),
) -> ChapterOut:
    """Nội dung một chương (kèm content)."""
    chapter = db.get(Chapter, chapter_id)
    if chapter is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy chương")
    get_story_or_404(db, chapter.story_id, viewer)  # 404 nếu truyện là nháp của người khác
    return _chapter_out(chapter)


@router.post("/stories/{story_id}/chapters", response_model=ChapterOut)
def create_chapter(
    story_id: int,
    payload: ChapterCreate,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ChapterOut:
    """Thêm chương (chỉ tác giả). Không truyền index thì tự đánh số tiếp theo."""
    story = _owned_story(db, story_id, user)
    if payload.index is None:
        max_index = db.execute(
            select(func.max(Chapter.chapter_index)).where(Chapter.story_id == story_id)
        ).scalar()
        index = 1 if max_index is None else int(max_index) + 1
    else:
        index = payload.index
        exists = db.execute(
            select(Chapter.id).where(
                Chapter.story_id == story_id, Chapter.chapter_index == index
            )
        ).first()
        if exists is not None:
            raise HTTPException(status_code=400, detail=f"Chương số {index} đã tồn tại")

    chapter = Chapter(
        story_id=story_id,
        chapter_index=index,
        title=payload.title,
        content=payload.content,
    )
    db.add(chapter)
    story.updated_at = utc_now()  # để mục "Mới cập nhật" phản ánh đúng
    db.commit()
    db.refresh(chapter)
    return _chapter_out(chapter)


@router.put("/chapters/{chapter_id}", response_model=ChapterOut)
def update_chapter(
    chapter_id: int,
    payload: ChapterUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ChapterOut:
    """Sửa chương (chỉ tác giả); trường nào không gửi thì giữ nguyên."""
    chapter = db.get(Chapter, chapter_id)
    if chapter is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy chương")
    story = _owned_story(db, chapter.story_id, user)

    data = payload.model_dump(exclude_unset=True)
    if "title" in data:
        if not payload.title:
            raise HTTPException(status_code=400, detail="Tên chương không được để trống")
        chapter.title = payload.title
    if "content" in data:
        if not (payload.content and payload.content.strip()):
            raise HTTPException(status_code=400, detail="Nội dung chương không được để trống")
        chapter.content = payload.content
    if "index" in data:
        if payload.index is None:
            raise HTTPException(status_code=400, detail="index phải là số nguyên >= 1")
        if payload.index != chapter.chapter_index:
            exists = db.execute(
                select(Chapter.id).where(
                    Chapter.story_id == chapter.story_id,
                    Chapter.chapter_index == payload.index,
                )
            ).first()
            if exists is not None:
                raise HTTPException(
                    status_code=400, detail=f"Chương số {payload.index} đã tồn tại"
                )
            chapter.chapter_index = payload.index

    chapter.updated_at = utc_now()
    story.updated_at = utc_now()
    db.commit()
    db.refresh(chapter)
    return _chapter_out(chapter)


@router.delete("/chapters/{chapter_id}")
def delete_chapter(
    chapter_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Xoá chương (chỉ tác giả). Xoá bình luận của chương trước vì FK không cascade."""
    chapter = db.get(Chapter, chapter_id)
    if chapter is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy chương")
    story = _owned_story(db, chapter.story_id, user)
    db.execute(sa_delete(Comment).where(Comment.chapter_id == chapter.id))
    db.delete(chapter)
    story.updated_at = utc_now()
    db.commit()
    return {"message": "Đã xoá chương"}
