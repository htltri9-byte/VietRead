"""API Admin kiểm duyệt truyện — mọi endpoint yêu cầu role = admin.

- GET  /admin/stories?status=&q=&page=&pageSize=  — danh sách theo trạng thái
- GET  /admin/stories/{id}                          — thông tin + danh sách chương
- GET  /admin/chapters/{chapterId}                  — nội dung đã resolve marker
- POST /admin/stories/{id}/approve                  — duyệt (idempotent, an toàn
                                                     khi 2 admin thao tác song song)
- POST /admin/stories/{id}/reject                   — từ chối/gỡ vì vi phạm (bắt buộc reason)
- GET  /admin/stats                                 — số truyện theo trạng thái

An toàn đua trạng thái: mọi chuyển trạng thái đều là UPDATE có điều kiện
(WHERE trạng thái hiện tại = trạng thái dự kiến) trong MỘT transaction —
request thứ hai thấy rowcount = 0 → 409, không bao giờ ghi đè lẫn nhau.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from .. import alternatives
from ..database import get_db
from ..moderation import log_moderation, require_admin, utc_now
from ..models import Chapter, Story, StoryGenre, Genre, User
from ..schemas import (
    AdminChapterOut,
    AdminStatsOut,
    AdminStoryDetailOut,
    AdminStoryOut,
    ChapterSummaryOut,
    ModerationActionOut,
    ModerationRejectIn,
)

router = APIRouter(prefix="/admin", tags=["admin"])

# Sắp xếp cho từng bộ lọc: chờ duyệt cũ nhất trước; còn lại mới duyệt/updated trước
_SORT_BY_STATUS = {
    "pending": (Story.submitted_at.asc(), Story.id.asc()),
    "approved": (Story.reviewed_at.desc(), Story.updated_at.desc()),
    "rejected": (Story.reviewed_at.desc(), Story.updated_at.desc()),
    "draft": (Story.updated_at.desc(), Story.id.desc()),
    "all": (Story.updated_at.desc(), Story.id.desc()),
    "recheck": (Story.updated_at.desc(), Story.id.desc()),
}
ADMIN_PAGE_SIZE = 20


def _admin_story_out(db: Session, story: Story, uploader: str | None = None) -> AdminStoryOut:
    if uploader is None:
        uploader = db.execute(
            select(User.name).where(User.id == story.author_id)
        ).scalar_one_or_none() or ""
    count = db.execute(
        select(func.count()).where(Chapter.story_id == story.id)
    ).scalar()
    return AdminStoryOut(
        id=story.id,
        title=story.title,
        coverUrl=story.cover_url,
        author=uploader,
        chapterCount=int(count or 0),
        moderationStatus=story.moderation_status,
        rejectReason=story.reject_reason,
        needsRecheck=story.needs_recheck,
        submittedAt=story.submitted_at,
        reviewedAt=story.reviewed_at,
        scanStatus=story.scan_status,
    )


def _get_story_for_admin(db: Session, story_id: int) -> Story:
    story = db.get(Story, story_id)
    if story is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
    return story


@router.get("/stories", response_model=list[AdminStoryOut])
def list_admin_stories(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
    status: str = Query(
        default="pending",
        description="pending | approved | rejected | draft | recheck | all",
    ),
    q: str | None = Query(default=None, description="Tìm theo tên truyện hoặc tác giả"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=ADMIN_PAGE_SIZE, ge=1, le=100, alias="pageSize"),
) -> list[AdminStoryOut]:
    """Danh sách truyện cho màn Kiểm duyệt. Mặc định `status=pending`,
    sắp xếp CŨ NHẤT TRƯỚC (SubmittedAt tăng dần)."""
    key = (status or "pending").strip().lower()
    if key not in _SORT_BY_STATUS:
        raise HTTPException(
            status_code=400,
            detail="status phải là pending | approved | rejected | draft | recheck | all",
        )

    stmt = select(Story)
    if key == "recheck":
        stmt = stmt.where(Story.moderation_status == "approved", Story.needs_recheck == True)  # noqa: E712
    elif key != "all":
        stmt = stmt.where(Story.moderation_status == key)

    if q and q.strip():
        pattern = f"%{q.strip()}%"
        stmt = stmt.outerjoin(User, User.id == Story.author_id).where(
            func.lower(Story.title).like(pattern.lower())
            | func.lower(User.name).like(pattern.lower())
        )

    rows = (
        db.execute(
            stmt.order_by(*_SORT_BY_STATUS[key])
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .scalars()
        .all()
    )
    uploaders = dict(
        db.execute(
            select(User.id, User.name).where(User.id.in_({s.author_id for s in rows}))
        ).all()
    ) if rows else {}
    return [_admin_story_out(db, s, uploaders.get(s.author_id, "")) for s in rows]


@router.get("/stories/{story_id}", response_model=AdminStoryDetailOut)
def get_admin_story(
    story_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
) -> AdminStoryDetailOut:
    """Chi tiết truyện để xem trước TRƯỚC khi công khai (kể cả nháp/pending)."""
    story = _get_story_for_admin(db, story_id)
    genres = [
        name
        for (name,) in db.execute(
            select(Genre.name)
            .join(StoryGenre, StoryGenre.genre_id == Genre.id)
            .where(StoryGenre.story_id == story.id)
            .order_by(Genre.name)
        ).all()
    ]
    uploader = db.execute(
        select(User.name).where(User.id == story.author_id)
    ).scalar_one_or_none() or ""
    chapters = (
        db.execute(
            select(Chapter)
            .where(Chapter.story_id == story.id)
            .order_by(Chapter.chapter_index)
        )
        .scalars()
        .all()
    )
    return AdminStoryDetailOut(
        story=_admin_story_out(db, story, uploader),
        description=story.description,
        genres=genres,
        originalAuthor=story.original_author,
        uploaderName=uploader,
        chapters=[
            ChapterSummaryOut(
                id=c.id,
                storyId=c.story_id,
                index=c.chapter_index,
                title=c.title,
                updatedAt=c.updated_at,
            )
            for c in chapters
        ],
    )


@router.get("/chapters/{chapter_id}", response_model=AdminChapterOut)
def get_admin_chapter(
    chapter_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
) -> AdminChapterOut:
    """Nội dung chương đã resolve marker (không dấu {}) + OriginalContent nếu có."""
    chapter = db.get(Chapter, chapter_id)
    if chapter is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy chương")
    return AdminChapterOut(
        id=chapter.id,
        storyId=chapter.story_id,
        index=chapter.chapter_index,
        title=chapter.title,
        content=alternatives.resolve(chapter.content),
        originalContent=chapter.original_content,
    )


@router.post("/stories/{story_id}/approve", response_model=ModerationActionOut)
def approve_story(
    story_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
) -> ModerationActionOut:
    """Duyệt truyện: `pending` (hoặc `approved` có NeedsRecheck) → `approved`.

    UPDATE có điều kiện trong một transaction — 2 admin duyệt song song thì
    chỉ request đầu thành công, request sau thấy rowcount = 0 → 409.
    """
    _get_story_for_admin(db, story_id)
    now = utc_now()
    result = db.execute(
        update(Story)
        .where(
            Story.id == story_id,
            (Story.moderation_status == "pending")
            |            (
                (Story.moderation_status == "approved")
                & (Story.needs_recheck == True)  # noqa: E712
            ),
        )
        .values(
            moderation_status="approved",
            is_draft=False,               # đồng bộ: approved ⇔ IsDraft = 0
            reject_reason=None,
            reviewed_at=now,
            reviewed_by=admin.id,
            needs_recheck=False,
            updated_at=now,
        )
    )
    if result.rowcount == 0:
        db.rollback()
        current = db.execute(
            select(Story.moderation_status).where(Story.id == story_id)
        ).scalar_one_or_none()
        if current is None:
            raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
        raise HTTPException(
            status_code=409,
            detail=f"Truyện không ở trạng thái chờ duyệt (hiện tại: '{current}') — "
                   "admin khác có thể đã xử lý trước",
        )
    log_moderation(db, _get_story_for_admin(db, story_id), admin.id, "approve")
    db.commit()
    db.expire_all()   # expire_on_commit=False → ép đọc lại giá trị MỚI từ DB
    story = _get_story_for_admin(db, story_id)
    return ModerationActionOut(message="Đã duyệt truyện", moderationStatus=story.moderation_status)


@router.post("/stories/{story_id}/reject", response_model=ModerationActionOut)
def reject_story(
    story_id: int,
    payload: ModerationRejectIn,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
) -> ModerationActionOut:
    """Từ chối/gỡ truyện: `pending` hoặc `approved` → `rejected` (bắt buộc lý do).

    Dùng cho cả từ chối lúc chờ duyệt lẫn GỠ truyện đã duyệt vì vi phạm.
    UPDATE có điều kiện → an toàn khi 2 admin thao tác song song (409).
    """
    _get_story_for_admin(db, story_id)
    reason = payload.reason
    now = utc_now()
    result = db.execute(
        update(Story)
        .where(
            Story.id == story_id,
            Story.moderation_status.in_(("pending", "approved")),
        )
        .values(
            moderation_status="rejected",
            is_draft=True,                # đồng bộ: không phải approved ⇒ IsDraft = 1
            reject_reason=reason,
            reviewed_at=now,
            reviewed_by=admin.id,
            needs_recheck=False,
            updated_at=now,
        )
    )
    if result.rowcount == 0:
        db.rollback()
        current = db.execute(
            select(Story.moderation_status).where(Story.id == story_id)
        ).scalar_one_or_none()
        if current is None:
            raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
        raise HTTPException(
            status_code=409,
            detail=f"Truyện không ở trạng thái chờ duyệt/đã duyệt (hiện tại: '{current}') — "
                   "admin khác có thể đã xử lý trước",
        )
    log_moderation(
        db, _get_story_for_admin(db, story_id), admin.id, "reject", reason
    )
    db.commit()
    db.expire_all()   # expire_on_commit=False → ép đọc lại giá trị MỚI từ DB
    story = _get_story_for_admin(db, story_id)
    return ModerationActionOut(
        message="Đã từ chối truyện", moderationStatus=story.moderation_status
    )


@router.get("/stats", response_model=AdminStatsOut)
def admin_stats(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
) -> AdminStatsOut:
    """Số truyện theo từng trạng thái — badge \"Chờ duyệt (N)\" ở màn Tài khoản."""
    rows = db.execute(
        select(Story.moderation_status, func.count()).group_by(Story.moderation_status)
    ).all()
    counts = {status: int(n) for status, n in rows}
    recheck = db.execute(
        select(func.count())
        .select_from(Story)
        .where(Story.moderation_status == "approved", Story.needs_recheck == True)  # noqa: E712
    ).scalar()
    return AdminStatsOut(
        draft=counts.get("draft", 0),
        pending=counts.get("pending", 0),
        approved=counts.get("approved", 0),
        rejected=counts.get("rejected", 0),
        needsRecheck=int(recheck or 0),
    )
