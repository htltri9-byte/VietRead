"""Dịch nội dung chương sang tiếng Việt — chia đoạn (chunk) rồi gọi API dịch (C4).

Mỗi chunk được dịch qua **chuỗi endpoint dự phòng** (thử lần lượt cho tới khi thành công):

1. `TRANSLATE_API_URL` trong `.env` (nếu có) — API dịch riêng của bạn;
2. Endpoint công khai `translate.googleapis.com` (không cần khoá);
3. Endpoint dự phòng `api.mymemory.translated.net` (không cần khoá).

Endpoint nào liên tục lỗi (vd: Google chặn IP `429` với client Python) sẽ bị
**tự tạm nghỉ theo thời gian** (cooldown vài phút / 1 giờ với lỗi quota) rồi
tự thử lại — **không bỏ vĩnh viễn**, nên server không cần restart khi endpoint
hồi phục (fix lỗi "Dịch thất bại ()" do toàn bộ endpoint bị khoá tới cuối
process). Endpoint đang chạy tốt được ghi nhớ để các chunk sau dùng thẳng
(nhanh). Một chunk thất bại trên tất cả endpoint → ném `TranslationError`
để worker đánh dấu job = Failed kèm thông báo tiếng Việt có **nêu rõ tên từng
endpoint và lý do** (đúng C4 — không bao giờ có "()" rỗng).
"""

from __future__ import annotations

import logging
import os
import re
import time

from .. import vietphrase  # app/vietphrase.py — dịch offline bằng từ điển
from collections.abc import Callable

import httpx

logger = logging.getLogger("vietread.translator")

# Endpoint gtx của Google — phản hồi [[["seg", "gốc", ...], ...], ...]
GOOGLE_TRANSLATE_API = "https://translate.googleapis.com/translate_a/single"
# MyMemory — phản hồi { "responseData": { "translatedText": "..." } } (miễn phí, có quota ngày)
MYMEMORY_TRANSLATE_API = "https://api.mymemory.translated.net/get"

# Mỗi request dịch tối đa bao nhiêu ký tự (endpoint nào cũng cắt theo ký tự;
# 120 ký tự ≈ 480 byte UTF-8, dưới giới hạn 500 byte của MyMemory)
CHUNK_CHARS = 1200
SMALL_CHUNK_CHARS = 120
REQUEST_TIMEOUT = 20.0  # giây
MAX_RETRIES = 2
RETRY_DELAY = 1.0  # giây

# Cooldown: endpoint lỗi >= COOLDOWN_AFTER_FAILS lần liên tiếp sẽ tự nghỉ
# rồi tự quay lại (không cần restart server).
COOLDOWN_AFTER_FAILS = 2
COOLDOWN_SECONDS = 300  # 5 phút — lỗi thường (timeout, HTTP 5xx...)
COOLDOWN_QUOTA_SECONDS = 3600  # 1 giờ — hết quota / bị chặn 429 (hồi phục chậm)
COOLDOWN_MAX_SECONDS = 43200  # trần 12 giờ cho cooldown theo thời điểm hồi phục

# Trạng thái trong tiến trình hiện tại (reset khi restart server)
_preferred: str | None = None  # endpoint đang chạy tốt
_fail_counts: dict[str, int] = {}  # lỗi liên tiếp per endpoint
_last_errors: dict[str, str] = {}  # lỗi gần nhất per endpoint (cho thông báo)
_cooldown_until: dict[str, float] = {}  # thời điểm endpoint được thử lại


class TranslationError(Exception):
    """Lỗi gọi API dịch (không có mạng, hết quota, chặn IP, sai khoá...)."""


def _parse_response(data) -> str:
    """Đọc phản hồi của cả 3 dạng: gtx list / {translatedText} / MyMemory."""
    # Dạng gtx: [[["bản dịch", "gốc", ...], ...], ...]
    if isinstance(data, list) and data and isinstance(data[0], list):
        parts = [
            seg[0]
            for seg in data[0]
            if isinstance(seg, list) and seg and isinstance(seg[0], str)
        ]
        if parts:
            return "".join(parts)
    # Dạng v2 / MyMemory
    if isinstance(data, dict):
        if isinstance(data.get("responseData"), dict):
            text = data["responseData"].get("translatedText")
            if text:
                if data.get("quotaFinished"):
                    raise TranslationError("hết quota miễn phí của MyMemory")
                return str(text)
        if data.get("translatedText"):
            return str(data["translatedText"])
    raise TranslationError("phản hồi không đúng định dạng")


def _request(url: str, params: dict, headers: dict | None = None) -> str:
    """Gọi 1 endpoint dịch cho 1 chunk — thử lại MAX_RETRIES lần rồi báo lỗi.

    HTTP 429 (hết quota / chặn) không thử lại vì retry ngay cũng khó qua được.
    """
    last = "unknown"
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = httpx.get(
                url,
                params=params,
                headers=headers or {},
                timeout=REQUEST_TIMEOUT,
                follow_redirects=True,
            )
            if resp.status_code == 429:
                detail = _http_error_detail(resp)
                raise TranslationError(
                    f"HTTP 429: {detail}" if detail else "HTTP 429 (bị chặn / hết quota)"
                )
            if resp.status_code >= 400:
                detail = _http_error_detail(resp)
                last = f"HTTP {resp.status_code}: {detail}" if detail else f"HTTP {resp.status_code}"
            else:
                return _parse_response(resp.json())
        except TranslationError as exc:
            last = str(exc)
            break  # 429 / sai định dạng → dừng ngay, không retry vô ích
        except Exception as exc:  # timeout / không có mạng / JSON lỗi
            last = f"{type(exc).__name__}: {exc}"
        if attempt < MAX_RETRIES:
            time.sleep(RETRY_DELAY)
    raise TranslationError(last)


# ---------------------------------------------------------------------------
# Các endpoint cụ thể — mỗi endpoint tự chia chunk theo sức chứa của mình
# ---------------------------------------------------------------------------


def _split_chars(text: str, limit: int) -> list[str]:
    """Chia text thành các chunk ≤ limit ký tự, cắt theo ranh giới đoạn/câu."""
    chunks: list[str] = []
    current = ""
    for para in text.split("\n"):
        while len(para) > limit:  # một đoạn quá dài → cắt theo câu
            cut = para.rfind("。", 0, limit)
            if cut < limit // 4:
                cut = limit - 1
            piece, para = para[: cut + 1], para[cut + 1 :]
            if current:
                chunks.append(current)
                current = ""
            chunks.append(piece)
        candidate = f"{current}\n{para}" if current else para
        if len(candidate) > limit and current:
            chunks.append(current)
            current = para
        else:
            current = candidate
    if current.strip():
        chunks.append(current)
    return [c for c in chunks if c.strip()]


def _google(text: str, target_lang: str) -> str:
    """Endpoint Google gtx (mặc định, không cần khoá)."""
    api = os.getenv("TRANSLATE_API_URL", "").strip() or GOOGLE_TRANSLATE_API
    key = os.getenv("TRANSLATE_API_KEY", "").strip()
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    parts = []
    for chunk in _split_chars(text, CHUNK_CHARS):
        parts.append(
            _request(
                api,
                {
                    "client": "gtx",
                    "sl": "auto",
                    "tl": target_lang,
                    "dt": "t",
                    "q": chunk,
                },
                headers,
            )
        )
    return "\n".join(parts)


def _detect_lang(text: str) -> str:
    """MyMemory cần tên ngôn nguồn: có chữ Trung → 'zh', không thì 'en'."""
    for ch in text:
        if "\u4e00" <= ch <= "\u9fff":
            return "zh"
    return "en"


def _mymemory(text: str, target_lang: str) -> str:
    """Endpoint dự phòng MyMemory (miễn phí, không cần khoá, giới hạn 500 byte).

    Đặt `TRANSLATE_EMAIL` trong `.env` → MyMemory tăng hạn mức ngày
    (5000 → 50000 từ) — hữu ích khi nhập chương dài.
    """
    source = _detect_lang(text)
    email = os.getenv("TRANSLATE_EMAIL", "").strip()
    parts = []
    for chunk in _split_chars(text, SMALL_CHUNK_CHARS):
        params = {"q": chunk, "langpair": f"{source}|{target_lang}"}
        if email:
            params["de"] = email
        parts.append(_request(MYMEMORY_TRANSLATE_API, params))
    return "\n".join(parts)


def _candidates(target_lang: str) -> list[tuple[str, Callable[[str, str], str]]]:
    """Danh sách endpoint theo thứ tự ưu tiên (endpoint đang nhớ chạy tốt lên đầu)."""
    named: list[tuple[str, Callable[[str, str], str]]] = []
    configured = os.getenv("TRANSLATE_API_URL", "").strip()
    if configured:
        named.append(("api cấu hình", _google))  # _google đã đọc TRANSLATE_API_URL
    named.append(("google", _google))
    named.append(("mymemory", _mymemory))

    # Gộp trùng (khi TRANSLATE_API_URL trỏ đúng google) + endpoint đang nhớ lên đầu
    seen: set[str] = set()
    ordered: list[tuple[str, Callable[[str, str], str]]] = []
    if _preferred:
        for name, fn in named:
            if name == _preferred and name not in seen:
                ordered.append((name, fn))
                seen.add(name)
    for name, fn in named:
        if name not in seen:
            ordered.append((name, fn))
            seen.add(name)
    return ordered


def _http_error_detail(resp: httpx.Response) -> str:
    """Đọc thông báo lỗi trong body — MyMemory ghi rõ lý do + thời điểm hồi quota."""
    try:
        data = resp.json()
    except Exception:
        data = None
    if isinstance(data, dict):
        for key in ("responseDetails", "message", "errorMessage"):
            value = data.get(key)
            if isinstance(value, str) and value.strip():
                return " ".join(value.split())[:300]
        nested = data.get("responseData")
        if isinstance(nested, dict) and isinstance(nested.get("translatedText"), str):
            return " ".join(nested["translatedText"].split())[:300]
    text = (resp.text or "").strip()
    if text and not text.startswith("<"):  # bỏ qua trang HTML kiểu "Sorry..."
        return " ".join(text.split())[:300]
    return ""


def _quota_wait_seconds(message: str) -> int | None:
    """MyMemory báo 'NEXT AVAILABLE IN 05 HOURS 10 MINUTES' → số giây cần chờ.

    Trả None nếu thông báo không nêu thời điểm (dùng cooldown mặc định).
    """
    if "NEXT AVAILABLE IN" not in message.upper():
        return None
    hours = re.search(r"(\d+)\s+HOURS?", message, re.IGNORECASE)
    minutes = re.search(r"(\d+)\s+MINUTES?", message, re.IGNORECASE)
    if not hours and not minutes:
        return None
    seconds = (int(hours.group(1)) if hours else 0) * 3600
    seconds += (int(minutes.group(1)) if minutes else 0) * 60
    return min(seconds + 60, COOLDOWN_MAX_SECONDS)  # +1 phút đệm


def _fmt_wait(seconds: float) -> str:
    """Đổi số giây chờ còn lại sang dạng dễ đọc cho người dùng (tiếng Việt)."""
    seconds = max(1, int(seconds))
    if seconds >= 3600:
        h, m = divmod(seconds // 60, 60)
        return f"{h} giờ {m} phút" if m else f"{h} giờ"
    if seconds >= 60:
        return f"{seconds // 60} phút"
    return f"{seconds} giây"


def _is_quota_or_limit(message: str) -> bool:
    """Lỗi quota / bị chặn (429) → endpoint hồi phục chậm, cho nghỉ lâu hơn."""
    low = message.lower()
    return "429" in low or "quota" in low or "chặn" in low


def _mark_success(name: str) -> None:
    """Endpoint chạy được → ghi nhớ làm mặc định, xoá mọi vết lỗi/cooldown."""
    global _preferred
    _preferred = name
    _fail_counts.pop(name, None)
    _last_errors.pop(name, None)
    _cooldown_until.pop(name, None)


def _mark_failure(name: str, message: str) -> None:
    """Ghi lỗi và tự đặt cooldown sau COOLDOWN_AFTER_FAILS lần liên tiếp.

    Cooldown có thời hạn (5 phút / 1 giờ) thay vì bỏ vĩnh viễn như trước —
    hết hạn endpoint tự được thử lại, server khỏi restart.
    """
    global _preferred
    _fail_counts[name] = _fail_counts.get(name, 0) + 1
    _last_errors[name] = message
    if _preferred == name:
        _preferred = None
    if _fail_counts[name] >= COOLDOWN_AFTER_FAILS:
        # Nếu API báo rõ thời điểm hồi ("NEXT AVAILABLE IN ...") thì dùng đúng;
        # không thì quota/429 nghỉ 1 giờ, lỗi thường nghỉ 5 phút.
        seconds = _quota_wait_seconds(message)
        if seconds is None:
            seconds = COOLDOWN_QUOTA_SECONDS if _is_quota_or_limit(message) else COOLDOWN_SECONDS
        _cooldown_until[name] = time.time() + seconds
        _fail_counts[name] = 0  # sang chu kỳ mới khi hết cooldown


def translate_text(
    text: str,
    target_lang: str = "vi",
    on_progress=None,
    mark_alternatives: bool = False,
    mark_level: str | None = None,
    key_choices: dict[str, str] | None = None,
    skip_keys: set[str] | None = None,
) -> str:
    """Dịch [text] sang [target_lang] theo biến `TRANSLATE_MODE` trong `.env`:

    - **`dict`** (mặc định): dịch OFFLINE bằng từ điển (`vietphrase.convert`) —
      không cần mạng, không cần TRANSLATE_API_KEY / TRANSLATE_API_URL;
    - **`online`**: chỉ dùng chuỗi endpoint online như trước;
    - **`auto`**: thử online trước, lỗi thì rơi về từ điển offline.

    `mark_alternatives=True` — cụm từ điển có nhiều nghĩa (đã qua bộ lọc
    [app.marking]) được xuất thành marker `{中文|nghĩa1|nghĩa2}` (chỉ áp dụng
    khi dịch bằng từ điển; dịch online không tạo marker) — dùng cho nội dung
    chương lưu vào `Content` bản thô.

    `mark_level` — mức gợi ý `low | medium | high` (mặc định `MARK_LEVEL` trong
    `.env` → `low`). `key_choices` / `skip_keys` — nghĩa đã chọn / khóa bỏ hỏi
    RIÊNG CỦA TRUYỆN (StoryWordChoices / StoryIgnoredWords) — khoá này tự dùng
    đúng nghĩa đã chọn, không tạo marker nữa.

    `on_progress(done, total)` (tuỳ chọn) được gọi theo từng đoạn xuống dòng khi
    dịch từ điển — worker dùng để cập nhật % tiến độ job. Lỗi từ điển được bọc
    lại thành `TranslationError` kèm **tên exception + nội dung thật** (không nhắc
    API key vì không liên quan) và traceback được log ra terminal uvicorn.
    """
    if not text or not text.strip():
        return ""

    mode = os.getenv("TRANSLATE_MODE", "dict").strip().lower()
    if mode not in ("dict", "online", "auto"):
        logger.warning("TRANSLATE_MODE=%r không hợp lệ — dùng 'dict'", mode)
        mode = "dict"

    if mode in ("online", "auto"):
        try:
            return _translate_online(text, target_lang)
        except TranslationError:
            if mode == "online":
                raise
            logger.warning("Dịch online lỗi — chuyển sang từ điển offline", exc_info=True)

    return _translate_dict(
        text,
        on_progress,
        mark_alternatives,
        mark_level,
        key_choices,
        skip_keys,
    )


def _translate_dict(
    text: str,
    on_progress=None,
    mark_alternatives: bool = False,
    mark_level: str | None = None,
    key_choices: dict[str, str] | None = None,
    skip_keys: set[str] | None = None,
) -> str:
    """Dịch offline bằng từ điển — chia theo từng dòng, trần marker tính cả chương."""
    try:
        vietphrase.load()
        lines = text.split("\n")
        converted = vietphrase.convert_lines(
            lines,
            mark_alternatives=mark_alternatives,
            mark_level=mark_level,
            key_choices=key_choices,
            skip_keys=skip_keys,
            on_progress=on_progress,
        )
        return "\n".join(converted)
    except TranslationError:
        raise
    except Exception as exc:
        logger.exception("Lỗi dịch từ điển offline")
        raise TranslationError(f"{type(exc).__name__}: {exc}") from exc


def _translate_online(text: str, target_lang: str) -> str:
    """Dịch online — chuỗi endpoint dự phòng (cơ chế cũ: cooldown, thử lại...)."""
    if not text or not text.strip():
        return ""

    now = time.time()
    errors: list[str] = []
    for name, fn in _candidates(target_lang):
        cooling = _cooldown_until.get(name, 0.0) - now
        if cooling > 0:
            # Vẫn nêu rõ endpoint + lỗi trước đó để người dùng biết vì sao.
            errors.append(
                f"{name}: tạm ngưng {_fmt_wait(cooling)} nữa (lần trước: "
                f"{_last_errors.get(name, 'không rõ')})"
            )
            continue
        try:
            result = fn(text, target_lang)
            _mark_success(name)
            return result
        except TranslationError as exc:
            errors.append(f"{name}: {exc}")
            _mark_failure(name, str(exc))

    detail = "; ".join(errors)[:500] or "chưa thử được endpoint nào"
    raise TranslationError(
        f"Dịch thất bại ({detail}) — kiểm tra TRANSLATE_API_KEY / TRANSLATE_API_URL "
        "trong backend/.env và kết nối mạng"
    )
