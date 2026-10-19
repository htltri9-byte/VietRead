"""Bộ lọc quyết định một mục từ điển có được tạo marker hay không + 3 mức gợi ý.

Mục tiêu: chỉ đánh dấu những chỗ **thật sự đa nghĩa hoặc khó hiểu** — các nghĩa
khác hẳn nhau; phần còn lại tự lấy nghĩa đầu, không có `{}`.

Áp dụng **trong `vietphrase.convert`** (không phải ở giao diện). Một mục chỉ
thành marker khi qua được các bước:

1. **Chống trùng**: so nghĩa sau khi hạ chữ thường, bỏ dấu cách thừa/dấu câu —
   chỉ khác hoa/thường/dấu cách/trùng thì gộp ([merge_similar]).
2. **Gộp nghĩa gần giống**: A chứa B (hoặc ngược lại), ≥50% âm tiết trùng,
   hoặc bỏ từ đệm (`khá`, `rất`, `thật`, `hơi`… — [PARTICLES]) còn trùng nhau
   thì gộp. Sau gộp < 2 nghĩa → không đánh dấu.
2b. **Hán-Việt ↔ thuần Việt** ([_is_hanviet_native_pair]): một nghĩa đúng bằng
   âm Hán-Việt của khóa (tra `hanviet.txt`) và nghĩa khác thuần Việt (không
   âm tiết nào là âm Hán-Việt) → đồng nghĩa, không đánh dấu — vd `có|hữu`,
   `ba|tam`.
3. Khóa nằm trong `no_mark.txt` (trợ từ, lượng từ, liên từ...) → bỏ qua.
4. Khóa **một chữ Hán** → bỏ qua, trừ khi nằm trong `ambiguous.txt`.
5. Tên riêng (tên `names.txt`, kind == "name") → bỏ qua.
6. Chỉ đánh dấu khi khác nghĩa về Ý:
   - `ambiguous.txt` (danh sách trắng) → luôn đánh dấu (chỉ cần qua bước 1-2);
   - `synonyms.txt` (danh sách đen) → không bao giờ đánh dấu.
6b. **Ngưỡng độ khác nhau theo mức** ([_DISTINCT_MIN]): điểm [_distinctness]
   dưới ngưỡng → không đánh dấu (ngưỡng thấp nhất ở mức cao nhất).
   Mức Ít thêm luật tần suất: mọi nghĩa đều 1 âm tiết (trợ từ...) → bỏ.
7. Chấm điểm + trần mỗi chương ([cap_for]): low ≤ 15, medium ≤ 40,
   high = không giới hạn (gần như hành vi hiện tại, chỉ áp bước 1-2).

Kết quả [evaluate] được **cache theo khóa** ([_eval_cache]) — dịch chương
3000-5000 chữ không phải tính lại; cache xoá khi nạp lại danh sách.

**Danh sách đóng gói**: `ambiguous.seed.txt` / `synonyms.seed.txt` đi kèm repo
(nội dung mặc định, viết tay — KHÔNG sinh bằng AI/gọi mạng). Nạp theo thứ tự
ưu tiên: `ambiguous.txt` / `synonyms.txt` người dùng thắng khi mâu thuẫn →
seed đóng gói. Xem `dictionaries/README.md`.

**Ba mức** (`markLevel`):

- `low` (mặc định, `MARK_LEVEL` trong `.env`): chỉ khóa trong `ambiguous.txt`
  + các "luật cũ" `{vì:là}` viết tay trong `vietphrase.txt` (hinted). Nếu
  `ambiguous.txt` trống → dùng bộ lọc 1-5 nghiêm ngặt (kèm loại `synonyms.txt`).
- `medium`: khóa qua bộ lọc 1-5 + bước 6 (loại `synonyms.txt`).
- `high`: chỉ áp bước 1-2 (gộp trùng), không giới hạn số marker.

Ba file danh sách nằm cạnh `vietphrase.txt` (`backend/dictionaries/`), format:
mỗi dòng một khóa, `#` là chú thích, UTF-8 hoặc UTF-16 (theo BOM). Sửa file
xong **không cần restart**: [get_lists] tự nạp lại khi mtime đổi, hoặc bấm
`POST /dictionary/mark-lists/reload`.
"""

from __future__ import annotations

import os
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path

# Nằm cạnh vietphrase.txt (Path(__file__) = backend/app/marking.py)
DICT_DIR = Path(__file__).resolve().parent.parent / "dictionaries"

LEVELS = ("low", "medium", "high")
DEFAULT_LEVEL = "low"

# Trần số marker MỖI CHƯƠNG theo mức (None = không giới hạn)
_CAPS: dict[str, int | None] = {"low": 15, "medium": 40, "high": None}

# Ngưỡng "độ khác nhau" tối thiểu để một mục thành marker ([_distinctness]) —
# thấp nhất ở mức cao nhất: low 0.75, medium 0.5, high 0 (chỉ gộp trùng).
_DISTINCT_MIN: dict[str, float] = {"low": 0.75, "medium": 0.5, "high": 0.0}

# Từ đệm / phó từ mức độ — hai nghĩa chỉ khác nhau ở âm tiết này thì vẫn là
# đồng nghĩa (vd "rất xuất sắc" | "khá xuất sắc" → gộp).
PARTICLES = frozenset({
    "khá", "rất", "thật", "hơi", "quá", "cực", "nhất", "hẳn", "thực",
    "แสน", "rõ", "dường", "như", "chắc", "lại", "cũng", "mới", "vừa",
})

# File danh sách người dùng (mỗi dòng một khóa chữ Trung; # = chú thích)
NO_MARK_FILE = "no_mark.txt"
AMBIGUOUS_FILE = "ambiguous.txt"
SYNONYMS_FILE = "synonyms.txt"
# Danh sách ĐÓNG GÓI kèm repo (viết tay, không sinh bằng AI):
# người dùng wins khi mâu thuẫn — xem [reload_lists].
AMBIGUOUS_SEED_FILE = "ambiguous.seed.txt"
SYNONYMS_SEED_FILE = "synonyms.seed.txt"

_WS_RE = re.compile(r"\s+")
# Dấu câu bọc hai đầu nghĩa (loại khi chuẩn hóa để so sánh)
_EDGE_PUNCT = ".,;:!?…“”\"'‘’()[]{}、。，！？·-–—～~"


def normalize_level(value: str | None) -> str:
    """Đưa `markLevel` về chuẩn — `None`/rỗng → mặc định; sai giá trị → ValueError."""
    if value is None or not str(value).strip():
        return default_level()
    level = str(value).strip().lower()
    if level not in LEVELS:
        raise ValueError("markLevel phải là 'low', 'medium' hoặc 'high'")
    return level


def default_level() -> str:
    """Mức gợi ý mặc định lấy từ `MARK_LEVEL` trong `.env` (mặc định `low`)."""
    raw = (os.getenv("MARK_LEVEL") or DEFAULT_LEVEL).strip().lower()
    return raw if raw in LEVELS else DEFAULT_LEVEL


def cap_for(level: str) -> int | None:
    """Trần số marker mỗi chương theo mức (`None` = không giới hạn)."""
    return _CAPS.get(level, _CAPS[DEFAULT_LEVEL])


# ---------------------------------------------------------------------------
# Danh sách file (no_mark / ambiguous / synonyms)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MarkLists:
    """Ba danh sách nạp từ file (đã gộp seed đóng gói) — bất biến, thay bằng
    object mới khi reload."""

    no_mark: frozenset[str]
    ambiguous: frozenset[str]
    synonyms: frozenset[str]
    mtimes: tuple[float, ...]


def _detect_encoding(path: Path) -> str:
    """Tự nhận encoding theo BOM — khớp `vietphrase._detect_encoding`."""
    with open(path, "rb") as fh:
        start = fh.read(4)
    if start[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return "utf-16"
    if start[:3] == b"\xef\xbb\xbf":
        return "utf-8-sig"
    return "utf-8"


def _read_keys(path: Path) -> set[str]:
    """Đọc một file danh sách → tập khóa (bỏ trống + dòng `#` chú thích)."""
    if not path.exists():
        return set()
    with open(path, encoding=_detect_encoding(path)) as fh:
        keys: set[str] = set()
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                keys.add(line)
        return keys


def _paths() -> tuple[Path, Path, Path, Path, Path]:
    return (
        DICT_DIR / NO_MARK_FILE,
        DICT_DIR / AMBIGUOUS_FILE,
        DICT_DIR / SYNONYMS_FILE,
        DICT_DIR / AMBIGUOUS_SEED_FILE,
        DICT_DIR / SYNONYMS_SEED_FILE,
    )


def _mtimes() -> tuple[float, ...]:
    return tuple(
        p.stat().st_mtime if p.exists() else 0.0 for p in _paths()
    )


_lists: MarkLists | None = None

# Cache kết quả [evaluate] theo khóa — dịch chương 3000-5000 chữ chỉ tính 1 lần
# cho mỗi (khóa, loại, danh sách nghĩa, mức). Xoá khi nạp lại danh sách.
_EVAL_CACHE_MAX = 50_000
_eval_cache: dict[tuple, tuple[bool, list[str]]] = {}


def reload_lists() -> MarkLists:
    """Nạp lại danh sách từ đĩa (gọi khi sửa file / POST reload).

    Thứ tự ưu tiên: file người dùng (`ambiguous.txt` / `synonyms.txt` /
    `no_mark.txt`) thắng khi mâu thuẫn với seed đóng gói (`*.seed.txt`) —
    vd khoá người dùng đặt trong `synonyms.txt` không nằm trong `ambiguous`
    dù seed có. File thiếu → coi như rỗng, không lỗi.
    """
    global _lists, _eval_cache
    no_mark, amb_user, syn_user, amb_seed, syn_seed = (
        _read_keys(p) for p in _paths()
    )
    ambiguous = amb_user | (amb_seed - syn_user - no_mark)
    synonyms = syn_user | (syn_seed - amb_user - no_mark)
    _lists = MarkLists(
        no_mark=frozenset(no_mark),
        ambiguous=frozenset(ambiguous),
        synonyms=frozenset(synonyms),
        mtimes=_mtimes(),
    )
    _eval_cache = {}  # danh sách đổi → cache phân loại cũ hết hạn
    return _lists


def get_lists() -> MarkLists:
    """Danh sách hiện tại — tự nạp lại nếu file trên đĩa đã đổi (không cần restart)."""
    if _lists is None:
        return reload_lists()
    if _mtimes() != _lists.mtimes:
        return reload_lists()
    return _lists


# ---------------------------------------------------------------------------
# Bước 1-2: chuẩn hóa + gộp trùng / gộp nghĩa gần giống
# ---------------------------------------------------------------------------


def normalize_meaning(value: str) -> str:
    """Hạ chữ thường, NFC, bỏ dấu cách thừa và dấu câu băm hai đầu."""
    text = unicodedata.normalize("NFC", str(value)).lower()
    text = _WS_RE.sub(" ", text).strip()
    return text.strip(_EDGE_PUNCT).strip()


def _syllables(norm: str) -> list[str]:
    """Âm tiết ≈ các cụm ký tự không khoảng trắng (tiếng Việt tách bằng dấu cách)."""
    return [s for s in norm.split(" ") if s]


def _strip_particles(norm: str) -> str:
    """Bỏ từ đệm/phó từ ([PARTICLES]) — "rất tốt" → "tốt", "khá tốt" → "tốt"."""
    return " ".join(s for s in _syllables(norm) if s not in PARTICLES)


def _similar(a: str, b: str) -> bool:
    """Hai nghĩa có coi là "gần giống" không: chứa nhau, ≥50% âm tiết trùng,
    hoặc bỏ từ đệm đi còn trùng nhau."""
    if a == b:
        return True
    if a in b or b in a:
        return True
    sa, sb = _syllables(a), _syllables(b)
    if not sa or not sb:
        return False
    shared = len(set(sa) & set(sb))
    if shared / min(len(set(sa)), len(set(sb))) >= 0.5:
        return True
    pa, pb = _strip_particles(a), _strip_particles(b)
    return bool(pa and pb and pa == pb)


def merge_similar(meanings: list[str]) -> list[str]:
    """Bước 1 (chống trùng) + bước 2 (gộp nghĩa gần giống) — giữ thứ tự ban đầu.

    Mỗi nhóm gộp lấy đại diện:

    - Nhóm chứa nghĩa ĐẦU TIÊN (nghĩa mặc định của từ điển) giữ chính nghĩa đó —
      để marker luôn mở bằng đúng nghĩa đầu, `resolve(marker)` khớp tuyệt đối
      với bản dịch không marker (người đọc thấy một nghĩa).
    - Các nhóm còn lại: nghĩa **ngắn hơn** (hòa thì giữ xuất hiện trước).
    """
    reps: list[str] = []
    norms: list[str] = []
    for meaning in meanings:
        value = str(meaning).strip()
        if not value:
            continue
        norm = normalize_meaning(value)
        if not norm:
            continue
        if norm in norms:  # bước 1: trùng sau chuẩn hóa
            continue
        reps.append(value)
        norms.append(norm)

    n = len(reps)
    parent = list(range(n))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i in range(n):
        for j in range(i + 1, n):
            if _similar(norms[i], norms[j]):
                ri, rj = find(i), find(j)
                if ri != rj:
                    parent[max(ri, rj)] = min(ri, rj)

    first_root = find(0) if n else -1
    best: dict[int, int] = {}
    order: list[int] = []
    for i in range(n):
        root = find(i)
        if root not in best:
            best[root] = i
            order.append(root)
        elif root != first_root:
            # Đại diện nhóm khác: nghĩa ngắn hơn (độ dài chuẩn hóa), hòa thì giữ trước
            cur = best[root]
            if len(norms[i]) < len(norms[cur]):
                best[root] = i
    return [reps[best[root]] for root in order]


# ---------------------------------------------------------------------------
# Bước 2b: Hán-Việt ↔ thuần Việt (vd có|hữu, ba|tam → đồng nghĩa)
# ---------------------------------------------------------------------------

# Âm Hán-Việt nạp từ `hanviet.txt` (cạnh các file từ điển khác — lazy, 1 lần)
_hanviet: dict[str, str] = {}


def _load_hanviet() -> None:
    """Nạp `hanviet.txt` (`字=âm1/âm2`) — chỉ cần âm ĐẦU TIÊN mỗi chữ."""
    global _hanviet
    if _hanviet:
        return
    path = DICT_DIR / "hanviet.txt"
    mapping: dict[str, str] = {}
    if path.exists():
        with open(path, encoding=_detect_encoding(path)) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                char, readings = line.split("=", 1)
                first = readings.split("/")[0].strip()
                if len(char.strip()) == 1 and first:
                    mapping[char.strip()] = first
    _hanviet = mapping


def _is_hanviet_native_pair(key: str, norms: list[str]) -> bool:
    """Một nghĩa đúng bằng âm Hán-Việt CỦA KHÓA + nghĩa khác thuần Việt → True.

    Vd `有` = `có|hữu`: "hữu" là âm Hán-Việt của 有, "co" không dùng âm tiết
    nào trong bộ âm của khoá → "thuần Việt tương ứng" → đồng nghĩa, không
    đánh dấu. Tương tự `三` = `ba|tam`, `夫妻` = `vợ chồng|phu thê`.

    Bảo thủ: chỉ đúng khi (a) MỌI chữ của khoá có âm Hán-Việt, (b) CHUỖI âm
    đọc đủ của khoá trùng một nghĩa, (c) nghĩa còn lại không dùng âm tiết nào
    là âm Hán-Việt CỦA CÁC CHỮ TRONG KHÓA (so âm tiết riêng khoá, không so
    toàn bộ ngôn ngữ → "có" không đụng "hữu" của 有).
    """
    _load_hanviet()
    if not _hanviet or len(norms) < 2:
        return False
    readings: list[str] = []
    for ch in key:
        reading = _hanviet.get(ch, "")
        if not reading:
            return False  # chữ không có âm Hán-Việt → không kết luận
        readings.append(reading)
    key_readings = frozenset(readings)
    hv_norm = normalize_meaning(" ".join(readings))
    if not hv_norm or hv_norm not in norms:
        return False
    return any(
        n != hv_norm
        and all(s not in key_readings for s in _syllables(n))
        for n in norms
    )


# ---------------------------------------------------------------------------
# Bước 3-6: quyết định có đánh dấu không
# ---------------------------------------------------------------------------


def evaluate(
    key: str,
    kind: str,
    meanings: list[str],
    level: str,
    lists: MarkLists,
    hinted: frozenset[str] | set[str] = frozenset(),
) -> tuple[bool, list[str]]:
    """Đánh giá một mục từ điển — trả `(được đánh dấu?, nghĩa sau khi gộp)`.

    [key] khóa chữ Trung; [kind] "phrase" (vietphrase) | "name" (names.txt);
    [hinted] các khóa có luật cũ `{a:b}` viết tay trong vietphrase.txt (được
    đối xử như nằm trong `ambiguous.txt` — luật cũ phải sống tiếp).

    Kết quả được cache theo (khóa, loại, danh sách nghĩa, mức, danh sách file)
    — [reload_lists] xoá cache; quá 50k mục thì tự xoá để không phình RAM.
    """
    cache_key = (
        key, kind, tuple(meanings), level,
        lists.no_mark, lists.ambiguous, lists.synonyms,
        frozenset(hinted),
    )
    hit = _eval_cache.get(cache_key)
    if hit is not None:
        return hit
    result = _evaluate_core(key, kind, meanings, level, lists, hinted)
    if len(_eval_cache) >= _EVAL_CACHE_MAX:
        _eval_cache.clear()
    _eval_cache[cache_key] = result
    return result


def _evaluate_core(
    key: str,
    kind: str,
    meanings: list[str],
    level: str,
    lists: MarkLists,
    hinted: frozenset[str] | set[str] = frozenset(),
) -> tuple[bool, list[str]]:
    merged = merge_similar(meanings)
    if len(merged) < 2:  # bước 1-2: sau gộp còn 1 nghĩa → không marker
        return False, merged

    whitelisted = key in lists.ambiguous or key in hinted
    if whitelisted:  # bước 6a: danh sách trắng — chỉ cần qua bước 1-2
        return True, merged
    if level == "high":  # mức Nhiều: gần như hành vi hiện tại, chỉ gộp trùng
        return True, merged

    # --- Bước 2b: Hán-Việt ↔ thuần Việt → đồng nghĩa (mọi mức thấp hơn high)
    if _is_hanviet_native_pair(key, [normalize_meaning(m) for m in merged]):
        return False, merged

    if level == "low" and lists.ambiguous:
        # Mức Ít có danh sách trắng → chỉ đánh dấu khóa được duyệt
        return False, merged
    # --- Mức Vừa (và mức Ít khi ambiguous trống): bộ lọc 1-5 + loại synonyms
    if key in lists.synonyms:  # bước 6b
        return False, merged
    if key in lists.no_mark:  # bước 3
        return False, merged
    if len(key) == 1:  # bước 4: khóa một chữ Hán
        return False, merged
    if kind == "name":  # bước 5: tên riêng (names.txt)
        return False, merged
    # --- Bước 6b: ngưỡng độ khác nhau theo mức (low cao nhất, high thấp nhất)
    if _distinctness(merged) < _DISTINCT_MIN.get(level, 0.5):
        return False, merged
    # --- Luật tần suất ở mức Ít: mọi nghĩa đều 1 âm tiết (trợ từ/lượng từ) →
    #     khóa rất phổ biến, hầu như toàn từ đệm → ưu tiên không đánh dấu.
    if level == "low" and all(
        len(_syllables(normalize_meaning(m))) <= 1 for m in merged
    ):
        return False, merged
    return True, merged


# ---------------------------------------------------------------------------
# Bước 7: chấm điểm để giữ N marker cao nhất mỗi chương
# ---------------------------------------------------------------------------


def _distinctness(merged: list[str]) -> float:
    """Độ khác nhau giữa các nghĩa: 1 − (overlap âm tiết lớn nhất giữa 2 nghĩa)."""
    norms = [normalize_meaning(m) for m in merged]
    if len(norms) < 2:
        return 0.0
    worst = 0.0
    for i in range(len(norms)):
        for j in range(i + 1, len(norms)):
            sa, sb = _syllables(norms[i]), _syllables(norms[j])
            if not sa or not sb:
                continue
            overlap = len(set(sa) & set(sb)) / min(len(set(sa)), len(set(sb)))
            worst = max(worst, overlap)
    return 1.0 - worst


def score_candidate(key: str, merged: list[str], whitelisted: bool = False) -> float:
    """Điểm một ứng viên marker: khác nghĩa cao, khóa dài (nhiều chữ), đã duyệt."""
    distinct = _distinctness(merged)
    key_bonus = min(len(key), 10) / 10.0 * 0.3
    return 2.0 * distinct + key_bonus + (1.0 if whitelisted else 0.0)
