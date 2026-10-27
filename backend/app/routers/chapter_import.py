"""Thêm chương mới vào truyện đã có — dán link Qidian hoặc dán văn bản.

Hai endpoint (chỉ chủ truyện; 404 nếu truyện không tồn tại, 403 nếu không phải chủ):

- ``POST /stories/{id}/chapters/import``      — cào 1 chương từ link Qidian
  (chỉ domain Qidian), dịch zh → vi, lưu ``Content`` = bản dịch,
  ``OriginalContent`` = bản gốc, ghi ``SourceChapterId/SourceChapterUrl``
  để chống trùng khi mời lại cùng link.
- ``POST /stories/{id}/chapters/import-text`` — dán thẳng văn bản
  (``sourceLang=vi`` lưu nguyên, ``zh`` dịch rồi lưu bản gốc).

Chỉ THÊM chương mới — không bao giờ ghi đè/chỉnh sửa chương đã có.
Lỗi cào (AdapterError) và lỗi dịch (TranslationError) được phân biệt rõ
(502 vs 503) — không bao giờ báo nhầm lỗi cào thành lỗi dịch; traceback được
log ra terminal uvicorn.
"""

from __future__ import annotations

import logging
import re
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..models import Chapter, User
from ..schemas import ChapterImportByText, ChapterImportByUrl, ChapterOut
from ..services import glossary as glossary_service
from ..services.story_words import load_choices, load_learned_keys, load_skips
from ..services.scraper import (
    CHAPTER_PREFIX_RE,
    AdapterError,
    ParsedChapter,
    get_adapter,
    is_qidian_url,
    qidian_chapter_id,
)
from ..services.translator import TranslationError, translate_text
from ..moderation import mark_needs_recheck
from .stories import get_owned_story, utc_now

router = APIRouter(tags=["chapters"])

logger = logging.getLogger("vietread.chapter_import")

# "第843章 火泉涉及世界终极真相" — đọc số chương từ tiêu đề gốc (chữ số Ả Rập)
_CHAPTER_NO_RE = re.compile(r"第\s*(\d+)\s*章")

# Bỏ tiền tố "第N章" khi dịch tên chương (xem scraper.CHAPTER_PREFIX_RE)

# Gợi dẫn định dạng link chương Qidian (đã kiểm chứng thực tế trên m.qidian.com)
_FORMAT_HINT = (
    "Định dạng đúng: https://www.qidian.com/chapter/{mã truyện}/{mã chương}/ "
    "(vd: https://m.qidian.com/chapter/1040765595/806596284/)"
)


def _is_http_url(url: str) -> bool:
    parsed = urlparse(url)
    return parsed.scheme in ("http", "https") and bool(parsed.netloc)


def _parse_qidian_chapter_url(url: str) -> tuple[str, str]:
    """Tách ``(bookId, chapterId)`` từ link chương Qidian. Sai → 400 tiếng Việt."""
    if not _is_http_url(url):
        raise HTTPException(
            status_code=400,
            detail=f"Link không hợp lệ — cần link http(s) đầy đủ. {_FORMAT_HINT}",
        )
    if not is_qidian_url(url):
        raise HTTPException(
            status_code=400, detail="Chỉ hỗ trợ thêm chương từ Qidian"
        )
    ids = qidian_chapter_id(url)
    if ids is None:
        raise HTTPException(
            status_code=400,
            detail=f"Link không đúng định dạng chương Qidian. {_FORMAT_HINT}",
        )
    return ids


def _scrape_chapter(url: str) -> ParsedChapter:
    """Gọi ``parse_chapter`` (adapter có sẵn, đã rewrite www → m.qidian.com).

    Lỗi cào (AdapterError) → 400 với chương VIP/trả phí, 502 khi Qidian chặn
    (kèm HTTP status) hoặc cào không ra nội dung — KHÔNG vượt rào, không dùng
    cookie/tài khoản.
    """
    adapter = get_adapter(url)
    if adapter is None:  # không thể xảy ra — đã check domain Qidian ở trên
        raise HTTPException(
            status_code=400, detail="Chỉ hỗ trợ thêm chương từ Qidian"
        )
    try:
        return adapter.parse_chapter(url)
    except AdapterError as exc:
        message = str(exc)
        logger.error("Cào chương Qidian lỗi (%s): %s", url, message, exc_info=True)
        if "VIP" in message or "trả phí" in message:
            raise HTTPException(status_code=400, detail=message)
        if "rỗng" in message:
            raise HTTPException(
                status_code=502,
                detail=f"Cào không ra nội dung chương từ Qidian — {message}",
            )
        raise HTTPException(
            status_code=502,
            detail=f"Qidian chặn hoặc không tải được chương — {message}",
        )


def _translate(
    text: str,
    mark_alternatives: bool = False,
    mark_level: str | None = None,
    key_choices: dict[str, str] | None = None,
    skip_keys: set[str] | None = None,
) -> str:
    """Dịch zh → vi theo TRANSLATE_MODE hiện hành. Lỗi dịch → 503 (không phải lỗi cào).

    `mark_alternatives=True` — cụm nhiều nghĩa (đã qua bộ lọc [app.marking])
    thành marker `{中文|nghĩa1|nghĩa2}` (chỉ dùng cho nội dung chương, không
    dùng cho tên chương). `mark_level` — mức gợi ý; `key_choices`/`skip_keys` —
    nghĩa đã chọn / khóa bỏ hỏi riêng của truyện.
    """
    try:
        return translate_text(
            text,
            "vi",
            mark_alternatives=mark_alternatives,
            mark_level=mark_level,
            key_choices=key_choices,
            skip_keys=skip_keys,
        )
    except TranslationError as exc:
        logger.error("Dịch nội dung chương lỗi: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=503,
            detail=f"Không dịch được nội dung sang tiếng Việt — {str(exc)[:500]}",
        )


def _existing_index(db: Session, story_id: int, index: int) -> bool:
    row = db.execute(
        select(Chapter.id).where(
            Chapter.story_id == story_id, Chapter.chapter_index == index
        )
    ).first()
    return row is not None


def _resolve_index(
    db: Session, story_id: int, chapter_no: int | None, hint_text: str | None
) -> int:
    """Số chương mới: ưu tiên ``chapterNo`` → đọc ``第N章`` trong hint → MAX+1.

    Trùng số với chương đã có → 409.
    """
    index = chapter_no
    if index is None and hint_text:
        m = _CHAPTER_NO_RE.search(hint_text)
        index = int(m.group(1)) if m else None
    if index is None:
        max_index = db.execute(
            select(func.max(Chapter.chapter_index)).where(Chapter.story_id == story_id)
        ).scalar()
        index = 1 if max_index is None else int(max_index) + 1
    if _existing_index(db, story_id, index):
        raise HTTPException(
            status_code=409, detail=f"Chương số {index} đã tồn tại trong truyện"
        )
    return index


def _chapter_out(chapter: Chapter) -> ChapterOut:
    """JSON chương vừa tạo — cùng format ``GET /chapters/{id}`` (Flutter dùng lại model)."""
    return ChapterOut(
        id=chapter.id,
        storyId=chapter.story_id,
        index=chapter.chapter_index,
        title=chapter.title,
        content=chapter.content,
    )


def _commit_or_conflict(db: Session) -> None:
    """Commit; trùng do 2 request chạy song song (unique index) → 409."""
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409, detail="Chương này đã được nhập"
        )


@router.post("/stories/{story_id}/chapters/import", response_model=ChapterOut)
def import_chapter_from_url(
    story_id: int,
    payload: ChapterImportByUrl,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ChapterOut:
    """Thêm 1 chương vào truyện đã có bằng link chương Qidian (chỉ chủ truyện).

    Chạy đồng bộ trong request (cào 1 chương → dịch → lưu), khoảng ≤ 60 giây.
    """
    story = get_owned_story(db, story_id, user)
    book_id, chapter_id = _parse_qidian_chapter_url(payload.chapter_url)

    # Chống nhầm truyện: link thuộc bookId khác → 400.
    if story.source_book_id and story.source_book_id != book_id:
        raise HTTPException(
            status_code=400, detail="Link này thuộc truyện khác"
        )

    # Chống trùng chương theo SourceChapterId (unique index lọc ở DB).
    dup = db.execute(
        select(Chapter).where(
            Chapter.story_id == story_id,
            Chapter.source_chapter_id == chapter_id,
        )
    ).scalar_one_or_none()
    if dup is not None:
        raise HTTPException(
            status_code=409,
            detail=(
                f"Chương này đã được nhập (chương số {dup.chapter_index} — "
                f"{dup.title})"
            ),
        )

    # Số chương do client gửi mà đã tồn tại → chặn trước khi tốn công cào/dịch.
    if payload.chapter_no is not None and _existing_index(
        db, story_id, payload.chapter_no
    ):
        raise HTTPException(
            status_code=409,
            detail=f"Chương số {payload.chapter_no} đã tồn tại trong truyện",
        )

    # parse_chapter tự rewrite www → m.qidian.com; chuẩn hoá link về bản mobile.
    canonical_url = f"https://m.qidian.com/chapter/{book_id}/{chapter_id}/"
    parsed = _scrape_chapter(canonical_url)
    if not (parsed.content and parsed.content.strip()):
        raise HTTPException(
            status_code=502, detail="Cào không ra nội dung chương từ Qidian"
        )

    # Số chương: chapterNo → 第N章 trong tiêu đề gốc → MAX+1; trùng → 409.
    index = _resolve_index(db, story_id, payload.chapter_no, parsed.title)

    # Tên chương: client gửi → dịch tiêu đề gốc (bỏ "第N章") → fallback.
    if payload.title:
        title = payload.title
    else:
        title_zh = CHAPTER_PREFIX_RE.sub("", parsed.title).strip() or parsed.title
        title = (_translate(title_zh) or "").strip()[:255] or f"Chương {index}"

    content_vi = _translate(
        parsed.content,
        mark_alternatives=True,
        mark_level=payload.mark_level,
        key_choices=load_choices(db, story_id),
        skip_keys=load_skips(db, story_id) | load_learned_keys(db, user.id),
    )  # TranslationError → 503
    # Chương mới: áp quy tắc "Tìm & thay thế" ApplyToFuture của truyện (nếu có).
    content_vi, replaced = glossary_service.apply_rules(db, story_id, content_vi)
    if replaced:
        logger.info("Thêm chương Qidian story=%s: áp %d chỗ thay thế", story_id, replaced)

    chapter = Chapter(
        story_id=story_id,
        chapter_index=index,
        title=title,
        content=content_vi,
        original_content=parsed.content,
        source_chapter_id=chapter_id,
        source_chapter_url=canonical_url,
    )
    db.add(chapter)
    if not story.source_book_id:
        # Truyện chưa có SourceBookId (nhập trước migration) → ghi lại từ link.
        story.source_book_id = book_id
        story.source_url = f"https://m.qidian.com/book/{book_id}/"
    story.updated_at = utc_now()  # mục "Mới cập nhật" + số chương (COUNT) tự đúng
    mark_needs_recheck(story)     # approved → Admin nên xem lại chương mới
    _commit_or_conflict(db)
    db.refresh(chapter)
    logger.info(
        "Thêm chương Qidian vào story=%s: chương %s (%s)", story_id, index, chapter_id
    )
    return _chapter_out(chapter)


@router.post("/stories/{story_id}/chapters/import-text", response_model=ChapterOut)
def import_chapter_from_text(
    story_id: int,
    payload: ChapterImportByText,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ChapterOut:
    """Thêm 1 chương bằng văn bản dán (chỉ chủ truyện).

    ``sourceLang=vi``: lưu nguyên làm Content (không dịch).
    ``sourceLang=zh``: dịch sang vi lưu Content, bản gốc lưu OriginalContent.
    """
    story = get_owned_story(db, story_id, user)
    text = payload.text

    # Gợi đánh số từ tên chương client gửi, không thì dòng đầu tiên của văn bản.
    first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    hint = payload.title or first_line
    index = _resolve_index(db, story_id, payload.chapter_no, hint)

    is_zh = payload.source_lang == "zh"
    content_vi = (
        _translate(
            text,
            mark_alternatives=True,
            mark_level=payload.mark_level,
            key_choices=load_choices(db, story_id),
            skip_keys=load_skips(db, story_id) | load_learned_keys(db, user.id),
        )
        if is_zh
        else text
    )
    # Chương mới (kể cả dán nguyên văn): áp quy tắc ApplyToFuture của truyện.
    content_vi, replaced = glossary_service.apply_rules(db, story_id, content_vi)
    if replaced:
        logger.info("Thêm chương dán văn bản story=%s: áp %d chỗ thay thế", story_id, replaced)

    # Tên chương: client gửi → dòng đầu (bỏ "第N章", dịch nếu zh) → "Chương N".
    if payload.title:
        title = payload.title
    else:
        candidate = CHAPTER_PREFIX_RE.sub("", first_line).strip() if is_zh else first_line
        if candidate and len(candidate) <= 120:
            title = ((_translate(candidate) if is_zh else candidate).strip() or "")[
                :255
            ]
        else:
            title = ""
        title = title or f"Chương {index}"

    chapter = Chapter(
        story_id=story_id,
        chapter_index=index,
        title=title,
        content=content_vi,
        original_content=text if is_zh else None,
    )
    db.add(chapter)
    story.updated_at = utc_now()
    mark_needs_recheck(story)     # approved → Admin nên xem lại chương mới
    _commit_or_conflict(db)
    db.refresh(chapter)
    logger.info("Thêm chương dán văn bản vào story=%s: chương %s", story_id, index)
    return _chapter_out(chapter)
