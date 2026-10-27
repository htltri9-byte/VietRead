"""API chương truyện: GET/POST /stories/{id}/chapters và GET/PUT/DELETE /chapters/{id}.

Người đọc luôn nhận bản **đã resolve** (bỏ marker nhiều nghĩa, lấy nghĩa đầu);
chủ truyện dùng `GET /chapters/{id}?raw=1` để nhận bản thô có marker khi sửa.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete as sa_delete
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import alternatives, security
from ..database import get_db
from ..moderation import mark_needs_recheck
from ..models import Chapter, ChapterRevision, Comment, User
from ..schemas import (
    ChapterCreate,
    ChapterOut,
    ChapterSummaryOut,
    ChapterUpdate,
    RetranslateOut,
    RetranslateRequest,
)
from ..services import glossary as glossary_service
from ..services.story_words import load_choices, load_learned_keys, load_skips
from ..services.translator import TranslationError, translate_text
from .stories import get_owned_story, get_story_or_404, require_owner, utc_now

router = APIRouter(tags=["chapters"])

logger = logging.getLogger("vietread.chapters")

CHAPTER_PAGE_SIZE = 50


def _chapter_out(chapter: Chapter, content: str | None = None) -> ChapterOut:
    """Chuyển chương sang JSON { id, storyId, index, title, content }.

    `content` khác None → trả đúng văn bản đó (bản thô hoặc bản đã resolve).
    """
    return ChapterOut(
        id=chapter.id,
        storyId=chapter.story_id,
        index=chapter.chapter_index,
        title=chapter.title,
        content=chapter.content if content is None else content,
    )


@router.get("/stories/{story_id}/chapters", response_model=list[ChapterSummaryOut])
def list_chapters(
    story_id: int,
    db: Session = Depends(get_db),
    viewer: User | None = Depends(security.get_current_user_optional),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=CHAPTER_PAGE_SIZE, ge=1, le=200, alias="pageSize"),
) -> list[ChapterSummaryOut]:
    """Danh sách chương của một truyện, xếp theo ChapterIndex, có phân trang.

    Chỉ SELECT 5 cột cần cho tóm tắt — không đọc `Content`/`OriginalContent`
    (chương dài hàng chục KiB, đọc cả row chỉ để trả id/title là lãng phí).
    """
    get_story_or_404(db, story_id, viewer)
    rows = (
        db.execute(
            select(
                Chapter.id,
                Chapter.story_id,
                Chapter.chapter_index,
                Chapter.title,
                Chapter.updated_at,
            )
            .where(Chapter.story_id == story_id)
            .order_by(Chapter.chapter_index)
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .all()
    )
    return [
        ChapterSummaryOut(
            id=row.id,
            storyId=row.story_id,
            index=row.chapter_index,
            title=row.title,
            updatedAt=row.updated_at,
        )
        for row in rows
    ]


@router.get("/chapters/{chapter_id}", response_model=ChapterOut)
def get_chapter(
    chapter_id: int,
    db: Session = Depends(get_db),
    viewer: User | None = Depends(security.get_current_user_optional),
    raw: bool = Query(
        default=False,
        description="Bản thô có marker nhiều nghĩa — chỉ chủ truyện được xem",
    ),
) -> ChapterOut:
    """Nội dung một chương (kèm content).

    Mặc định trả bản **đã resolve** — người đọc (đọc chương, tải offline, tìm
    kiếm, xem thử) không bao giờ thấy dấu `{}`. `?raw=1` trả bản thô để chủ
    truyện sửa chương: 401 khi chưa đăng nhập, 403 khi không phải chủ.
    """
    chapter = db.get(Chapter, chapter_id)
    if chapter is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy chương")
    story = get_story_or_404(db, chapter.story_id, viewer)  # 404 nếu nháp của người khác
    if raw:
        if viewer is None:
            raise HTTPException(status_code=401, detail="Chưa đăng nhập (thiếu token)")
        require_owner(story, viewer)
        # Bản thô trả SẠCH: dữ liệu cũ {为|vì|...} → {vì|...}, không chữ Hán —
        # màn Sửa chương không bao giờ thấy khóa; lưu chương ghi lại dạng sạch.
        return _chapter_out(chapter, alternatives.normalize(chapter.content))
    return _chapter_out(chapter, alternatives.resolve(chapter.content))


@router.post("/chapters/{chapter_id}/retranslate", response_model=RetranslateOut)
def retranslate_chapter(
    chapter_id: int,
    payload: RetranslateRequest | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> RetranslateOut:
    """Dịch lại chương từ `OriginalContent` bằng từ điển hiện tại (chỉ chủ truyện).

    Trả **nội dung để nạp vào màn Sửa chương, KHÔNG tự lưu** — chỉ lưu khi người
    dùng bấm Lưu. Dùng để lấy marker cho các chương đã dịch trước đây; quy tắc
    `ApplyToFuture` của truyện cũng được áp lên bản trả về.

    Body TUỲ CHỌN `{ markLevel: low|medium|high }` — mức gợi ý nhiều nghĩa
    (thiếu → `MARK_LEVEL` trong `.env`, mặc định `low`). Nghĩa đã chọn / khóa
    "không hỏi lại" của riêng truyện được áp khi dịch.
    """
    chapter = db.get(Chapter, chapter_id)
    if chapter is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy chương")
    story = get_owned_story(db, chapter.story_id, user)
    if not (chapter.original_content and chapter.original_content.strip()):
        raise HTTPException(
            status_code=400, detail="Chương này không có bản gốc để dịch lại"
        )
    try:
        content = translate_text(
            chapter.original_content,
            "vi",
            mark_alternatives=True,
            mark_level=payload.mark_level if payload else None,
            key_choices=load_choices(db, story.id),
            skip_keys=load_skips(db, story.id) | load_learned_keys(db, user.id),
        )
    except TranslationError as exc:
        logger.error("Dịch lại chương %s lỗi: %s", chapter_id, exc, exc_info=True)
        raise HTTPException(
            status_code=503,
            detail=f"Không dịch được nội dung sang tiếng Việt — {str(exc)[:500]}",
        ) from exc
    content, replaced = glossary_service.apply_rules(db, story.id, content)
    if replaced:
        logger.info(
            "Dịch lại chương %s: áp %d chỗ thay thế từ glossary", chapter_id, replaced
        )
    # KHÔNG commit — endpoint chỉ trả về, không ghi đè Content.
    return RetranslateOut(chapterId=chapter.id, content=content)


@router.post("/stories/{story_id}/chapters", response_model=ChapterOut)
def create_chapter(
    story_id: int,
    payload: ChapterCreate,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ChapterOut:
    """Thêm chương (chỉ tác giả). Không truyền index thì tự đánh số tiếp theo."""
    story = get_owned_story(db, story_id, user)
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

    # Chương mới: áp quy tắc "Tìm & thay thế" ApplyToFuture của truyện (nếu có),
    # rồi chuẩn hoá marker (bỏ chữ Hán nếu client gửi dữ liệu cũ) — không cần restart.
    content, _replaced = glossary_service.apply_rules(db, story_id, payload.content)
    content = alternatives.normalize(content)

    chapter = Chapter(
        story_id=story_id,
        chapter_index=index,
        title=payload.title,
        content=content,
    )
    db.add(chapter)
    story.updated_at = utc_now()  # để mục "Mới cập nhật" phản ánh đúng
    mark_needs_recheck(story)     # approved → Admin nên xem lại (các trạng thái khác giữ nguyên)
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
    story = get_owned_story(db, chapter.story_id, user)

    data = payload.model_dump(exclude_unset=True)
    if "title" in data:
        if not payload.title:
            raise HTTPException(status_code=400, detail="Tên chương không được để trống")
        chapter.title = payload.title
    if "content" in data:
        if not (payload.content and payload.content.strip()):
            raise HTTPException(status_code=400, detail="Nội dung chương không được để trống")
        # Lưu chương = ghi lại marker dạng sạch (bỏ khóa/chữ Hán dữ liệu cũ)
        chapter.content = alternatives.normalize(payload.content)
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
    mark_needs_recheck(story)
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
    story = get_owned_story(db, chapter.story_id, user)
    db.execute(sa_delete(Comment).where(Comment.chapter_id == chapter.id))
    # Revision (snapshot hoàn tác) không cascade theo chương — xoá trong code
    # để không tạo 2 đường cascade từ Stories (xem schema.sql).
    db.execute(sa_delete(ChapterRevision).where(ChapterRevision.chapter_id == chapter.id))
    db.delete(chapter)
    story.updated_at = utc_now()
    mark_needs_recheck(story)
    db.commit()
    return {"message": "Đã xoá chương"}
