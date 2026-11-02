"""Worker chạy nền cho POST /imports (C4 — Bước 10).

FastAPI `BackgroundTasks` gọi `run_import_job(job_id)` sau khi đã trả `{ jobId }`
(chạy trong threadpool nên mỗi job có session SQLAlchemy riêng):

    Pending → Running → cào thông tin truyện (adapter) → tạo **truyện nháp**
    thuộc người dùng đã import → với mỗi chương: cào → dịch → lưu
    Chapters(Content = bản dịch, OriginalContent = bản gốc) → cập nhật Progress
    → Done (progress 100).

Bất kỳ lỗi nào (nguồn chặn, link sai, dịch lỗi…) đều chuyển job sang
**Failed** kèm `Error` tiếng Việt rõ ràng. Nếu lỗi xảy ra giữa chừng thì
truyện nháp + các chương đã nhập vẫn được giữ lại để người dùng xem/sửa.
"""

from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timezone

from sqlalchemy import select

from ..database import SessionLocal
from ..models import Chapter, Genre, ImportJob, Story, StoryGenre
from . import glossary as glossary_service
from .story_words import load_choices, load_learned_keys, load_skips
from .scraper import (
    CHAPTER_PREFIX_RE,
    AdapterError,
    ParsedStory,
    get_adapter,
    host_of,
    qidian_book_id,
    qidian_chapter_id,
)
from .translator import translate_text
from ..vietphrase import convert_name

logger = logging.getLogger("vietread.imports")


def original_author_fields(parsed_author: str | None) -> tuple[str | None, str | None]:
    """(OriginalAuthor, OriginalAuthorRaw) từ tên tác giả đọc được ở nguồn.

    - Raw = tên gốc (chữ Trung) — lưu nguyên không sửa.
    - OriginalAuthor = bản Hán-Việt viết hoa từng từ ([convert_name], offline
      từ điển). Tên không phải chữ Trung (vd Latin) → giữ nguyên làm hiển thị.
    - Không lấy được / không chuyển được → cả hai `None` (job vẫn Done).
    """
    raw = (parsed_author or "").strip()
    if not raw:
        return None, None
    vi = convert_name(raw)
    if vi is None and not any("\u3400" <= ch <= "\u9fff" for ch in raw):
        vi = raw  # không có chữ Hán → tên đã đọc được, dùng thẳng
    return vi, raw

def _utc_now() -> datetime:
    """Thời gian UTC naive — khớp DATETIME2 (SYSUTCDATETIME) như các router khác."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, "") or default)
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, "") or default)
    except ValueError:
        return default


def _error_text(exc: Exception) -> str:
    """Thông báo lỗi lưu vào cột Error (giới hạn trong 2000 ký tự)."""
    message = str(exc).strip() or type(exc).__name__
    return message[:2000]


def _ensure_genres(db, story_id: int, names: list[str]) -> None:
    """Gắn thể loại cho truyện; thể loại chưa có thì tạo mới (giống POST /stories)."""
    for name in names[:10]:
        genre = db.execute(select(Genre).where(Genre.name == name)).scalar_one_or_none()
        if genre is None:
            genre = Genre(name=name)
            db.add(genre)
            db.flush()
        db.add(StoryGenre(story_id=story_id, genre_id=genre.id))


def run_import_job(job_id: int) -> None:
    """Thực hiện một import job — gọi bởi BackgroundTasks (blocking, có retry/delay)."""
    db = SessionLocal()
    job: ImportJob | None = None
    try:
        job = db.get(ImportJob, job_id)
        if job is None:  # bị xoá giữa chừng thì bỏ qua
            return

        job.status = "Running"
        job.progress = 0
        job.updated_at = _utc_now()
        db.commit()

        # --- 1) Chọn nguồn + lấy thông tin truyện ---------------------------
        adapter = get_adapter(job.source_url)
        if adapter is None:
            raise AdapterError(
                f"Nguồn '{host_of(job.source_url)}' chưa được hỗ trợ — "
                "hiện chỉ hỗ trợ Qidian và nguồn demo demo.vietread.local"
            )

        parsed: ParsedStory = adapter.parse_story(job.source_url)
        limit = _env_int("IMPORT_MAX_CHAPTERS", 0)
        chapters = parsed.chapters[:limit] if limit > 0 else parsed.chapters
        if not chapters:
            raise AdapterError("Không tìm thấy chương nào từ nguồn")

        # --- 2) Tạo truyện nháp (IsDraft=1) thuộc người dùng đã import ------
        title = translate_text(parsed.title, job.target_lang).strip()[:255]
        if not title:
            title = parsed.title.strip()[:255] or "Truyện nhập từ link"
        description = (
            translate_text(parsed.description, job.target_lang).strip()
            if parsed.description
            else None
        )
        author_vi, author_raw = original_author_fields(parsed.author)
        story = Story(
            author_id=job.user_id,
            title=title,
            description=description or None,
            cover_url=parsed.cover_url,
            status="ongoing",
            is_draft=True,
            original_author=author_vi,
            original_author_raw=author_raw,
            source_url=job.source_url,
            # bookId từ URL truyện (Qidian) — NULL với nguồn khác / URL lạ;
            # dùng để chống nhầm truyện khi thêm chương bằng link về sau.
            source_book_id=qidian_book_id(job.source_url),
        )
        db.add(story)
        db.flush()
        _ensure_genres(db, story.id, parsed.genres)

        job.story_id = story.id
        job.updated_at = _utc_now()
        db.commit()

        # --- 3) Từng chương: cào → dịch → lưu → cập nhật Progress ------------
        total = len(chapters)
        delay = _env_float("IMPORT_CHAPTER_DELAY", 0.5)
        # Nạp 1 lần cho CẢ BỘ: nghĩa đã chọn / khóa bỏ hỏi / quy tắc đã học /
        # quy tắc ApplyToFuture — các khoá này không đổi trong 1 lần import
        # (tránh 4 query lặp theo mỗi chương — trước đây N+1 với bộ vài trăm chương).
        key_choices = load_choices(db, story.id)
        skip_keys = load_skips(db, story.id) | load_learned_keys(db, job.user_id)
        future_rules = glossary_service.load_future_rules(db, story.id)
        for i, (chapter_title, chapter_url) in enumerate(chapters, start=1):
            parsed_chapter = adapter.parse_chapter(chapter_url)

            # Dịch từ điển (TRANSLATE_MODE=dict) gọi callback theo từng đoạn
            # xuống dòng → cập nhật % tiến độ job mượt hơn từng chương.
            base = (i - 1) / total

            def _on_paragraph(done: int, parts: int, _base: float = base) -> None:
                if parts <= 0:
                    return
                job.progress = int((_base + done / parts / total) * 100)
                job.updated_at = _utc_now()
                db.commit()

            content_vi = translate_text(
                parsed_chapter.content,
                job.target_lang,
                on_progress=_on_paragraph,
                # Bản thô lưu marker nhiều nghĩa để chủ truyện chọn nghĩa sau
                mark_alternatives=True,
                # Mức gợi ý lấy từ MARK_LEVEL (.env); nghĩa đã chọn / khóa bỏ
                # hỏi của riêng truyện này được áp khi dịch chương mới.
                key_choices=key_choices,
                skip_keys=skip_keys,
            )
            # Chương mới: áp quy tắc "Tìm & thay thế" ApplyToFuture của truyện này
            content_vi, replaced = glossary_service.apply_rules(
                db, story.id, content_vi, rules=future_rules
            )
            if replaced:
                logger.info("Import job %s: chương %s — áp %d chỗ thay thế",
                            job_id, i, replaced)
            # Bỏ "第N章" ở đầu tiêu đề (còn giữ nguyên nếu bỏ hết sẽ thành rỗng)
            title_zh = CHAPTER_PREFIX_RE.sub("", parsed_chapter.title).strip() or parsed_chapter.title
            title_vi = translate_text(title_zh, job.target_lang).strip()
            # Mã chương + link nguồn (Qidian) để chống trùng khi thêm chương mới;
            # nguồn khác / URL không khớp định dạng → để NULL (bỏ qua).
            src_ids = qidian_chapter_id(chapter_url)
            db.add(
                Chapter(
                    story_id=story.id,
                    chapter_index=i,
                    title=title_vi[:255] or f"Chương {i}",
                    content=content_vi,
                    original_content=parsed_chapter.content,
                    source_chapter_id=src_ids[1] if src_ids else None,
                    source_chapter_url=chapter_url if src_ids else None,
                )
            )
            job.progress = int(i / total * 100)
            job.updated_at = _utc_now()
            db.commit()  # client poll thấy % chương đã dịch

            if delay > 0 and i < total:
                time.sleep(delay)  # delay giữa các request tới nguồn (C4)

        job.status = "Done"
        job.progress = 100
        job.updated_at = _utc_now()
        db.commit()
        logger.info("Import job %s Done — story=%s, %s chương", job_id, story.id, total)

    except Exception as exc:  # nguồn chặn / link sai / dịch lỗi → Failed + Error
        try:
            db.rollback()
            if job is not None:
                job.status = "Failed"
                job.error = _error_text(exc)
                job.updated_at = _utc_now()
                db.commit()
            logger.warning("Import job %s Failed: %s", job_id, job.error if job else exc)
        except Exception:
            logger.exception("Không ghi được trạng thái Failed cho job %s", job_id)
    finally:
        db.close()
