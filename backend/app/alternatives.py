"""Marker nhiều nghĩa `{nghĩa1|nghĩa2|nghĩa3}` trong bản dịch thô.

Khi `vietphrase.convert` gặp một mục từ điển có nhiều nghĩa (tách bằng `/`), nó
xuất marker thay vì chỉ lấy nghĩa đầu — để người đăng truyện **chọn nghĩa** trên
màn Sửa chương. Ký tự phân cách thống nhất là `|`; parser vẫn đọc được dạng cũ
`{nghĩa1:nghĩa2}` (dạng này từng xuất hiện trong `vietphrase.txt` trước khi có
marker chính thức).

**Marker KHÔNG BAO GIỜ chứa chữ Trung** — chỉ nghĩa tiếng Việt:

- Định dạng chuẩn: `{nghĩa1|nghĩa2}` (nghĩa đầu = mặc định). Mọi phần tử chứa
  ký tự CJK (chữ Hán + dấu câu CJK) bị LOẠI khi parse/build/resolve/count —
  không bao giờ đến được người đăng hay người đọc.
- Dữ liệu cũ `{中文|nghĩa1|nghĩa2}` (trước đây đặt khóa chữ Trung ở segment
  đầu) vẫn đọc được: phần chữ Hán tách ra làm **khóa cũ** ([Marker.key] — chỉ
  dùng nội bộ để tra ngược khi cần), phần Việt giữ làm danh sách nghĩa; người
  dùng không bao giờ thấy chữ Hán. Lưu chương / `POST /markers/clean` ghi lại
  dạng sạch (xem [normalize]).
- Người đọc **không bao giờ** thấy dấu `{}` — `resolve` trả nghĩa đầu.

Quy tắc:
- Marker chỉ hợp lệ khi có **≥ 2 nghĩa Việt khác nhau**; nghĩa đầu tiên là
  mặc định; tối đa [MAX_ALTERNATIVES] nghĩa, loại nghĩa trống/duplicate/CJK.
- Sau khi loại chữ Hán còn < 2 nghĩa → không còn là marker: `parse`/`count`
  bỏ qua, `resolve`/`normalize` lấy nghĩa đầu Việt còn lại và bỏ `{}`.
- Truyện cũ không có marker vẫn chạy bình thường (resolve giữ nguyên văn bản).

Dùng được ở backend (đọc/ghi bản thô) và tham chiếu đúng định dạng ở Flutter
(`lib/utils/alternatives.dart` phải khớp với module này).
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass

# Trần số nghĩa trong một marker
MAX_ALTERNATIVES = 6

# Một marker: `{a|b}` hoặc dữ liệu cũ `{中文|a|b}` / `{a:b}` (không lồng nhau)
_MARKER_RE = re.compile(r"\{([^{}]+)\}")

# Ký tự CJK — chữ Hán BMP + mở rộng + dấu câu/ký tự CJK.
# GIỐNG HỆT `lib/utils/alternatives.dart` để hai phía parse khớp nhau.
_CJK_RE = re.compile(
    r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff"  # chữ Hán
    r"\u3000-\u303f\uff01-\uff60\ufe30-\ufe4f]"  # dấu câu / ký tự CJK
)


def has_cjk(value: str) -> bool:
    """True nếu chuỗi chứa ký tự CJK (chữ Hán hoặc dấu câu CJK)."""
    return _CJK_RE.search(value) is not None


# Tên cũ — giữ tham chiếu ngoài không vỡ (cùng ngữ nghĩa: nhận diện ký tự CJK)
has_han = has_cjk


@dataclass(frozen=True)
class Marker:
    """Một chỗ nhiều nghĩa trong văn bản: `[start, end)` là vùng `{...}`."""

    start: int
    end: int
    text: str  # đúng chuỗi `{...}` trong văn bản (dữ liệu cũ có thể còn khóa)
    meanings: tuple[str, ...]  # ≥ 2 nghĩa VIỆT, thứ tự: nghĩa đầu = mặc định
    key: str | None = None  # khóa cũ (chữ Hán) — chỉ dữ liệu cũ, không hiển thị

    @property
    def first(self) -> str:
        return self.meanings[0]


def _split_parts(inner: str) -> tuple[str | None, list[str]]:
    """Tách nội dung marker thành (khóa cũ, danh sách nghĩa Việt).

    - `a|b|c`    → khóa `None`, nghĩa `[a, b, c]` (dạng chuẩn, không chữ Hán);
    - `中文|a|b`  → khóa `中文`, nghĩa `[a, b]` (DỮ LIỆU CŨ: segment chữ Hán
      đầu tiên là khóa cũ — tách ra, không bao giờ hiển thị);
    - `a:b`      → dạng cũ (tách theo `:` khi không có `|`);
    - `abc`      → một nghĩa duy nhất.

    Mọi phần tử chứa ký tự CJK đều bị loại khỏi nghĩa (giữ thứ tự, bỏ trống
    và trùng). Khóa cũ = phần tử CJK đầu tiên (nếu có) — dùng để tra cứu khi
    cần với dữ liệu cũ, không nằm trong danh sách nghĩa.
    """
    if "|" in inner:
        raw = inner.split("|")
    elif ":" in inner:
        raw = inner.split(":")
    else:
        raw = [inner]
    parts: list[str] = []
    cjk_parts: list[str] = []
    for part in raw:
        value = part.strip()
        if not value:
            continue
        if has_cjk(value):
            if value not in cjk_parts:
                cjk_parts.append(value)
        elif value not in parts:
            parts.append(value)
    key = cjk_parts[0] if cjk_parts else None
    return key, parts


def split_key(inner: str) -> str | None:
    """Khóa cũ (segment chữ Hán) của marker — chỉ dữ liệu cũ có; không hiển thị."""
    return _split_parts(inner)[0]


def split_meanings(inner: str) -> list[str]:
    """Danh sách NGHĨA VIỆT của marker (đã bỏ mọi phần tử chữ Hán/CJK)."""
    return _split_parts(inner)[1]


def parse(text: str) -> list[Marker]:
    """Liệt kê mọi marker trong [text] kèm vị trí, nghĩa Việt và khóa cũ (nếu có).

    Marker hợp lệ cần **≥ 2 nghĩa Việt** — sau khi loại chữ Hán còn < 2 thì
    không còn là chỗ chọn nghĩa (resolve sẽ lấy nghĩa đầu còn lại, bỏ `{}`).
    """
    if not text or "{" not in text:
        return []
    markers: list[Marker] = []
    for m in _MARKER_RE.finditer(text):
        key, meanings = _split_parts(m.group(1))
        if len(meanings) < 2:
            continue
        markers.append(
            Marker(
                start=m.start(),
                end=m.end(),
                text=m.group(0),
                meanings=tuple(meanings),
                key=key,
            )
        )
    return markers


def count(text: str) -> int:
    """Số chỗ chưa chọn nghĩa (= số marker còn trong văn bản)."""
    return len(parse(text))


def resolve(text: str, mode: str | int = "first") -> str:
    """Bỏ toàn bộ marker (kể cả khóa), thay mỗi marker bằng một nghĩa.

    - `mode="first"` (mặc định) — nghĩa đầu (nghĩa người đọc xem);
    - `mode="last"` — nghĩa cuối;
    - `mode=<số>` — nghĩa ở vị trí đó (ngoài danh sách → nghĩa đầu).

    Văn bản không có marker được trả về nguyên vẹn (truyện cũ).
    """
    if not text or "{" not in text:
        return text or ""

    def _pick(m: re.Match) -> str:
        _key, meanings = _split_parts(m.group(1))
        if not meanings:
            return ""
        if mode == "last":
            return meanings[-1]
        if isinstance(mode, int):
            idx = mode if 0 <= mode < len(meanings) else 0
            return meanings[idx]
        return meanings[0]

    return _MARKER_RE.sub(_pick, text)


def clean_meanings(values: Iterable[str]) -> list[str]:
    """Loại phần tử rỗng / trùng / chứa ký tự CJK — mọi nghĩa phải là tiếng Việt."""
    out: list[str] = []
    for value in values:
        item = str(value).strip()
        if item and not has_cjk(item) and item not in out:
            out.append(item)
    return out


def build(meanings: Iterable[str]) -> str:
    """Ghép danh sách nghĩa thành marker `{a|b}` — trả `""` nếu không hợp lệ.

    Hợp lệ khi có ≥ 2 nghĩa Việt khác nhau sau khi bỏ trống/duplicate/CJK,
    ≤ 6 nghĩa. KHÔNG kèm khóa Trung — marker sinh ra chỉ chứa nghĩa tiếng Việt.
    """
    clean = clean_meanings(meanings)
    if len(clean) < 2:
        return ""
    return "{" + "|".join(clean[:MAX_ALTERNATIVES]) + "}"


def normalize(text: str) -> str:
    """Viết lại MỌI marker trong [text] về dạng sạch — dữ liệu cũ → chuẩn:

    - bỏ phần tử chữ Hán (khóa cũ) và trùng lặp: `{为|vì|là|vi}` → `{vì|là|vi}`;
    - sau khi loại còn 2+ nghĩa → marker `{a|b}`; còn 1 nghĩa → giữ nghĩa đó,
      bỏ `{}`; còn 0 → bỏ hẳn chỗ đó (không để lại dấu {}).

    Văn bản không có `{}` giữ nguyên. Dùng khi đọc bản thô (`?raw=1`), khi lưu
    chương và ở `POST /stories/{id}/markers/clean`.
    """
    if not text or "{" not in text:
        return text or ""

    def _clean(m: re.Match) -> str:
        _key, meanings = _split_parts(m.group(1))
        if len(meanings) >= 2:
            return "{" + "|".join(meanings[:MAX_ALTERNATIVES]) + "}"
        if meanings:
            return meanings[0]  # < 2 nghĩa → không còn là marker
        return ""  # không còn nghĩa Việt nào → bỏ chỗ đó

    return _MARKER_RE.sub(_clean, text)


def clean_count(text: str) -> int:
    """Số chỗ trong [text] cần dọn về dạng sạch (chứa chữ Hán / < 2 nghĩa)."""
    if not text or "{" not in text:
        return 0
    return sum(
        1 for m in _MARKER_RE.finditer(text) if normalize(m.group(0)) != m.group(0)
    )


def expand(value: str) -> list[str]:
    """Gỡ marker **cũ** nằm trong một nghĩa của từ điển thành nhiều nghĩa.

    Vd `định {vì:là}` → `["định vì", "định là"]`; `{không là:không vì}` →
    `["không là", "không vì"]`; marker một nghĩa `{card siêu nhân}` →
    `["card siêu nhân"]` (bỏ dấu `{}`). Văn bản không có `{}` → giữ nguyên.

    Ghi chú: marker trong GIÁ TRỊ từ điển không bao giờ có khóa chữ Trung nên
    dùng thẳng [split_meanings] cũ (tách nghĩa, không diễn giải khóa).
    """
    if not value or "{" not in value:
        return [value] if value.strip() else []
    results = [value]
    for m in list(_MARKER_RE.finditer(value)):
        inner = _legacy_parts(m.group(1)) or [""]
        results = [
            base[: m.start()] + meaning + base[m.end() :]
            for base in results
            for meaning in inner
        ]
    return [r for r in results if r.strip()]


def _legacy_parts(inner: str) -> list[str]:
    """Tách marker CŨ trong giá trị từ điển — thuần nghĩa, không có khóa."""
    if "|" in inner:
        raw = inner.split("|")
    elif ":" in inner:
        raw = inner.split(":")
    else:
        raw = [inner]
    out: list[str] = []
    for part in raw:
        value = part.strip()
        if value and value not in out:
            out.append(value)
    return out
