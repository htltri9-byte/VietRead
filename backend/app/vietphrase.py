"""Dịch Trung → Việt OFFLINE bằng từ điển (longest-match) — chế độ `TRANSLATE_MODE=dict`.

Nguồn dữ liệu nằm trong `backend/dictionaries/` (không hardcode trong code):

- `names.txt`     — tên riêng do người dùng thêm, **ưu tiên cao nhất** (`中文=Việt Nam`);
- `surnames.txt`  — họ Trung Quốc (mỗi dòng `字=âm`, kèm sẵn 400 họ Bách Tánh)
- `vietphrase.txt` — cụm từ → nghĩa tiếng Việt (`中文=nghĩa1/nghĩa2`, do người dùng cung cấp);
- `hanviet.txt`   — âm Hán-Việt từng chữ, sinh từ Unihan `kVietnamese` (`字=âm1/âm2`).

Thuật toán: tại mỗi vị trí trong chuỗi, thử cụm **dài nhất** có trong từ điển
(giới hạn [MAX_KEY] ký tự, thử từ dài xuống ngắn); thứ tự tra **Names →
Luật Nhân (mẫu `中文{0}中文=mẫu Việt {0}` — ô {0} được điền bằng đoạn văn bản
được dịch bằng chính bộ máy token) → VietPhrase → Họ (`surnames.txt`, ký tự
đơn lẻ) → Hán-Việt từng chữ**; ký tự
không có trong từ điển nào thì giữ nguyên. Từ điển được nạp **một lần** vào
dict bộ nhớ (cache pickle để khởi động nhanh), không đọc file lại mỗi lần dịch.

Văn bản đầu ra được hậu xử lý: ngăn cách token bằng dấu cách (không thêm dấu
cách thừa quanh dấu câu), đổi dấu câu full-width sang Việt, viết hoa chữ đầu
câu/đoạn và tên riêng, giữ nguyên xuống dòng/đoạn của bản gốc.
"""

from __future__ import annotations

import logging
import pickle
import re
import time
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

from . import alternatives, marking

logger = logging.getLogger("vietread.dictionary")

# Thư mục từ điển — backend/dictionaries/ (ngoài gói app/)
DICT_DIR = Path(__file__).resolve().parent.parent / "dictionaries"

# Cụm dài nhất khi so khớp (tên riêng/vietphrase đều giới hạn chừng này)
MAX_KEY = 12

# Trần độ dài đoạn chèn vào {0} của Luật Nhân (chống khớp lan man)
MAX_CAPTURE = 12

# Mẫu Luật Nhân lồng nhau tối đa chừng này lớp ( {0} chứa {0} )
_MAX_DEPTH = 3

# Cache pickle tự sinh — nhanh hơn parse ~10k dòng ở mỗi lần khởi động
_CACHE_FILE = DICT_DIR / "_cache.pkl"

# --- Từ điển nạp vào bộ nhớ (reset khi restart server) ------------------------
_names: dict[str, str] = {}
_vietphrase: dict[str, str] = {}
_hanviet: dict[str, str] = {}
# Các nghĩa KHÁC của names.txt/vietphrase.txt (chỉ khoá có >= 2 nghĩa) — dùng
# khi convert(mark_alternatives=True) để xuất marker {nghĩa1|nghĩa2}.
_names_alts: dict[str, list[str]] = {}
_vp_alts: dict[str, list[str]] = {}
# Khóa có "luật cũ" {nghĩa1:nghĩa2} viết tay trong vietphrase.txt (vd `为={vì:là}`)
# — được đối xử như nằm trong ambiguous.txt khi lọc marker (xem marking.evaluate).
_hinted_keys: set[str] = set()
# Họ Trung Quốc — ký tự đơn lẻ, chỉ tra khi không trúng cụm nào ở các tầng trên
_surnames: dict[str, str] = {}
# Luật Nhân: prefix (text trước {0}) → [(các đoạn của mẫu, mẫu Việt)]
_luatnhan: dict[str, list[tuple[tuple[str, ...], str]]] = {}
_loaded = False

# Dấu câu full-width → dạng Việt/ASCII (…… xử lý riêng trước, ô 2 ký tự)
_PUNCT_MAP = str.maketrans(
    {
        "，": ",", "、": ",", "。": ".", "？": "?", "！": "!", "：": ":", "；": ";",
        "“": '"', "”": '"', "「": '"', "」": '"', "『": '"', "』": '"',
        "（": "(", "）": ")", "　": " ",
    }
)

# Nháy/ngoặc MỞ và ĐÓNG phân biệt được bằng ký tự GỐC (trước khi map sang ")
_OPENERS = '“「『（([【'
_CLOSERS = '”」』）)]】'

# Chữ Trung (kể cả mở rộng) — chỉ vị trí chữ Hán mới tra từ điển
def _is_han(ch: str) -> bool:
    cp = ord(ch)
    return 0x3400 <= cp <= 0x9FFF or 0xF900 <= cp <= 0xFAFF or 0x20000 <= cp <= 0x3134F


def _capitalize_first(word: str) -> str:
    """Viết hoa chữ cái đầu tiên (hỗ trợ dấu tiếng Việt).

    Với marker `{nghĩa1|…}` → viết hoa **nghĩa đầu** để bản dịch sau resolve
    vẫn đúng chữ hoa đầu câu — `resolve(convert(x))` khớp tuyệt đối với
    `convert(x)` không marker.
    """
    for idx, ch in enumerate(word):
        if ch in "{}|":
            if ch == "}":
                return word  # hết marker mà chưa thấy chữ cái Latin
            continue  # ranh giới segment marker / khóa → tiếp tục tìm nghĩa
        if ch.isalpha() and not _is_han(ch):
            return word[:idx] + ch.upper() + word[idx + 1 :]
    return word


def _capitalize_words(value: str) -> str:
    """Viết hoa từng từ — dùng cho tên riêng từ names.txt."""
    return " ".join(_capitalize_first(w) if w else w for w in value.split(" "))


def _detect_encoding(path: Path) -> str:
    """Tự nhận encoding theo BOM: hỗ trợ UTF-16 LE/BE và UTF-8 (kèm BOM hoặc không)."""
    with open(path, "rb") as fh:
        start = fh.read(4)
    if start[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return "utf-16"  # codec tự chọn LE/BE theo BOM
    if start[:3] == b"\xef\xbb\xbf":
        return "utf-8-sig"
    return "utf-8"


# "Luật cũ" viết tay trong giá trị từ điển: marker nhiều NGHĨA kiểu {a:b}
# (6 dòng trong vietphrase.txt, vd `为={vì:là}/vì/làm/vi/là`) — chỉ dạng này
# được ghi vào hinted keys; marker một nghĩa {card siêu nhân} không tính.
_OLD_HINT_RE = re.compile(r"\{[^{}]*[:|][^{}]*\}")


def _meanings_of(value: str) -> list[str]:
    """Một giá trị từ điển `nghĩa1/nghĩa2;nghĩa3` → danh sách nghĩa sạch.

    Gỡ marker cũ `{a:b}` còn nằm trong nghĩa (vd `định {vì:là}` → `định vì`,
    `định là`), bỏ nghĩa trống/trùng, tối đa [alternatives.MAX_ALTERNATIVES].
    """
    out: list[str] = []
    for part in re.split(r"[/;]", value):
        for expanded in alternatives.expand(part.strip()):
            if expanded and expanded not in out:
                out.append(expanded)
    return out[: alternatives.MAX_ALTERNATIVES]


def _parse_dict_alts(
    path: Path, hints: set[str] | None = None
) -> dict[str, list[str]]:
    """Đọc file từ điển `khai=nghĩa1/nghĩa2` → **mọi nghĩa** của mỗi khoá.

    Chấp nhận UTF-8 hoặc UTF-16 (theo BOM). Dòng "nhiều từ" kiểu
    `太一,正一=thái nhất,chính nhất` (song song, cụm ngắn) vẫn được tách
    thành từng cặp như [_parse_dict_file] trước đây.

    [hints] (tuỳ chọn) — nhận tập khoá chứa "luật cũ" `{a:b}` viết tay trong
    giá trị (vd `为={vì:là}`): những khoá này giữ vai trò danh sách trắng
    ambiguous cho bộ lọc marker (xem [marking]).
    """
    result: dict[str, list[str]] = {}
    if not path.exists():
        return result
    with open(path, encoding=_detect_encoding(path)) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = unicodedata.normalize("NFC", key.strip())
            value = unicodedata.normalize("NFC", value.strip())
            # Dòng nhiều từ: 2 vế đều nhiều đoạn, cụm ngắn (≤4 chữ) → tách song song
            if "," in key and value:
                keys = [k.strip() for k in key.split(",")]
                vals = [v.strip() for v in value.split(",")]
                firsts = [v.split("/")[0].split(";")[0].strip() for v in vals]
                if (
                    len(keys) == len(vals)
                    and all(keys) and all(firsts)
                    and max(len(k) for k in keys) <= 4
                ):
                    for k2, v2 in zip(keys, vals):
                        if hints is not None and _OLD_HINT_RE.search(v2):
                            hints.add(k2)
                        meanings = _meanings_of(v2)
                        if meanings:
                            result[k2] = meanings
                    continue
            if hints is not None and _OLD_HINT_RE.search(value):
                hints.add(key)
            meanings = _meanings_of(value)
            if key and meanings:
                result[key] = meanings
    return result


def _parse_dict_file(path: Path) -> dict[str, str]:
    """Đọc file từ điển `khai=vý/nghĩa2` → dict chỉ giữ **nghĩa đầu tiên**.

    (Nghĩa đầy đủ do [_parse_dict_alts] trả về — dùng cho marker nhiều nghĩa.)
    """
    return {key: value[0] for key, value in _parse_dict_alts(path).items()}


def _parse_luatnhan_file(
    path: Path,
) -> tuple[dict[str, list[tuple[tuple[str, ...], str]]], dict[str, str]]:
    """Đọc `luatnhan.txt` (Luật Nhân) — mẫu `中文{0}中文=mẫu Việt {0}`.

    Trả về (rules, literal): `rules` ánh xạ **prefix** (phần tử đứng trước `{0}`)
    → danh sách (các đoạn của mẫu, mẫu Việt); dòng không có `{0}` thì đưa vào
    `literal` để gộp vào Vietphrase như cụm thường.
    """
    rules: dict[str, list[tuple[tuple[str, ...], str]]] = {}
    literal: dict[str, str] = {}
    if not path.exists():
        return rules, literal
    with open(path, encoding=_detect_encoding(path)) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = unicodedata.normalize("NFC", key.strip())
            value = unicodedata.normalize("NFC", value.strip())
            value = value.replace("……", "...").replace("…", "...").translate(_PUNCT_MAP)
            if "{0}" not in key:
                first = value.split("/")[0].split(";")[0].strip()
                if key and first:
                    literal[key] = first
                continue
            # Mẫu phải có cùng số {0} hai bên; hai đầu mẫu phải có chữ
            parts = tuple(p.strip() for p in key.split("{0}"))
            if (
                key.count("{0}") != value.count("{0}")
                or not parts[0]
                or not parts[-1]
                or any(not p for p in parts[1:-1])
            ):
                continue
            rules.setdefault(parts[0], []).append((parts, value))
    return rules, literal


def _multi_only(alts: dict[str, list[str]]) -> dict[str, list[str]]:
    """Giữ lại khoá có ≥ 2 nghĩa — khoá 1 nghĩa không bao giờ sinh marker."""
    return {k: v for k, v in alts.items() if len(v) >= 2}


def load(force: bool = False) -> None:
    """Nạp toàn bộ từ điển vào bộ nhớ MỘT LẦN (dùng cache pickle nếu còn mới)."""
    global _names, _vietphrase, _hanviet, _luatnhan, _surnames, _loaded
    global _names_alts, _vp_alts, _hinted_keys
    if _loaded and not force:
        return
    _rev_index.clear()  # nạp lại từ điển → index tra ngược nghĩa → khóa hết hạn
    started = time.perf_counter()
    sources = [
        DICT_DIR / "names.txt",
        DICT_DIR / "vietphrase.txt",
        DICT_DIR / "hanviet.txt",
        DICT_DIR / "luatnhan.txt",
        DICT_DIR / "surnames.txt",
    ]

    # --- Thử đọc cache pickle (mới hơn mọi file nguồn thì dùng luôn) ---
    if not force and _CACHE_FILE.exists():
        try:
            newest_src = max((p.stat().st_mtime for p in sources if p.exists()), default=0)
            if _CACHE_FILE.stat().st_mtime >= newest_src:
                with open(_CACHE_FILE, "rb") as fh:
                    data = pickle.load(fh)
                if len(data) != 8:  # cache cũ (trước hinted keys) → nạp lại
                    raise ValueError("cache từ điển bản cũ")
                (
                    _names,
                    _vietphrase,
                    _hanviet,
                    _luatnhan,
                    _surnames,
                    _names_alts,
                    _vp_alts,
                    _hinted_keys,
                ) = data
                _loaded = True
                logger.info(
                    "Từ điển (cache): %d tên riêng, %d vietphrase, %d mẫu Luật Nhân, "
                    "%d họ, %d Hán-Việt (%.2fs)",
                    len(_names), len(_vietphrase), len(_luatnhan), len(_surnames), len(_hanviet),
                    time.perf_counter() - started,
                )
                _warn_missing_vietphrase()
                return
        except Exception:  # cache hỏng → nạp lại từ file
            logger.exception("Không đọc được cache từ điển (%s) — nạp lại từ file", _CACHE_FILE)    # --- Nạp trực tiếp từ các file txt ---
    hints: set[str] = set()
    names_alts = _parse_dict_alts(sources[0])
    vp_alts = _parse_dict_alts(sources[1], hints)
    _names = {k: v[0] for k, v in names_alts.items()}
    _vietphrase = {k: v[0] for k, v in vp_alts.items()}
    _names_alts = _multi_only(names_alts)
    _vp_alts = _multi_only(vp_alts)
    _hinted_keys = hints
    del names_alts, vp_alts
    _hanviet = _parse_dict_file(sources[2])
    _luatnhan, _luatnhan_literal = _parse_luatnhan_file(sources[3])
    _surnames = _parse_dict_file(sources[4])
    _vietphrase.update(_luatnhan_literal)  # dòng Luật Nhân không có {0} → cụm thường
    _loaded = True
    try:
        DICT_DIR.mkdir(parents=True, exist_ok=True)
        with open(_CACHE_FILE, "wb") as fh:
            pickle.dump(
                (
                    _names,
                    _vietphrase,
                    _hanviet,
                    _luatnhan,
                    _surnames,
                    _names_alts,
                    _vp_alts,
                    _hinted_keys,
                ),
                fh,
                protocol=pickle.HIGHEST_PROTOCOL,
            )
    except Exception:
        logger.exception("Không ghi được cache từ điển (%s)", _CACHE_FILE)
    logger.info(
        "Từ điển (file): %d tên riêng, %d vietphrase, %d mẫu Luật Nhân, %d họ, %d Hán-Việt (%.2fs)",
        len(_names), len(_vietphrase), len(_luatnhan), len(_surnames), len(_hanviet),
        time.perf_counter() - started,
    )
    _warn_missing_vietphrase()


def _warn_missing_vietphrase() -> None:
    """Cảnh báo rõ ràng khi thiếu vietphrase.txt (đang dịch chỉ theo âm từng chữ)."""
    if not (DICT_DIR / "vietphrase.txt").exists():
        logger.warning(
            "Thiếu %s — đang dịch CHỈ theo âm Hán-Việt từng chữ (không có nghĩa cụm từ). "
            "Thêm file (định dạng 中文=nghĩa1/nghĩa2) rồi restart để dịch đẹp hơn.",
            DICT_DIR / "vietphrase.txt",
        )


def reload_names() -> int:
    """Nạp lại riêng names.txt (gọi sau POST /dictionary/names) — không cần restart."""
    global _names, _names_alts
    alts = _parse_dict_alts(DICT_DIR / "names.txt")
    _names = {k: v[0] for k, v in alts.items()}
    _names_alts = _multi_only(alts)
    _rev_index.clear()  # từ điển đổi → index tra ngược nghĩa → khóa hết hạn
    logger.info("Đã nạp lại names.txt: %d tên riêng", len(_names))
    return len(_names)


# ---------------------------------------------------------------------------
# Tra ngược: danh sách nghĩa → khóa từ điển (client gửi nghĩa, không gửi khóa)
# ---------------------------------------------------------------------------

# Index `(mức, fingerprint)` → {tuple(đã chuẩn hóa) của marker : [khóa]}.
# Tính 1 lần khi cần (evaluate có cache theo khóa), tự hết hạn khi từ điển
# hoặc 3 file danh sách đổi (fingerprint gồm số mục + mtimes file).
_rev_index: dict[tuple, dict[tuple[str, ...], list[str]]] = {}


def _rev_fingerprint() -> tuple:
    return (
        len(_vietphrase), len(_names), len(_vp_alts), len(_names_alts),
        marking.get_lists().mtimes,
    )


def _build_rev_index(
    level: str, lists: marking.MarkLists, hinted: set[str]
) -> dict[tuple[str, ...], list[str]]:
    """Khóa → tập marker (nghĩa sau lọc) của CHÍNH nó, nhóm theo marker đó.

    Chỉ gộp mục qua được [marking.evaluate] ở mức [level] (đúng bộ lọc/đáng
    mức mà marker trong dữ liệu đã dùng) — trả về dict {marker chuẩn hóa: khóa}.
    """
    index: dict[tuple[str, ...], list[str]] = {}
    sources = ((_vp_alts, "phrase"), (_names_alts, "name"))
    for alts, kind in sources:
        for key, values in alts.items():
            if len(values) < 2:
                continue
            ok, merged = marking.evaluate(key, kind, values, level, lists, hinted)
            if not ok:
                continue
            clean = alternatives.clean_meanings(merged)[: alternatives.MAX_ALTERNATIVES]
            if len(clean) < 2:
                continue
            sig = tuple(marking.normalize_meaning(m) for m in clean)
            bucket = index.setdefault(sig, [])
            if key not in bucket:
                bucket.append(key)
    return index


def meanings_for_key(key: str, level: str | None = None) -> list[str] | None:
    """Nghĩa tiếng Việt (sau lọc theo mức) của MỘT khóa từ điển.

    Dùng cho màn “Quy tắc” hiển thị NGHĨA thay cho khóa chữ Trung của
    UserMarkRule (không lộ chữ Hán cho người dùng). Trả `None` nếu không
    tra được khóa.
    """
    load()
    if not key:
        return None
    lists = marking.get_lists()
    hinted = _hinted_keys
    try:
        lv = marking.normalize_level(level)
    except ValueError:
        lv = marking.default_level()
    for alts, kind in ((_names_alts, "name"), (_vp_alts, "phrase")):
        values = alts.get(key)
        if not values or len(values) < 2:
            continue
        _ok, merged = marking.evaluate(key, kind, values, lv, lists, hinted)
        clean = alternatives.clean_meanings(merged)[: alternatives.MAX_ALTERNATIVES]
        if clean:
            return clean
    # Khóa chỉ có 1 nghĩa (hiếm) → nghĩa đầu tiên của từ điển
    primary = _names.get(key) or _vietphrase.get(key)
    if primary:
        clean = alternatives.clean_meanings(
            alternatives.expand(primary.split("/")[0])
        )
        if clean:
            return clean[: alternatives.MAX_ALTERNATIVES]
    return None


def keys_for_meanings(
    meanings: list[str] | tuple[str, ...], level: str | None = None
) -> list[str]:
    """Tra NGƯỢC khóa từ điển từ danh sách nghĩa của một marker.

    Client (màn Sửa chương) gửi danh sách nghĩa thay vì khóa chữ Trung;
    backend tìm mọi khóa có marker **trùng danh sách nghĩa sau chuẩn hóa**
    (mọi mức — marker trong dữ liệu không ghi mức đã dùng) và trả về để áp
    dụng "luôn dùng" / "không hỏi lại" cho tất cả. Không gọi mạng; index
    cache theo (mức, fingerprint từ điển/danh sách).
    """
    load()
    lists = marking.get_lists()
    hinted = _hinted_keys
    wanted = tuple(
        norm
        for norm in (marking.normalize_meaning(m) for m in meanings or ())
        if norm
    )
    if not wanted:
        return []
    levels = [marking.normalize_level(level)] if level else list(marking.LEVELS)
    fingerprint = _rev_fingerprint()
    found: list[str] = []
    for lv in levels:
        cache_key = (lv, fingerprint)
        index = _rev_index.get(cache_key)
        if index is None:
            index = _build_rev_index(lv, lists, hinted)
            if len(_rev_index) > 12:
                _rev_index.clear()
            _rev_index[cache_key] = index
        for key in index.get(wanted, ()):
            if key not in found:
                found.append(key)
    return found


@dataclass
class MarkContext:
    """Ngữ cảnh marker cho MỘT lần dịch (thường = một chương).

    - [enabled] — `mark_alternatives` (có bật gợi ý nghĩa hay không);
    - [level] — mức gợi ý `low | medium | high` (xem [marking]);
    - [choices] — khóa → nghĩa đã chọn riêng của truyện (`StoryWordChoices`),
      dịch lại sẽ dùng thẳng nghĩa này thay cho marker;
    - [skips] — khóa "Không hỏi lại" của truyện (`StoryIgnoredWords`);
    - [lists] — 3 file danh sách (no_mark/ambiguous/synonyms), nạp 1 lần/chương;
    - [hinted] — khóa có luật cũ `{a:b}` viết tay trong vietphrase.txt.
    """

    enabled: bool = False
    level: str = marking.DEFAULT_LEVEL
    choices: dict[str, str] = field(default_factory=dict)
    skips: set[str] = field(default_factory=set)
    lists: marking.MarkLists | None = None
    hinted: set[str] = field(default_factory=set)


def _make_ctx(
    mark_alternatives: bool,
    mark_level: str | None = None,
    key_choices: dict[str, str] | None = None,
    skip_keys: set[str] | None = None,
) -> MarkContext:
    """Dựng ngữ cảnh marker — level sai giá trị → dùng mức thấp nhất + log.

    [key_choices]/[skip_keys] do từng truyện sở hữu (mặc định rỗng = không đổi
    hành vi so với trước). Danh sách file lấy 1 lần, tự nạp lại khi file đổi.
    """
    if mark_level is None:
        level = marking.default_level()
    else:
        try:
            level = marking.normalize_level(mark_level)
        except ValueError:
            logger.warning("markLevel=%r không hợp lệ — dùng 'low'", mark_level)
            level = marking.DEFAULT_LEVEL
    return MarkContext(
        enabled=mark_alternatives,
        level=level,
        choices=dict(key_choices or {}),
        skips=set(skip_keys or ()),
        lists=marking.get_lists(),
        hinted=set(_hinted_keys),
    )


def _match_luatnhan(
    text: str, i: int, depth: int, ctx: MarkContext | None = None
) -> tuple[int, str] | None:
    """Khớp mẫu Luật Nhân tại vị trí i — prefix dài nhất trước, hậu tố trong cửa sổ.

    Trả `(số ký tự đã tiêu thụ, mẫu Việt đã điền {0})` hoặc None nếu không trúng.
    """
    span = min(MAX_KEY, len(text) - i)
    for length in range(span, 0, -1):
        candidates = _luatnhan.get(text[i : i + length])
        if not candidates:
            continue
        for parts, template in candidates:
            pos = i + length
            fills: list[str] = []
            ok = True
            for part in parts[1:]:
                # Hậu tố phải nằm trong cửa sổ trần [MAX_CAPTURE] — không lấy xa
                window = min(len(text), pos + MAX_CAPTURE + len(part) + 1)
                found = text.find(part, pos, window)
                middle = text[pos:found] if found >= 0 else ""
                if (
                    found < 0
                    or not middle
                    or "\n" in middle
                    or any(c in "。！？…!?" for c in middle)
                ):
                    ok = False
                    break
                fills.append(middle)
                pos = found + len(part)
            if not ok:
                continue
            value = template
            for fill in fills:
                value = value.replace("{0}", _fill_middle(fill, depth, ctx), 1)
            return pos - i, value
    return None


def _fill_middle(text: str, depth: int, ctx: MarkContext | None = None) -> str:
    """Dịch đoạn chèn vào {0} bằng chính bộ máy token (mẫu lồng tối đa 3 lớp).

    Mẫu lồng dùng chung ngữ cảnh [ctx] (mức gợi ý, nghĩa đã chọn) nhưng marker
    bên trong tính riêng — trần N marker/chương do [_plan_multi] tính cho phần
    token ngoài cùng (marker lồng hiếm gặp, đã lọc đủ bước 1-6).
    """
    return _render(
        _tokenize(text, depth + 1, ctx),
        capitalize_next=False,
        ctx=ctx,
    )


# Một token: (kind, nghĩa, nghĩa-khác|None, khóa|None) — kind: name/phrase/word/raw
_Piece = tuple[str, str, list[str] | None, str | None]


def _tokenize(
    text: str, depth: int = 0, ctx: MarkContext | None = None
) -> list[_Piece]:
    """Tách chuỗi Trung thành token (kind, nghĩa, nghĩa-khác, khóa).

    `nghĩa-khác` là các nghĩa còn lại của mục names/vietphrase (None nếu không
    có); `khóa` là chính cụm Trung đã khớp — [_plan_multi] dùng khóa để lọc
    marker (no_mark/ambiguous/synonyms) và [_render] ghép `{nghĩa1|nghĩa2}`.
    """
    pieces: list[_Piece] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if not _is_han(ch):
            pieces.append(("raw", ch, None, None))
            i += 1
            continue
        span = min(MAX_KEY, n - i)
        seg: str | None = None
        kind = ""
        alts: list[str] | None = None
        key: str | None = None
        # 1) Names — cụm dài nhất trước, ưu tiên trên cùng
        for length in range(span, 0, -1):
            part = text[i : i + length]
            if part in _names:
                seg, kind = _names[part], "name"
                alts = _names_alts.get(part)
                key = part
                i += length
                break
        # 2) Luật Nhân — mẫu có ô {0}, prefix dài nhất trước (nội suy tối đa 3 lớp)
        if seg is None and depth < _MAX_DEPTH:
            matched = _match_luatnhan(text, i, depth, ctx)
            if matched:
                consumed, seg = matched
                kind = "phrase"
                i += consumed
        # 3) VietPhrase — cụm dài nhất trước
        if seg is None:
            for length in range(span, 0, -1):
                part = text[i : i + length]
                if part in _vietphrase:
                    seg, kind = _vietphrase[part], "phrase"
                    alts = _vp_alts.get(part)
                    key = part
                    i += length
                    break
        # 4) Họ (surnames.txt) — ký tự đơn lẻ, sau cụm để không ghi đè nghĩa phổ thông
        if seg is None:
            surname = _surnames.get(ch)
            if surname:
                seg, kind = surname, "name"
                i += 1
        # 5) Hán-Việt từng chữ; không có thì giữ nguyên ký tự gốc
        if seg is None:
            hanviet = _hanviet.get(ch)
            seg, kind = (hanviet, "word") if hanviet else (ch, "raw")
            i += 1
        pieces.append((kind, seg, alts, key))
    return pieces


def _normalize(text: str) -> str:
    """Chuẩn hoá văn bản đầu vào (NFC, xuống dòng Unix, dấu … → ...)."""
    text = unicodedata.normalize("NFC", text).replace("\r\n", "\n").replace("\r", "\n")
    return text.replace("……", "...").replace("…", "...")


def convert(
    text: str,
    mark_alternatives: bool = False,
    mark_level: str | None = None,
    key_choices: dict[str, str] | None = None,
    skip_keys: set[str] | None = None,
) -> str:
    """Dịch Trung → Việt bằng từ điển (longest-match). Không gọi mạng.

    `mark_alternatives=True` — mục names/vietphrase có ≥ 2 nghĩa ĐƯỢC CHỌN qua
    bộ lọc [marking] mới xuất marker `{nghĩa1|nghĩa2}` (bản thô để chủ
    truyện chọn nghĩa); mặc định False chỉ lấy nghĩa đầu như cũ. Dịch online
    không bao giờ tạo marker.

    - `mark_level` — `low | medium | high` (mặc định từ `MARK_LEVEL` trong
      `.env`, thiếu → `low`); sai giá trị → dùng `low` + log cảnh báo.
    - `key_choices` / `skip_keys` — nghĩa đã chọn / khóa "không hỏi lại"
      RIÊNG CỦA TRUYỆN (bảng StoryWordChoices / StoryIgnoredWords).
    """
    load()
    if not text or not text.strip():
        return ""
    ctx = _make_ctx(mark_alternatives, mark_level, key_choices, skip_keys)
    # --- Tách token rồi hậu xử lý: ngăn cách dấu cách, dấu câu Việt, viết hoa ---
    return _render(_tokenize(_normalize(text), ctx=ctx), ctx=ctx)


def convert_lines(
    texts: list[str],
    mark_alternatives: bool = False,
    mark_level: str | None = None,
    key_choices: dict[str, str] | None = None,
    skip_keys: set[str] | None = None,
    on_progress=None,
) -> list[str]:
    """Dịch NHIỀU dòng (một chương) — trần marker tính TỔNG cho cả chương.

    [_translate_dict] gọi hàm này thay vì `convert` từng dòng để mức `low`
    (≤ 15) / `medium` (≤ 40) là trần cả chương chứ không phải mỗi dòng.
    `on_progress(done, total)` được gọi sau mỗi dòng tokenize (phần nặng nhất)
    để job import vẫn báo tiến độ.
    """
    load()
    ctx = _make_ctx(mark_alternatives, mark_level, key_choices, skip_keys)
    tokenized: list[list[_Piece]] = []
    total = len(texts)
    for done, line in enumerate(texts, start=1):
        tokenized.append(_tokenize(_normalize(line), ctx=ctx))
        if on_progress is not None:
            try:
                on_progress(done, total)
            except Exception:
                logger.exception("Lỗi callback tiến độ dịch từ điển (bỏ qua)")
    plans = _plan_multi(tokenized, ctx)
    return [
        _render(pieces, ctx=ctx, override=plan)
        for pieces, plan in zip(tokenized, plans)
    ]


def _plan_multi(chunks: list[list[_Piece]], ctx: MarkContext | None) -> list[dict[int, str]]:
    """Quyết định mỗi token xuất gì: marker (đã lọc + chấm điểm), nghĩa đã
    chọn, hoặc nghĩa đầu (không có entry).

    - Bước 1-6 lọc theo từng khóa ([marking.evaluate]);
    - Bước 7: chấm điểm rồi chỉ giữ N cao nhất **trong cả mảng** (một chương),
      N theo mức (low 15 / medium 40 / high không giới hạn); marker đã lồng
      trong mẫu Luật Nhân (nằm sẵn trong giá trị token) trừ vào ngân sách đó.
    - `choices` (nghĩa đã chọn theo truyện) luôn được dùng, kể cả khi không
      bật marker — dịch lại chương khác của cùng truyện tự dùng nghĩa đó.
    """
    plans: list[dict[int, str]] = [dict() for _ in chunks]
    if ctx is None or (not ctx.enabled and not ctx.choices):
        return plans
    lists = ctx.lists if ctx.lists is not None else marking.get_lists()
    candidates: list[tuple[float, int, int, list[str], str | None]] = []
    for ci, pieces in enumerate(chunks):
        for pi, (_kind, _value, alts, key) in enumerate(pieces):
            if ctx.choices and key and key in ctx.choices:
                plans[ci][pi] = ctx.choices[key]
                continue
            if not ctx.enabled or not alts or len(alts) < 2:
                continue
            if ctx.skips and key in ctx.skips:
                continue
            ok, merged = marking.evaluate(
                key or "", _kind, alts, ctx.level, lists, ctx.hinted
            )
            if not ok:
                continue
            whitelisted = (key in lists.ambiguous) or (key in ctx.hinted)
            candidates.append(
                (marking.score_candidate(key or "", merged, whitelisted), ci, pi, merged, key)
            )
    cap = marking.cap_for(ctx.level)
    if cap is not None:
        embedded = 0
        for pieces in chunks:
            for _kind, value, alts, _key in pieces:
                if alts is None and "{" in value:
                    embedded += alternatives.count(value)
        budget = max(0, cap - embedded)
        candidates.sort(key=lambda c: (-c[0], c[1], c[2]))
        candidates = candidates[:budget]
    for _score, ci, pi, merged, _key in candidates:
        marked = alternatives.build(merged)  # marker chỉ chứa nghĩa Việt, không kèm khóa
        if marked:
            plans[ci][pi] = marked
    return plans


def _render(
    pieces: list[_Piece],
    capitalize_next: bool = True,
    ctx: MarkContext | None = None,
    override: dict[int, str] | None = None,
) -> str:
    """Ghép token thành văn bản: đúng 1 dấu cách giữa các token, dấu câu Việt,
    viết hoa chữ đầu câu/đoạn (trừ khi đang điền giữa chừng một mẫu {0}).

    [override] — giá trị đã quyết sẵn cho từng token (marker `{nghĩa1|nghĩa2}` hoặc
    nghĩa đã chọn) do [_plan_multi] trả về; thiếu override thì tự tính (token
    lồng trong mẫu Luật Nhân). Không có [ctx] → giữ nguyên nghĩa đầu như cũ.
    """
    if override is None and ctx is not None:
        override = _plan_multi([pieces], ctx)[0]
    out: list[str] = []
    open_pending = False  # vừa dán ngoặc/nháy MỞ → token kế tiếp không cách
    for pi, (kind, value, _alts, _key) in enumerate(pieces):
        if override and pi in override:
            value = override[pi]
        if kind == "raw":
            if value in "\n":
                out.append("\n")
                capitalize_next = True
                open_pending = False
                continue
            if value in _OPENERS:  # ngoặc mở: thêm 1 dấu cách trước (trừ khi đã có)
                mapped = value.translate(_PUNCT_MAP)
                if out and out[-1] and out[-1][-1] not in " \n\t((“":
                    out.append(" ")
                out.append(mapped)
                open_pending = True
                continue
            mapped = value.translate(_PUNCT_MAP)
            if mapped in ".!?":  # hết câu → chữ cái đầu câu sau đó viết hoa
                capitalize_next = True
            if mapped in _CLOSERS.translate(_PUNCT_MAP) or mapped in ",.;:!?%":
                if out and out[-1].strip() == "":
                    out.pop()  # không để dấu cách thừa trước dấu câu đóng
            open_pending = False
            out.append(mapped)
            continue
        # Token tiếng Việt (name/phrase/word): ngăn cách bằng đúng 1 dấu cách
        if out and not open_pending and out[-1] and out[-1][-1] not in " \n\t":
            out.append(" ")
        open_pending = False
        token = _capitalize_words(value) if kind == "name" else value
        if capitalize_next:
            token = _capitalize_first(token)
            capitalize_next = False
        out.append(token)
    return "".join(out)
