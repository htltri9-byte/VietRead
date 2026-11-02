"""Nghĩa đã chọn / khóa "không hỏi lại" + quy tắc học từ hành vi người đăng.

- `StoryWordChoices` — người đăng bấm "Luôn dùng nghĩa này cho truyện này":
  từ nay khi dịch/dịch lại chương của truyện đó, khóa này tự dùng đúng nghĩa,
  không tạo marker nữa.
- `StoryIgnoredWords` — "Không hỏi lại từ này" (của riêng truyện, KHÔNG đụng
  file chung `no_mark.txt`): khóa này không bao giờ tạo marker trong truyện.
- `UserWordStats` / `UserMarkRules` — HỌC HÀNH VI: mỗi lượt "không hỏi lại"
  (bất kỳ truyện nào) +1 thống kê; đủ `LEARN_SKIP_THRESHOLD` lần → sinh quy
  tắc này cho mọi truyện của người đó; xoá quy tắc → marker trở lại.

Hai hàm nạp ở đây được gọi trước mỗi lần dịch chương (import link/văn bản,
dịch lại) rồi truyền vào `translate_text(..., key_choices=, skip_keys=)` —
trong đó `skip_keys` = bỏ hỏi của riêng truyện ∪ quy tắc đã học của NGƯỜI ĐĂNG.
Mọi truy vấn khoá theo `story_id` / `user_id` nên không ảnh hưởng cái khác.
"""

from __future__ import annotations

import os

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import StoryIgnoredWord, StoryWordChoice, UserMarkRule, UserWordStat


def load_choices(db: Session, story_id: int) -> dict[str, str]:
    """Ánh xạ khóa → nghĩa đã chọn của truyện (dùng thẳng khi dịch)."""
    rows = db.execute(
        select(StoryWordChoice.source_key, StoryWordChoice.chosen_text).where(
            StoryWordChoice.story_id == story_id
        )
    ).all()
    return {source_key: chosen for source_key, chosen in rows}


def load_skips(db: Session, story_id: int) -> set[str]:
    """Tập khóa "không hỏi lại" của truyện (không tạo marker nữa)."""
    rows = db.execute(
        select(StoryIgnoredWord.source_key).where(
            StoryIgnoredWord.story_id == story_id
        )
    ).all()
    return {source_key for (source_key,) in rows}


# ---------------------------------------------------------------------------
# Học hành vi người đăng — UserWordStats → UserMarkRules (quy tắc toàn cục)
# ---------------------------------------------------------------------------


def learn_skip_threshold() -> int:
    """Số lượt bỏ qua tối thiểu để sinh quy tắc — `LEARN_SKIP_THRESHOLD` (.env).

    Mặc định 5; giá trị rỗng/không phải số → 5; <= 0 → tắt học (không sinh
    quy tắc bao giờ). Đọc mỗi lần gọi — sửa `.env` không cần restart.
    """
    raw = (os.getenv("LEARN_SKIP_THRESHOLD") or "").strip()
    try:
        return int(raw) if raw else 5
    except ValueError:
        return 5


def record_skip(db: Session, user_id: int, source_key: str) -> int:
    """Ghi +1 lượt "không hỏi lại" của NGƯỜI DÙNG cho khóa (tích luỹ mọi truyện).

    Trả về SkipCount hiện tại. Đủ ngưỡng `LEARN_SKIP_THRESHOLD` → tạo (hoặc
    cập nhật) `UserMarkRule` — từ đó khóa không marker nữa ở mọi truyện của
    người này; xoá quy tắc ở màn Quy tắc thì marker trở lại. Tự commit riêng
    (gọi từ endpoint ignore sau khi đã ghi dòng theo truyện).
    """
    row = db.execute(
        select(UserWordStat).where(
            UserWordStat.user_id == user_id,
            UserWordStat.source_key == source_key,
        )
    ).scalar_one_or_none()
    if row is None:
        row = UserWordStat(user_id=user_id, source_key=source_key, skip_count=1)
        db.add(row)
    else:
        row.skip_count += 1
    try:
        db.commit()
    except Exception:  # request song song ghi trùng (unique index)
        db.rollback()
        row = db.execute(
            select(UserWordStat).where(
                UserWordStat.user_id == user_id,
                UserWordStat.source_key == source_key,
            )
        ).scalar_one()
        row.skip_count += 1
        db.commit()
    count = row.skip_count

    threshold = learn_skip_threshold()
    if threshold <= 0 or count < threshold:
        return count

    # Đủ ngưỡng → sinh quy tắc (idempotent: đã có thì chỉ cập nhật số lượt).
    rule = db.execute(
        select(UserMarkRule).where(
            UserMarkRule.user_id == user_id,
            UserMarkRule.source_key == source_key,
        )
    ).scalar_one_or_none()
    if rule is None:
        db.add(
            UserMarkRule(
                user_id=user_id, source_key=source_key, skip_count=count
            )
        )
    else:
        rule.skip_count = count
    try:
        db.commit()
    except Exception:  # request song song vừa tạo quy tắc trùng
        db.rollback()
    return count


def load_learned_keys(db: Session, user_id: int) -> set[str]:
    """Tập khóa đã học của NGƯỜI ĐĂNG (UserMarkRules) — thêm vào skip_keys."""
    rows = db.execute(
        select(UserMarkRule.source_key).where(UserMarkRule.user_id == user_id)
    ).all()
    return {source_key for (source_key,) in rows}
