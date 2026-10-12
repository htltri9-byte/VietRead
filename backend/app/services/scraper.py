"""Cào thông tin truyện + chương từ nguồn nước ngoài (C4 — Bước 10).

Mỗi nguồn (Qidian, B.faloo, Fanqie…) là một adapter riêng cùng interface
`parse_story(url)` / `parse_chapter(url)` để dễ thêm nguồn mới.

Chiến lược parse best-effort: thẻ `og:` (title/mô tả/bìa) + regex link chương
+ thẻ `<p>` cho nội dung — các nguồn này hay thay giao diện hoặc chặn IP,
lúc đó adapter ném `AdapterError` với thông báo tiếng Việt rõ ràng để worker
đánh dấu job = Failed kèm `Error` (đúng C4: "nguồn chặn, link không hợp lệ").

Ngoài ra có nguồn demo `demo.vietread.local` dùng fixture có sẵn (không cần
mạng) để kiểm thử / demo toàn bộ luồng nhập – dịch mà không phụ thuộc mạng.
"""

from __future__ import annotations

import html as html_lib
import json
import os
import re
import time
from dataclasses import dataclass, field
from urllib.parse import urljoin, urlparse

import httpx

# --- Cấu hình request tới nguồn ---------------------------------------------
REQUEST_TIMEOUT = 15.0  # giây
MAX_RETRIES = 3  # số lần thử lại khi tải trang lỗi/dạng
RETRY_DELAY = 2.0  # delay giữa các lần thử (giây)

_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
    ),
    "Accept-Language": "zh-CN,zh;q=0.9,vi;q=0.8",
}

# Nguồn demo: fixture có sẵn trong file này, không gọi mạng khi cào.
DEMO_HOST = "demo.vietread.local"


class AdapterError(Exception):
    """Lỗi khi cào nguồn (nguồn chặn, HTML đổi, link không hợp lệ…)."""


@dataclass
class ParsedStory:
    """Thông tin truyện + danh sách chương lấy được từ nguồn."""

    title: str
    author: str = ""
    description: str = ""
    cover_url: str | None = None
    genres: list[str] = field(default_factory=list)
    # (tên chương, url chương) theo thứ tự trên nguồn
    chapters: list[tuple[str, str]] = field(default_factory=list)


@dataclass
class ParsedChapter:
    """Một chương đã cào: tiêu đề + nội dung gốc (trước khi dịch)."""

    title: str
    content: str


def _fetch(url: str) -> str:
    """GET một trang với retry + delay giữa các lần thử (C4)."""
    last = "unknown"
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = httpx.get(
                url, headers=_HEADERS, timeout=REQUEST_TIMEOUT, follow_redirects=True
            )
            if resp.status_code == 403:
                raise AdapterError(f"Nguồn chặn yêu cầu (HTTP 403): {url}")
            if resp.status_code in (401, 402):
                raise AdapterError(
                    f"Nguồn yêu cầu đăng nhập/quyền truy cập (HTTP {resp.status_code}): {url}"
                )
            if resp.status_code >= 400:
                raise AdapterError(f"Nguồn trả HTTP {resp.status_code}: {url}")
            return resp.text
        except AdapterError:
            raise
        except Exception as exc:  # timeout / DNS / kết nối gián đoạn
            last = f"{type(exc).__name__}: {exc}"
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_DELAY)
    raise AdapterError(f"Không tải được trang sau {MAX_RETRIES} lần thử: {url} ({last})")


def _meta(html: str, prop: str) -> str:
    """Đọc thẻ <meta property="og:..." content="..."> (có ở hầu hết trang truyện)."""
    m = re.search(
        rf'<meta[^>]+(?:property|name)="{re.escape(prop)}"[^>]+content="([^"]*)"',
        html,
        flags=re.IGNORECASE,
    )
    return html_lib.unescape(m.group(1)).strip() if m else ""


def _strip_tags(fragment: str) -> str:
    """Bỏ mọi thẻ HTML còn lại và giải entity."""
    text = re.sub(r"<[^>]+>", " ", fragment)
    return re.sub(r"\s+", " ", html_lib.unescape(text)).strip()


# Ký tự PUA (Private Use Area) — Fanqie thay chữ thật bằng ký tự ngoài Unicode
# rồi render bằng font web riêng → gặp PUA là nội dung bị mã hoá anti-scrape.
PUA_RE = re.compile(r"[\ue000-\uf8ff]")


def _extract_content(html: str) -> str:
    """Lấy nội dung chương: các thẻ <p> (bỏ script/style).

    Chỉ tin thẻ <p> — tách theo `<br>` hay dòng lề dễ lấy nhầm phần điều hướng
    thành nội dung (thực tế gặp với trang chương Faloo)."""
    body = re.sub(
        r"<(script|style)[^>]*>.*?</\1>", " ", html, flags=re.IGNORECASE | re.S
    )
    paragraphs = [
        _strip_tags(p)
        for p in re.findall(r"<p[^>]*>(.*?)</p>", body, flags=re.IGNORECASE | re.S)
    ]
    kept = [p for p in paragraphs if len(p) >= 5]
    return "\n".join(kept)


class SourceAdapter:
    """Interface chung của một nguồn: `parse_story(url)` / `parse_chapter(url)`."""

    # Domain nhận diện nguồn (kèm cả subdomain, vd: m.qidian.com)
    hosts: tuple[str, ...] = ()

    @classmethod
    def matches(cls, host: str) -> bool:
        host = host.lower()
        return any(host == h or host.endswith("." + h) for h in cls.hosts)

    def parse_story(self, url: str) -> ParsedStory:
        raise NotImplementedError

    def parse_chapter(self, url: str) -> ParsedChapter:
        raise NotImplementedError


class _HtmlAdapter(SourceAdapter):
    """Adapter dùng chung cho các nguồn HTML thuần (og: meta + regex link chương).

    Tên/mô tả/bìa lấy từ thẻ `og:`; danh sách chương là các link có chữ
    `第…章/回/节` (mẫu link chương của Qidian/Fanqie/Faloo); nội dung chương
    lấy toàn bộ thẻ `<p>`.
    """

    # Regex link chương — mỗi nguồn override được nếu giao diện khác đi
    chapter_link_re = re.compile(
        r'<a[^>]+href="([^"]+)"[^>]*>\s*([^<]*(?:章|回|节|節)[^<]*)\s*</a>',
        flags=re.IGNORECASE,
    )

    def parse_story(self, url: str) -> ParsedStory:
        page = _fetch(url)
        title = _meta(page, "og:title")
        if not title:
            m_h1 = re.search(r"<h1[^>]*>(.*?)</h1>", page, flags=re.S)
            title = _strip_tags(m_h1.group(1)) if m_h1 else ""
        if not title:
            raise AdapterError(
                "Không tìm thấy tên truyện — nguồn có thể đã đổi giao diện hoặc chặn máy chủ"
            )

        author = ""
        m_author = re.search(r'"authorName"\s*:\s*"([^"]+)"', page)
        if m_author:
            author = m_author.group(1).strip()
        else:
            m_author = re.search(r"author[^>]*>\s*([^<]{2,60})\s*<", page, flags=re.I)
            author = m_author.group(1).strip() if m_author else ""

        chapters: list[tuple[str, str]] = []
        seen: set[str] = set()
        for href, label in self.chapter_link_re.findall(page):
            full = urljoin(url, href)
            if full in seen:
                continue
            seen.add(full)
            chapters.append((_strip_tags(label), full))
        if not chapters:
            raise AdapterError(
                "Không tìm thấy danh sách chương — nguồn có thể yêu cầu đăng nhập "
                "hoặc chặn máy chủ"
            )

        cover = _meta(page, "og:image") or None
        return ParsedStory(
            title=title,
            author=author,
            description=_meta(page, "og:description"),
            cover_url=cover,
            chapters=chapters,
        )

    def parse_chapter(self, url: str) -> ParsedChapter:
        page = _fetch(url)
        title = _meta(page, "og:title")
        content = _extract_content(page)
        if len(content) < 30:
            raise AdapterError(
                "Nội dung chương rỗng — nguồn yêu cầu đăng nhập/quyền truy cập "
                "(nội dung trả phí hoặc bị chặn)"
            )
        return ParsedChapter(title=title, content=content)


class QidianAdapter(_HtmlAdapter):
    """Qidian — bản desktop (www.qidian.com) chặn bot (HTTP 202) nên mọi link
    đều rewrite về bản mobile `m.qidian.com` (SSR, đọc được không cần JS);
    danh sách chương lấy từ trang `/catalog/` (đủ hàng trăm chương, sắp theo 第N章)."""

    hosts = ("qidian.com",)

    def _mobile_catalog(self, url: str) -> str:
        """Đưa mọi link Qidian (book/chapter, www/m) về catalog mobile."""
        path = urlparse(url).path
        m_ch = re.search(r"/chapter/(\d+)/", path)
        m_book = re.search(r"/book/(\d+)", path)
        if m_ch:
            return f"https://m.qidian.com/book/{m_ch.group(1)}/catalog/"
        if m_book:
            return f"https://m.qidian.com/book/{m_book.group(1)}/catalog/"
        raise AdapterError(f"Link Qidian không đúng dạng trang truyện: {url}")

    def parse_story(self, url: str) -> ParsedStory:
        catalog_url = self._mobile_catalog(url)
        book_url = re.sub(r"/catalog/?$", "/", catalog_url)

        # Thông tin truyện lấy từ trang book (có og: + author)
        page = _fetch(book_url)
        title = _meta(page, "og:title")
        if not title:
            m_h1 = re.search(r"<h1[^>]*>(.*?)</h1>", page, flags=re.S)
            title = _strip_tags(m_h1.group(1)) if m_h1 else ""
        if not title:
            raise AdapterError("Không tìm thấy tên truyện Qidian (nguồn đổi giao diện hoặc chặn)")
        m_author = re.search(r"author[^>]*>\s*([^<]*[^\s<][^<]*)\s*<", page)

        # Danh sách chương từ catalog: 第N章 gần nhất phía trước mỗi link
        catalog = _fetch(catalog_url)
        by_number: dict[int, str] = {}
        for m in re.finditer(r"第(\d+)章", catalog):
            before = catalog[max(0, m.start() - 400) : m.start()]
            hrefs = re.findall(r'href="([^"]*/chapter/\d+/\d+/[^"]*)"', before)
            if hrefs:
                by_number.setdefault(int(m.group(1)), urljoin(catalog_url, hrefs[-1]))
        if not by_number:
            raise AdapterError(
                "Không tìm thấy danh sách chương Qidian — nguồn có thể yêu cầu đăng nhập "
                "hoặc chặn máy chủ"
            )

        return ParsedStory(
            title=title,
            author=m_author.group(1).strip() if m_author else "",
            description=_meta(page, "og:description"),
            cover_url=_meta(page, "og:image") or None,
            chapters=[("", by_number[n]) for n in sorted(by_number)],
        )

    def parse_chapter(self, url: str) -> ParsedChapter:
        # Chapter link từ catalog đã là m.qidian; link người dùng dán thì rewrite
        path = urlparse(url).path
        if re.search(r"/chapter/\d+/\d+/", path) and urlparse(url).netloc != "m.qidian.com":
            url = f"https://m.qidian.com{path}"
        page = _fetch(url)
        title = _meta(page, "og:title")
        if not title:
            m_h1 = re.search(r"<h1[^>]*>(.*?)</h1>", page, flags=re.S)
            title = _strip_tags(m_h1.group(1)) if m_h1 else ""
        content = _extract_content(page)
        if "登录订阅" in page or "lock-mask" in page:
            raise AdapterError(
                "Nội dung chương này là trả phí (VIP) của Qidian — chỉ đọc được đoạn "
                "mở đầu, cần đăng nhập/mua điểm để lấy trọn chương"
            )
        if len(content) < 30:
            raise AdapterError(
                "Nội dung chương Qidian rỗng — nguồn có thể đã đổi giao diện hoặc chặn máy chủ"
            )
        return ParsedChapter(title=title, content=content)


class FalooAdapter(_HtmlAdapter):
    """B.faloo (b.faloo.com / wap.faloo.com) — trang chương yêu cầu đăng nhập
    tài khoản (thẻ `noLogin`) nên khách đọc được trang nhưng không có nội dung."""

    hosts = ("faloo.com",)

    def parse_chapter(self, url: str) -> ParsedChapter:
        page = _fetch(url)
        title = _meta(page, "og:title")
        if not title:
            m_h1 = re.search(r"<h1[^>]*>(.*?)</h1>", page, flags=re.S)
            title = _strip_tags(m_h1.group(1)) if m_h1 else ""
        content = _extract_content(page)
        if len(content) >= 30:
            return ParsedChapter(title=title, content=content)
        if "noLogin" in page or "请登录" in page:
            raise AdapterError(
                "Faloo yêu cầu đăng nhập tài khoản mới đọc được nội dung chương "
                "(khách chỉ thấy thông báo đăng nhập)"
            )
        raise AdapterError(
            "Nội dung chương Faloo rỗng — nguồn có thể đã đổi giao diện hoặc chặn máy chủ"
        )


class FanqieAdapter(_HtmlAdapter):
    """Fanqie Novel (fanqie.com.cn / fanqienovel.com) — trang chương SSR nhưng
    **mã hoá nội dung**: chữ bị thay bằng ký tự PUA rồi render bằng font web
    riêng (anti-scrape); đọc nội dung từ JSON `chapterData.content` và báo rõ
    khi gặp bản mã hoá (giải mã thật cần OCR font — ngoài phạm vi demo)."""

    hosts = ("fanqie.com.cn", "fanqienovel.com")

    def parse_chapter(self, url: str) -> ParsedChapter:
        page = _fetch(url)
        title = _meta(page, "og:title")
        content = ""
        marker = page.find('"chapterData"')
        if marker >= 0:
            try:
                data, _ = json.JSONDecoder().raw_decode(
                    page, page.find(":", marker) + 1
                )
                if isinstance(data, dict):
                    title = str(data.get("title") or title or "")
                    content = _extract_content(str(data.get("content") or ""))
            except (json.JSONDecodeError, IndexError, TypeError):
                content = ""
        if not content:
            content = _extract_content(page)
        if len(content) < 30:
            raise AdapterError(
                "Không đọc được nội dung chương Fanqie — nguồn có thể yêu cầu đăng nhập "
                "hoặc đổi giao diện"
            )
        if PUA_RE.search(content):
            raise AdapterError(
                "Fanqie mã hoá nội dung bằng font anti-scrape (chữ bị thay bằng ký tự "
                "ngoài Unicode) — chưa giải mã được, cần công cụ OCR font riêng"
            )
        return ParsedChapter(title=title, content=content)


# ---------------------------------------------------------------------------
# Nguồn demo — fixture có sẵn, không cào mạng (dùng cho kiểm thử / demo)
# ---------------------------------------------------------------------------

_DEMO_STORY = ParsedStory(
    title="青云之路",
    author="演示作者",
    description="一个少年踏上修行之路，历经风雨，终成一代宗师。",
    cover_url=None,
    genres=["Tiên Hiệp"],
    chapters=[
        ("第一章 起风", f"https://{DEMO_HOST}/chapter/1"),
        ("第二章 入门", f"https://{DEMO_HOST}/chapter/2"),
        ("第三章 试炼", f"https://{DEMO_HOST}/chapter/3"),
    ],
)

_DEMO_CHAPTER_CONTENT = {
    1: "少年站在山巅，望着远方的云海。\n他知道，从今天起，一切都不一样了。\n风起时，剑鸣如龙吟。",
    2: "他拜入山门，开始修炼剑法。\n师父说：心不静，则剑不利。\n日夜苦练，寒暑不辍。",
    3: "山下来了强敌，众人惊慌。\n他提剑而上，只身迎敌。\n三招之后，风停雨歇。",
}


class DemoAdapter(SourceAdapter):
    """Nguồn demo `demo.vietread.local`: trả fixture có sẵn (không cần mạng).

    Việc *dịch* vẫn chạy thật — nên dùng nguồn này để demo luồng
    Pending → Running → % → Done + truyện nháp ngay cả khi không cào được
    Qidian/Fanqie (chặn IP, nội dung trả phí).
    """

    hosts = (DEMO_HOST,)

    def parse_story(self, url: str) -> ParsedStory:
        # Trả bản sao để caller thao tác không làm đứt fixture static
        return ParsedStory(
            title=_DEMO_STORY.title,
            author=_DEMO_STORY.author,
            description=_DEMO_STORY.description,
            cover_url=_DEMO_STORY.cover_url,
            genres=list(_DEMO_STORY.genres),
            chapters=list(_DEMO_STORY.chapters),
        )

    def parse_chapter(self, url: str) -> ParsedChapter:
        try:
            index = int(url.rstrip("/").rsplit("/", 1)[-1])
        except ValueError:
            raise AdapterError(f"Link chương demo không hợp lệ: {url}")
        if index not in _DEMO_CHAPTER_CONTENT:
            raise AdapterError(f"Chương demo không tồn tại: {url}")
        title = _DEMO_STORY.chapters[index - 1][0]
        return ParsedChapter(title=title, content=_DEMO_CHAPTER_CONTENT[index])


# Các nguồn thật + nguồn demo (đúng thứ tự ưu tiên tra host)
ADAPTERS: tuple[SourceAdapter, ...] = (
    QidianAdapter(),
    FalooAdapter(),
    FanqieAdapter(),
    DemoAdapter(),
)


def host_of(url: str) -> str:
    """Host của link (bỏ user:pass và port) — dùng cho thông báo lỗi."""
    netloc = urlparse(url).netloc
    return netloc.split("@")[-1].split(":")[0].lower()


# ---------------------------------------------------------------------------
# Tách bookId / chapterId từ link Qidian (xác nhận thực tế trên m.qidian.com)
# ---------------------------------------------------------------------------

# Định dạng link chương Qidian (đã gọi thử):
#   https://m.qidian.com/chapter/{bookId}/{chapterId}/   (bản mobile — đọc được)
#   https://www.qidian.com/chapter/{bookId}/{chapterId}/ (bản desktop — chặn bot)
#   https://m.qidian.com/book/{bookId}/{chapterId}.html  (đường dẫn cũ, redirect)
_QIDIAN_CHAPTER_RE = re.compile(r"/chapter/(\d+)/(\d+)")
_QIDIAN_LEGACY_CHAPTER_RE = re.compile(r"/book/(\d+)/(\d+)\.html$")
_QIDIAN_BOOK_RE = re.compile(r"/book/(\d+)")


def is_qidian_url(url: str) -> bool:
    """Link có thuộc domain Qidian (qidian.com hoặc subdomain) không."""
    host = host_of(url)
    return host == "qidian.com" or host.endswith(".qidian.com")


def qidian_book_id(url: str) -> str | None:
    """bookId từ link truyện Qidian (`/book/{id}/` hoặc `/chapter/{id}/{id}/`).

    Trả None nếu không phải link Qidian hoặc không khớp định dạng — dùng khi
    ghi `Stories.SourceBookId` (nhập cả bộ / thêm chương mới) bỏ qua được.
    """
    if not is_qidian_url(url):
        return None
    path = urlparse(url).path
    m = _QIDIAN_CHAPTER_RE.search(path)
    if m:
        return m.group(1)
    m = _QIDIAN_BOOK_RE.search(path)
    return m.group(1) if m else None


def qidian_chapter_id(url: str) -> tuple[str, str] | None:
    """`(bookId, chapterId)` từ link chương Qidian; None nếu không phải/link lạ.

    Dùng để ghi `Chapters.SourceChapterId/SourceChapterUrl` — chống trùng chương
    khi thêm chương vào truyện đã có.
    """
    if not is_qidian_url(url):
        return None
    path = urlparse(url).path
    m = _QIDIAN_CHAPTER_RE.search(path)
    if m:
        return m.group(1), m.group(2)
    m = _QIDIAN_LEGACY_CHAPTER_RE.search(path)
    if m:
        return m.group(1), m.group(2)
    return None


def get_adapter(url: str) -> SourceAdapter | None:
    """Chọn adapter theo domain của link; `None` = nguồn chưa được hỗ trợ."""
    host = host_of(url)
    for adapter in ADAPTERS:
        if adapter.matches(host):
            return adapter
    return None
