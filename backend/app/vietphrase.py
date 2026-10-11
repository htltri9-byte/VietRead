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
import time
import unicodedata
from pathlib import Path

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
    """Viết hoa chữ cái đầu tiên (hỗ trợ dấu tiếng Việt)."""
    for idx, ch in enumerate(word):
        if ch.isalpha():
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


def _parse_dict_file(path: Path) -> dict[str, str]:
    """Đọc file từ điển `khai=vý/nghĩa2` → dict chỉ giữ **nghĩa đầu tiên**.

    Chấp nhận UTF-8 hoặc UTF-16 (theo BOM). Dòng "nhiều từ" kiểu
    `太一,正一=thái nhất,chính nhất` (song song, cụm ngắn) được tách
    thành từng cặp; dòng có dấu phẩy trong cụm dài thì giữ nguyên như một khoá.
    """
    result: dict[str, str] = {}
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
                vals = [v.split("/")[0].split(";")[0].strip() for v in value.split(",")]
                if (
                    len(keys) == len(vals)
                    and all(keys) and all(vals)
                    and max(len(k) for k in keys) <= 4
                ):
                    for k2, v2 in zip(keys, vals):
                        result[k2] = v2
                    continue
            value = value.split("/")[0].split(";")[0].strip()
            if key and value:
                result[key] = value
    return result


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


def load(force: bool = False) -> None:
    """Nạp toàn bộ từ điển vào bộ nhớ MỘT LẦN (dùng cache pickle nếu còn mới)."""
    global _names, _vietphrase, _hanviet, _luatnhan, _surnames, _loaded
    if _loaded and not force:
        return
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
                if len(data) != 5:  # cache cũ (trước surnames) → nạp lại từ file
                    raise ValueError("cache từ điển bản cũ")
                _names, _vietphrase, _hanviet, _luatnhan, _surnames = data
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
    _names = _parse_dict_file(sources[0])
    _vietphrase = _parse_dict_file(sources[1])
    _hanviet = _parse_dict_file(sources[2])
    _luatnhan, _luatnhan_literal = _parse_luatnhan_file(sources[3])
    _surnames = _parse_dict_file(sources[4])
    _vietphrase.update(_luatnhan_literal)  # dòng Luật Nhân không có {0} → cụm thường
    _loaded = True
    try:
        DICT_DIR.mkdir(parents=True, exist_ok=True)
        with open(_CACHE_FILE, "wb") as fh:
            pickle.dump(
                (_names, _vietphrase, _hanviet, _luatnhan, _surnames),
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
    global _names
    _names = _parse_dict_file(DICT_DIR / "names.txt")
    logger.info("Đã nạp lại names.txt: %d tên riêng", len(_names))
    return len(_names)


def _match_luatnhan(text: str, i: int, depth: int) -> tuple[int, str] | None:
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
                value = value.replace("{0}", _fill_middle(fill, depth), 1)
            return pos - i, value
    return None


def _fill_middle(text: str, depth: int) -> str:
    """Dịch đoạn chèn vào {0} bằng chính bộ máy token (mẫu lồng tối đa 3 lớp)."""
    return _render(_tokenize(text, depth + 1), capitalize_next=False)


def _tokenize(text: str, depth: int = 0) -> list[tuple[str, str]]:
    """Tách chuỗi Trung thành token (kind, giá trị) — kind: name/phrase/word/raw."""
    pieces: list[tuple[str, str]] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if not _is_han(ch):
            pieces.append(("raw", ch))
            i += 1
            continue
        span = min(MAX_KEY, n - i)
        seg: str | None = None
        kind = ""
        # 1) Names — cụm dài nhất trước, ưu tiên trên cùng
        for length in range(span, 0, -1):
            part = text[i : i + length]
            if part in _names:
                seg, kind = _names[part], "name"
                i += length
                break
        # 2) Luật Nhân — mẫu có ô {0}, prefix dài nhất trước (nội suy tối đa 3 lớp)
        if seg is None and depth < _MAX_DEPTH:
            matched = _match_luatnhan(text, i, depth)
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
        pieces.append((kind, seg))
    return pieces


def convert(text: str) -> str:
    """Dịch Trung → Việt bằng từ điển (longest-match). Không gọi mạng."""
    load()
    if not text or not text.strip():
        return ""
    text = unicodedata.normalize("NFC", text).replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("……", "...").replace("…", "...")
    # --- Tách token rồi hậu xử lý: ngăn cách dấu cách, dấu câu Việt, viết hoa ---
    return _render(_tokenize(text))

def _render(pieces: list[tuple[str, str]], capitalize_next: bool = True) -> str:
    """Ghép token thành văn bản: đúng 1 dấu cách giữa các token, dấu câu Việt,
    viết hoa chữ đầu câu/đoạn (trừ khi đang điền giữa chừng một mẫu {0})."""
    out: list[str] = []
    open_pending = False  # vừa dán ngoặc/nháy MỞ → token kế tiếp không cách
    for kind, value in pieces:
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
