"""Gợi ý nhiều nghĩa theo truyện — dọn marker (clean) + nghĩa đã chọn / bỏ hỏi.

- ``POST /stories/{id}/markers/clean`` — dọn chữ Hán/khóa cũ khỏi marker của
  dữ liệu cũ (``{为|vì|là|vi}`` → ``{vì|là|vi}``), snapshot vào
  ``ChapterRevisions`` để hoàn tác bằng ``POST /stories/{id}/replace/undo``.
- ``GET/POST /stories/{id}/word-choices`` + ``DELETE .../word-choices/{cid}`` —
  "Luôn dùng nghĩa này cho truyện này": dịch/dịch lại chương của truyện đó tự
  dùng đúng nghĩa, không tạo marker (bảng ``StoryWordChoices``).
- ``GET/POST /stories/{id}/ignored-words`` + ``DELETE .../ignored-words/{wid}`` —
  "Không hỏi lại từ này" của RIÊNG truyện, không đụng file chung
  ``no_mark.txt`` (bảng ``StoryIgnoredWords``).

POST word-choices / ignored-words nhận **danh sách nghĩa của marker**
(``meanings``) — backend tra ngược khóa từ điển (mọi khóa có marker trùng
nghĩa) thay vì bắt client gửi chữ Hán; ``sourceKey`` vẫn nhận cho client cũ.

Mọi endpoint chỉ chủ truyện (401 khi chưa đăng nhập, 403 với người khác,
404 khi truyện không tồn tại); mọi truy vấn khoá theo ``StoryId``.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete as sa_delete
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import alternatives, security, vietphrase
from ..database import get_db
from ..moderation import mark_needs_recheck
from ..models import (
    Chapter,
    ChapterRevision,
    StoryIgnoredWord,
    StoryWordChoice,
    User,
    UserMarkRule,
)
from ..schemas import (
    IgnoredWordIn,
    IgnoredWordOut,
    IgnoredWordSavedOut,
    MarkRuleOut,
    ResolveAllOut,
    ResolveAllRequest,
    WordChoiceIn,
    WordChoiceOut,
    WordChoiceSavedOut,
)
from ..services.story_words import record_skip
from .stories import get_owned_story, utc_now

router = APIRouter(tags=["markers"])


# ---------------------------------------------------------------------------
# Dọn marker: dọn chữ Hán dữ liệu cũ (hoàn tác được)
# ---------------------------------------------------------------------------


@router.post(
    "/stories/{story_id}/markers/clean",
    response_model=ResolveAllOut,
)
def clean_markers(
    story_id: int,
    payload: ResolveAllRequest | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ResolveAllOut:
    """Dọn chữ Hán / ký tự CJK khỏi marker của mọi chương (chỉ chủ truyện).

    Dữ liệu cũ ``{为|vì|là|vi}`` → ``{vì|là|vi}``; sau khi loại còn < 2 nghĩa
    thì giữ nghĩa đầu Việt còn lại và bỏ ``{}``. Chương có đổi được snapshot
    vào ``ChapterRevisions`` — hoàn tác bằng ``POST /stories/{id}/replace/undo``
    (một batch gần nhất/truyện). `onlyChapterId` body tuỳ chọn.
    Không đụng `OriginalContent`, không đụng truyện khác.
    """
    story = get_owned_story(db, story_id, user)
    query = select(Chapter).where(Chapter.story_id == story_id).order_by(
        Chapter.chapter_index
    )
    if payload is not None and payload.only_chapter_id is not None:
        query = query.where(Chapter.id == payload.only_chapter_id)
    rows = list(db.execute(query).scalars().all())
    if payload is not None and payload.only_chapter_id is not None and not rows:
        raise HTTPException(
            status_code=404, detail="Không tìm thấy chương trong truyện này"
        )

    batch_id = str(uuid.uuid4())
    batch_at = utc_now()
    db.execute(sa_delete(ChapterRevision).where(ChapterRevision.story_id == story_id))

    changed = 0
    cleaned_total = 0
    for chapter in rows:
        if "{" not in chapter.content:
            continue
        cleaned = alternatives.normalize(chapter.content)
        if cleaned == chapter.content:
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
        cleaned_total += alternatives.clean_count(chapter.content)
        chapter.content = cleaned
        chapter.updated_at = batch_at
        changed += 1

    if changed == 0:
        db.rollback()
        raise HTTPException(
            status_code=400,
            detail="Không còn chữ Hán nào trong marker của truyện này",
        )

    story.updated_at = utc_now()
    mark_needs_recheck(story)   # approved → Admin cần xem lại nội dung đã đổi
    db.commit()

    target = (
        f"chương {rows[0].chapter_index}"
        if payload and payload.only_chapter_id
        else f"{changed} chương"
    )
    return ResolveAllOut(
        message=f"Đã dọn chữ Hán khỏi {cleaned_total} marker trong {target}",
        batchId=batch_id,
        chaptersChanged=changed,
        markersResolved=cleaned_total,
    )


# ---------------------------------------------------------------------------
# "Luôn dùng nghĩa này cho truyện này" — StoryWordChoices
# ---------------------------------------------------------------------------


def _choice_out(row: StoryWordChoice) -> WordChoiceOut:
    return WordChoiceOut(
        id=row.id,
        sourceKey=row.source_key,
        chosenText=row.chosen_text,
        createdAt=row.created_at,
    )


def _resolve_keys(payload: WordChoiceIn | IgnoredWordIn) -> list[str]:
    """Khóa sẽ ghi cho request: ``sourceKey`` (client cũ) + tra ngược từ
    ``meanings`` (mọi khóa có marker trùng danh sách nghĩa — áp cho tất cả)."""
    keys: list[str] = []
    if payload.source_key:
        keys.append(payload.source_key)
    for key in vietphrase.keys_for_meanings(payload.meanings or []):
        if key not in keys:
            keys.append(key)
    if not keys:
        raise HTTPException(
            status_code=400,
            detail="Không tra được khóa từ điển từ danh sách nghĩa",
        )
    return keys


@router.get("/stories/{story_id}/word-choices", response_model=list[WordChoiceOut])
def list_word_choices(
    story_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> list[WordChoiceOut]:
    """Nghĩa đã lưu "luôn dùng" của truyện (chỉ chủ truyện — màn quy tắc)."""
    get_owned_story(db, story_id, user)
    rows = list(
        db.execute(
            select(StoryWordChoice)
            .where(StoryWordChoice.story_id == story_id)
            .order_by(StoryWordChoice.id.desc())
        )
        .scalars()
        .all()
    )
    return [_choice_out(row) for row in rows]


@router.post("/stories/{story_id}/word-choices", response_model=WordChoiceSavedOut)
def save_word_choice(
    story_id: int,
    payload: WordChoiceIn,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> WordChoiceSavedOut:
    """Lưu/khóa nghĩa cho một từ của truyện này (chỉ chủ truyện).

    Khóa cần ghi được tra từ [payload.meanings] (danh sách nghĩa của marker —
    client không gửi chữ Hán) hoặc [payload.source_key] (client cũ); nhiều khóa
    trùng danh sách nghĩa → lưu cho TẤT cả. Ghi trùng khóa → cập nhật nghĩa
    mới nhất. Từ nay khi dịch/dịch lại chương của truyện này, khóa tự dùng
    [chosenText], không tạo marker. Phản hồi kèm ``affectedIds`` để hoàn tác.
    """
    get_owned_story(db, story_id, user)
    keys = _resolve_keys(payload)
    existing = {
        row.source_key: row
        for row in db.execute(
            select(StoryWordChoice).where(
                StoryWordChoice.story_id == story_id,
                StoryWordChoice.source_key.in_(keys),
            )
        )
        .scalars()
        .all()
    }
    rows: list[StoryWordChoice] = []
    for key in keys:
        row = existing.get(key)
        if row is None:
            row = StoryWordChoice(
                story_id=story_id,
                source_key=key,
                chosen_text=payload.chosen_text,
            )
            db.add(row)
        else:
            row.chosen_text = payload.chosen_text
        rows.append(row)
    try:
        db.commit()
    except Exception:  # request song song ghi trùng (unique index)
        db.rollback()
        raise HTTPException(status_code=409, detail="Nghĩa đã được lưu bởi request khác")
    for row in rows:
        db.refresh(row)
    first = rows[0]
    return WordChoiceSavedOut(
        id=first.id,
        sourceKey=first.source_key,
        chosenText=first.chosen_text,
        createdAt=first.created_at,
        affectedIds=[row.id for row in rows],
    )


@router.delete("/stories/{story_id}/word-choices/{choice_id}")
def delete_word_choice(
    story_id: int,
    choice_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Xoá một nghĩa đã lưu của truyện (chỉ chủ truyện; không có → 404)."""
    get_owned_story(db, story_id, user)
    row = db.get(StoryWordChoice, choice_id)
    if row is None or row.story_id != story_id:
        raise HTTPException(status_code=404, detail="Không tìm thấy nghĩa đã lưu")
    db.delete(row)
    db.commit()
    return {"message": "Đã xoá nghĩa đã lưu"}


# ---------------------------------------------------------------------------
# "Không hỏi lại từ này" — StoryIgnoredWords (riêng truyện, không sửa file chung)
# ---------------------------------------------------------------------------


def _ignore_out(row: StoryIgnoredWord) -> IgnoredWordOut:
    return IgnoredWordOut(
        id=row.id,
        sourceKey=row.source_key,
        createdAt=row.created_at,
    )


@router.get("/stories/{story_id}/ignored-words", response_model=list[IgnoredWordOut])
def list_ignored_words(
    story_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> list[IgnoredWordOut]:
    """Danh sách từ "không hỏi lại" của truyện (chỉ chủ truyện)."""
    get_owned_story(db, story_id, user)
    rows = list(
        db.execute(
            select(StoryIgnoredWord)
            .where(StoryIgnoredWord.story_id == story_id)
            .order_by(StoryIgnoredWord.id.desc())
        )
        .scalars()
        .all()
    )
    return [_ignore_out(row) for row in rows]


@router.post("/stories/{story_id}/ignored-words", response_model=IgnoredWordSavedOut)
def ignore_word(
    story_id: int,
    payload: IgnoredWordIn,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> IgnoredWordSavedOut:
    """Thêm khóa vào danh sách "không hỏi lại" của riêng truyện này (idempotent).

    Khóa tra từ [payload.meanings] (danh sách nghĩa marker — client không gửi
    chữ Hán) hoặc [payload.source_key] (client cũ); nhiều khóa trùng danh sách
    nghĩa → bỏ hỏi cho TẤT cả. Mỗi lượt bấm còn +1 thống kê hành vi của
    NGƯỜI DÙNG (UserWordStats) ở TỪNG khóa — đủ `LEARN_SKIP_THRESHOLD` lượt →
    sinh quy tắc UserMarkRule, khóa này hết hỏi ở mọi truyện; xoá quy tắc ở
    `DELETE /me/mark-rules/{id}` thì trở lại. Phản hồi kèm ``affectedIds``.
    """
    get_owned_story(db, story_id, user)
    keys = _resolve_keys(payload)
    existing = {
        row.source_key: row
        for row in db.execute(
            select(StoryIgnoredWord).where(
                StoryIgnoredWord.story_id == story_id,
                StoryIgnoredWord.source_key.in_(keys),
            )
        )
        .scalars()
        .all()
    }
    rows: list[StoryIgnoredWord] = []
    created = False
    for key in keys:
        row = existing.get(key)
        if row is None:
            row = StoryIgnoredWord(story_id=story_id, source_key=key)
            db.add(row)
            created = True
        rows.append(row)
    if created:
        try:
            db.commit()
        except Exception:  # request song song ghi trùng
            db.rollback()
            raise HTTPException(
                status_code=409, detail="Danh sách đã được ghi bởi request khác"
            )
    # Hành "bỏ hỏi" của người đăng — tách riêng commit (tự ghi stat + quy tắc),
    # tính MỖI khóa để quy tắc học được sinh đúng khóa.
    for key in keys:
        record_skip(db, user.id, key)
    for row in rows:
        db.refresh(row)
    first = rows[0]
    return IgnoredWordSavedOut(
        id=first.id,
        sourceKey=first.source_key,
        createdAt=first.created_at,
        affectedIds=[row.id for row in rows],
    )


@router.delete("/stories/{story_id}/ignored-words/{word_id}")
def delete_ignored_word(
    story_id: int,
    word_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Bỏ một khóa khỏi danh sách "không hỏi lại" (chỉ chủ truyện; 404 nếu không có)."""
    get_owned_story(db, story_id, user)
    row = db.get(StoryIgnoredWord, word_id)
    if row is None or row.story_id != story_id:
        raise HTTPException(status_code=404, detail="Không tìm thấy từ trong danh sách")
    db.delete(row)
    db.commit()
    return {"deleted": True}


# ---------------------------------------------------------------------------
# Quy tắc học từ hành vi — GET/DELETE /me/mark-rules (màn "Quy tắc")
# ---------------------------------------------------------------------------


def _rule_out(row: UserMarkRule) -> MarkRuleOut:
    return MarkRuleOut(
        id=row.id,
        source_key=row.source_key,
        skip_count=row.skip_count,
        created_at=row.created_at,
        # Nghĩa tiếng Việt để màn Quy tắc hiển thị — không lộ khóa chữ Trung
        meanings=vietphrase.meanings_for_key(row.source_key),
    )


@router.get("/me/mark-rules", response_model=list[MarkRuleOut])
def list_mark_rules(
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> list[MarkRuleOut]:
    """Quy tắc học từ hành vi của CHÍNH người đăng (màn Quy tắc: xem/xoá).

    Mỗi quy tắc = khóa đã bỏ hỏi đủ `LEARN_SKIP_THRESHOLD` lượt → khoá này
    không marker nữa ở mọi truyện của người này. Không đụng dữ liệu người khác.
    """
    rows = list(
        db.execute(
            select(UserMarkRule)
            .where(UserMarkRule.user_id == user.id)
            .order_by(UserMarkRule.id.desc())
        )
        .scalars()
        .all()
    )
    return [_rule_out(row) for row in rows]


@router.delete("/me/mark-rules/{rule_id}")
def delete_mark_rule(
    rule_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Xoá một quy tắc học được (khóa này lại được hỏi; 404 nếu không có).

    Không xoá thống kê `UserWordStats` — người dùng bỏ hỏi thêm đủ lượt nữa
    thì quy tắc được sinh lại từ đầu.
    """
    row = db.get(UserMarkRule, rule_id)
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Không tìm thấy quy tắc")
    db.delete(row)
    db.commit()
    return {"message": "Đã xoá quy tắc — từ này sẽ lại được hỏi"}
