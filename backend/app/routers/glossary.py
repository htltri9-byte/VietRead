"""Tìm & thay thế theo truyện — chỉ chủ truyện (Phần 2 của yêu cầu).

- ``POST /stories/{id}/replace``        — ``dryRun=true`` đếm chỗ/chương (không ghi),
  ``dryRun=false`` thay thật trong một transaction, snapshot vào ``ChapterRevisions``
  và trả ``batchId`` để hoàn tác; ``applyToFuture=true`` lưu quy tắc ``StoryGlossary``.
- ``POST /stories/{id}/replace/undo``   — hoàn tác batch gần nhất (bỏ qua chương
  đã bị sửa tiếp sau batch và báo số chương không hoàn tác được).
- ``GET  /stories/{id}/glossary``       — xem quy tắc đã lưu của truyện.
- ``DELETE /stories/{id}/glossary/{id}`` — xoá một quy tắc.

Thao tác trên **bản thô** của ``Content`` (kể cả bên trong marker ``{a|b}``),
không đụng ``OriginalContent``, không đụng ``names.txt``/từ điển dùng chung,
không ảnh hưởng truyện khác (mọi truy vấn khoá theo ``StoryId``).
"""

from __future__ import annotations

import unicodedata
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete as sa_delete
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..models import Chapter, ChapterRevision, Story, StoryGlossary, User
from ..schemas import (
    GlossaryRuleOut,
    ReplaceChapterHit,
    ReplaceOut,
    ReplaceRequest,
    UndoOut,
)
from ..services import glossary as glossary_service
from .stories import get_owned_story, utc_now

router = APIRouter(tags=["glossary"])


def _validated(payload: ReplaceRequest) -> tuple[str, str]:
    """Validate cặp tìm/thay (ValueError → 400 tiếng Việt) + chuẩn hoá Unicode."""
    try:
        glossary_service.validate_pair(payload.find, payload.replace)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    find = unicodedata.normalize("NFC", payload.find)
    replace = unicodedata.normalize("NFC", payload.replace)
    if find == replace:  # sau chuẩn hoá có thể trùng nhau
        raise HTTPException(
            status_code=400, detail="Chuỗi cần tìm và chuỗi thay thế không được giống nhau"
        )
    return find, replace


def _count_in_story(rows: list[Chapter], rx, include_titles: bool) -> tuple[list[ReplaceChapterHit], int]:
    """Đếm số chỗ khớp từng chương (kèm tên chương nếu yêu cầu)."""
    hits: list[ReplaceChapterHit] = []
    total = 0
    for chapter in rows:
        matches = glossary_service.count_matches(chapter.content, rx)
        if include_titles:
            matches += glossary_service.count_matches(chapter.title, rx)
        if matches:
            hits.append(
                ReplaceChapterHit(
                    chapterId=chapter.id,
                    chapterNo=chapter.chapter_index,
                    matches=matches,
                )
            )
            total += matches
    return hits, total


@router.post(
    "/stories/{story_id}/replace",
    response_model=ReplaceOut,
    response_model_exclude_none=True,
)
def replace_in_story(
    story_id: int,
    payload: ReplaceRequest,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ReplaceOut:
    """Tìm & thay thế trong MỘT truyện (chỉ chủ truyện).

    ``dryRun=true`` → trả `{ totalMatches, chapters }`, không ghi gì.
    ``dryRun=false`` → snapshot chương cũ vào `ChapterRevisions` (1 batch gần nhất),
    thay trong `Content` mọi chương (và `Title` nếu `includeTitles`) rồi commit một
    lần; trả số chỗ, số chương đã đổi và `batchId`.
    """
    story = get_owned_story(db, story_id, user)
    find, replace = _validated(payload)
    rx = glossary_service.build_regex(find, payload.match_case, payload.whole_word)

    rows = list(
        db.execute(
            select(Chapter)
            .where(Chapter.story_id == story_id)
            .order_by(Chapter.chapter_index)
        )
        .scalars()
        .all()
    )
    hits, total = _count_in_story(rows, rx, payload.include_titles)

    if payload.dry_run:
        return ReplaceOut(dryRun=True, totalMatches=total, chapters=hits)

    batch_id = str(uuid.uuid4())
    batch_at = utc_now()  # mốc để undo phát hiện chương bị sửa tiếp sau batch
    # Chỉ giữ 1 batch gần nhất cho mỗi truyện → xoá batch cũ trước khi ghi batch mới.
    db.execute(sa_delete(ChapterRevision).where(ChapterRevision.story_id == story_id))

    changed_hits: list[ReplaceChapterHit] = []
    changed = 0
    total = 0
    for chapter in rows:
        new_content, n_content = glossary_service.replace_all(
            chapter.content, rx, replace
        )
        new_title = chapter.title
        n_title = 0
        if payload.include_titles:
            new_title, n_title = glossary_service.replace_all(chapter.title, rx, replace)
        if n_content == 0 and n_title == 0:
            continue
        db.add(
            ChapterRevision(
                chapter_id=chapter.id,
                story_id=story_id,
                title=chapter.title,
                content=chapter.content,
                batch_id=batch_id,
                created_at=batch_at,
            )
        )
        chapter.content = new_content
        chapter.title = new_title
        # Cập nhật bằng đúng mốc batch → undo so sánh được, không nhầm "đã sửa tiếp"
        chapter.updated_at = batch_at
        changed += 1
        total += n_content + n_title
        changed_hits.append(
            ReplaceChapterHit(
                chapterId=chapter.id,
                chapterNo=chapter.chapter_index,
                matches=n_content + n_title,
            )
        )

    if payload.apply_to_future:
        db.add(
            StoryGlossary(
                story_id=story_id,
                find_text=find,
                replace_text=replace,
                match_case=payload.match_case,
                whole_word=payload.whole_word,
                apply_to_future=True,
            )
        )

    story.updated_at = utc_now()
    db.commit()  # một transaction cho toàn bộ lần thay

    return ReplaceOut(
        dryRun=False,
        totalMatches=total,
        chapters=changed_hits,
        batchId=batch_id,
        chaptersChanged=changed,
    )


@router.post("/stories/{story_id}/replace/undo", response_model=UndoOut)
def undo_replace(
    story_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> UndoOut:
    """Hoàn tác lần thay thế gần nhất của truyện (chỉ chủ truyện).

    Chương đã bị sửa tiếp sau batch (`UpdatedAt > snapshot`) được **bỏ qua** và
    đếm vào `skipped`; batch được tiêu thụ sau khi hoàn tác xong.
    """
    get_owned_story(db, story_id, user)
    revisions = list(
        db.execute(
            select(ChapterRevision)
            .where(ChapterRevision.story_id == story_id)
            .order_by(ChapterRevision.id)
        )
        .scalars()
        .all()
    )
    if not revisions:
        raise HTTPException(
            status_code=400, detail="Chưa có lần thay thế nào để hoàn tác"
        )

    restored = 0
    skipped = 0
    for revision in revisions:
        chapter = db.get(Chapter, revision.chapter_id)
        if chapter is None or chapter.updated_at > revision.created_at:
            skipped += 1  # chương đã bị xoá hoặc sửa tiếp sau batch
            continue
        chapter.content = revision.content
        chapter.title = revision.title
        chapter.updated_at = utc_now()
        restored += 1

    db.execute(sa_delete(ChapterRevision).where(ChapterRevision.story_id == story_id))
    story = db.get(Story, story_id)
    if story is not None:
        story.updated_at = utc_now()
    db.commit()

    message = f"Đã hoàn tác {restored} chương"
    if skipped:
        message += f" — {skipped} chương đã bị sửa sau đó nên bỏ qua"
    return UndoOut(message=message, restored=restored, skipped=skipped)


@router.get("/stories/{story_id}/glossary", response_model=list[GlossaryRuleOut])
def list_glossary(
    story_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> list[GlossaryRuleOut]:
    """Danh sách quy tắc tìm & thay thế đã lưu của truyện (chỉ chủ truyện)."""
    get_owned_story(db, story_id, user)
    rules = glossary_service.load_rules(db, story_id)
    return [
        GlossaryRuleOut(
            id=rule.id,
            findText=rule.find_text,
            replaceText=rule.replace_text,
            matchCase=rule.match_case,
            wholeWord=rule.whole_word,
            applyToFuture=rule.apply_to_future,
            createdAt=rule.created_at,
        )
        for rule in rules
    ]


@router.delete("/stories/{story_id}/glossary/{rule_id}")
def delete_glossary_rule(
    story_id: int,
    rule_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Xoá một quy tắc của truyện (chỉ chủ truyện; không có → 404)."""
    get_owned_story(db, story_id, user)
    rule = db.get(StoryGlossary, rule_id)
    if rule is None or rule.story_id != story_id:
        raise HTTPException(status_code=404, detail="Không tìm thấy quy tắc")
    db.delete(rule)
    db.commit()
    return {"message": "Đã xoá quy tắc"}
