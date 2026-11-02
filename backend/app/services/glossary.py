"""Quy tắc "Tìm & thay thế" riêng của từng truyện (bảng `StoryGlossary`).

- [build_regex] — dựng regex Unicode bằng `re.escape` (không nuốt chữ có dấu),
  `wholeWord` dùng ranh giới `(?<!\\w)` / `(?!\\w)`, `matchCase=False` → không
  phân biệt hoa thường.
- [apply_rules] — áp dụng các quy tắc `ApplyToFuture` của một truyện lên bản
  dịch của chương MỚI trước khi lưu (import cả bộ, thêm chương link/văn bản,
  dịch lại, thêm chương tay). Quy tắc chỉ tác động tới truyện sở hữu nó.

Thay thế chạy trên **bản thô** — kể cả bên trong marker `{a|b}` (đúng yêu cầu),
và mọi thao tác đều nằm trong router để transaction của request giữ nguyên.
"""

from __future__ import annotations

import re
import unicodedata

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import StoryGlossary

# Trần chuỗi find/replace — khớp NVARCHAR(200) trong schema
MAX_FIND_CHARS = 200


def validate_pair(find: str, replace: str) -> None:
    """Kiểm tra cặp tìm/thay — ném ValueError kèm thông báo tiếng Việt (→ 400)."""
    if not find.strip():
        raise ValueError("Chuỗi cần tìm không được để trống")
    if len(find) > MAX_FIND_CHARS:
        raise ValueError(f"Chuỗi cần tìm tối đa {MAX_FIND_CHARS} ký tự")
    if find == replace:
        raise ValueError("Chuỗi cần tìm và chuỗi thay thế không được giống nhau")


def build_regex(
    find: str, match_case: bool = False, whole_word: bool = False
) -> re.Pattern[str]:
    """Dựng regex cho một quy tắc (chuỗi find đã validate)."""
    pattern = re.escape(unicodedata.normalize("NFC", find))
    if whole_word:
        pattern = rf"(?<!\w){pattern}(?!\w)"
    return re.compile(pattern, 0 if match_case else re.IGNORECASE)


def count_matches(text: str, rx: re.Pattern[str]) -> int:
    """Số chỗ khớp trong một đoạn văn bản (0 nếu rỗng)."""
    if not text:
        return 0
    return len(rx.findall(text))


def replace_all(text: str, rx: re.Pattern[str], replacement: str) -> tuple[str, int]:
    """Thay mọi chỗ khớp — trả (văn bản mới, số chỗ). Dùng hàm thay để
    `replacement` không bị coi là group reference (`\\1`, `\\g<0>`)."""
    if not text:
        return text, 0
    return rx.subn(lambda _m: replacement, text)


def load_rules(db: Session, story_id: int) -> list[StoryGlossary]:
    """Mọi quy tắc của một truyện, xếp theo thứ tự tạo (thứ tự áp dụng)."""
    return list(
        db.execute(
            select(StoryGlossary)
            .where(StoryGlossary.story_id == story_id)
            .order_by(StoryGlossary.id)
        )
        .scalars()
        .all()
    )


def load_future_rules(db: Session, story_id: int) -> list[StoryGlossary]:
    """Chỉ quy tắc có ApplyToFuture — dùng cho chương thêm sau này."""
    return [
        rule
        for rule in load_rules(db, story_id)
        if rule.apply_to_future
    ]


def apply_rules(
    db: Session,
    story_id: int,
    text: str,
    rules: list[StoryGlossary] | None = None,
) -> tuple[str, int]:
    """Áp dụng mọi quy tắc ApplyToFuture của truyện [story_id] lên [text].

    Trả `(văn bản sau thay, tổng số chỗ đã thay)`. Không đụng truyện khác
    (mọi truy vấn đều khoá theo story_id).

    [rules] — danh sách do [load_future_rules] nạp sẵn khi áp cho nhiều chương
    (import cả bộ) để không query lại mỗi chương; mặc định None thì tự nạp.
    """
    total = 0
    for rule in load_future_rules(db, story_id) if rules is None else rules:
        rx = build_regex(rule.find_text, rule.match_case, rule.whole_word)
        text, n = replace_all(text, rx, rule.replace_text)
        total += n
    return text, total
