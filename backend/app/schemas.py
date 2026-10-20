"""Schema Pydantic validate request / định dạng response JSON (Phần B)."""

from __future__ import annotations

from datetime import datetime
from urllib.parse import urlparse

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from . import marking


class UserOut(BaseModel):
    """Thông tin người dùng trả về cho client: { id, name, email, avatarUrl }."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    name: str
    email: str
    avatar_url: str | None = Field(default=None, alias="avatarUrl")


class RegisterRequest(BaseModel):
    """POST /auth/register — { name, email, password }."""

    name: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=6, max_length=100)

    @field_validator("name")
    @classmethod
    def _strip_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Tên hiển thị không được để trống")
        return value

    @field_validator("email")
    @classmethod
    def _normalize_email(cls, value: str) -> str:
        value = value.strip().lower()
        local, _, domain = value.partition("@")
        if not local or "." not in domain or domain.startswith(".") or domain.endswith("."):
            raise ValueError("Email không hợp lệ")
        return value


class LoginRequest(BaseModel):
    """POST /auth/login — { email, password }."""

    email: str = Field(min_length=1, max_length=255)
    password: str = Field(min_length=1, max_length=100)

    @field_validator("email")
    @classmethod
    def _normalize_email(cls, value: str) -> str:
        return value.strip().lower()


class TokenResponse(BaseModel):
    """Response của đăng ký / đăng nhập: { token, user }."""

    token: str
    user: UserOut


def user_to_out(user) -> UserOut:
    """Chuyển đối tượng ORM User sang UserOut (khóa avatarUrl theo đặc tả)."""
    return UserOut(
        id=user.id,
        name=user.name,
        email=user.email,
        avatarUrl=user.avatar_url,
    )


# ===========================================================================
# Bước 2 — stories / chapters / genres (Phần B)
# ===========================================================================


class GenreOut(BaseModel):
    """Thể loại: { id, name }."""

    id: int
    name: str


class StoryFields(BaseModel):
    """Validate dùng chung cho StoryCreate / StoryUpdate."""

    model_config = ConfigDict(populate_by_name=True)

    @field_validator("title", check_fields=False)
    @classmethod
    def _check_title(cls, value: str | None) -> str | None:
        if value is None:
            return value
        value = value.strip()
        if not value:
            raise ValueError("Tên truyện không được để trống")
        return value

    @field_validator("status", check_fields=False)
    @classmethod
    def _check_status(cls, value: str | None) -> str | None:
        if value is None:
            return value
        value = value.strip().lower()
        if value not in ("ongoing", "completed"):
            raise ValueError("status phải là 'ongoing' hoặc 'completed'")
        return value

    @field_validator("genres", check_fields=False)
    @classmethod
    def _check_genres(cls, value: list[str] | None) -> list[str] | None:
        if value is None:
            return value
        if len(value) > 10:
            raise ValueError("Tối đa 10 thể loại cho một truyện")
        cleaned: list[str] = []
        seen: set[str] = set()
        for item in value:
            name = item.strip()
            if name and name.lower() not in seen:
                seen.add(name.lower())
                cleaned.append(name)
        return cleaned


class StoryCreate(StoryFields):
    """POST /stories — { title, description?, coverUrl?, status?, genres?, isDraft? }."""

    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    cover_url: str | None = Field(default=None, alias="coverUrl", max_length=500)
    status: str = "ongoing"
    genres: list[str] = Field(default_factory=list)
    is_draft: bool = Field(default=False, alias="isDraft")


class StoryUpdate(StoryFields):
    """PUT /stories/{id} — chỉ trường nào gửi lên thì mới sửa."""

    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    cover_url: str | None = Field(default=None, alias="coverUrl", max_length=500)
    status: str | None = None
    genres: list[str] | None = None
    is_draft: bool | None = Field(default=None, alias="isDraft")


class StoryOut(BaseModel):
    """Model Story theo Phần B; thêm authorId + isDraft để phân quyền ở Bước 9/10."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    title: str
    author: str
    author_id: int = Field(alias="authorId")
    cover_url: str | None = Field(default=None, alias="coverUrl")
    description: str | None = None
    genres: list[str] = Field(default_factory=list)
    status: str
    rating: float
    chapter_count: int = Field(default=0, alias="chapterCount")
    is_draft: bool = Field(default=False, alias="isDraft")
    updated_at: datetime = Field(alias="updatedAt")


class ChapterSummaryOut(BaseModel):
    """ChapterSummary: { id, storyId, index, title, updatedAt } — không kèm nội dung."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    story_id: int = Field(alias="storyId")
    index: int
    title: str
    updated_at: datetime = Field(alias="updatedAt")


class ChapterOut(BaseModel):
    """Chapter: { id, storyId, index, title, content } — kèm nội dung chương."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    story_id: int = Field(alias="storyId")
    index: int
    title: str
    content: str


class ChapterCreate(BaseModel):
    """POST /stories/{id}/chapters — bỏ trống index để tự đánh số tiếp."""

    title: str = Field(min_length=1, max_length=255)
    content: str = Field(min_length=1)
    index: int | None = Field(default=None, ge=1)

    @field_validator("title")
    @classmethod
    def _strip_title(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Tên chương không được để trống")
        return value


# ===========================================================================
# Bước 8 — comments (Phần B)
# ===========================================================================


class CommentCreate(BaseModel):
    """POST /stories/{id}/comments — { content, chapterId? }."""

    model_config = ConfigDict(populate_by_name=True)

    content: str = Field(min_length=1, max_length=2000)
    chapter_id: int | None = Field(default=None, ge=1, alias="chapterId")

    @field_validator("content")
    @classmethod
    def _strip_content(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Nội dung bình luận không được để trống")
        return value


class CommentOut(BaseModel):
    """Comment: { id, storyId, chapterId?, userId, userName, avatarUrl?, content, createdAt }."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    story_id: int = Field(alias="storyId")
    chapter_id: int | None = Field(default=None, alias="chapterId")
    user_id: int = Field(alias="userId")
    user_name: str = Field(alias="userName")
    avatar_url: str | None = Field(default=None, alias="avatarUrl")
    content: str
    created_at: datetime = Field(alias="createdAt")


class ChapterUpdate(BaseModel):
    """PUT /chapters/{id} — chỉ trường nào gửi lên thì mới sửa."""

    title: str | None = Field(default=None, max_length=255)
    content: str | None = None
    index: int | None = Field(default=None, ge=1)

    @field_validator("title")
    @classmethod
    def _strip_title(cls, value: str | None) -> str | None:
        if value is None:
            return value
        value = value.strip()
        if not value:
            raise ValueError("Tên chương không được để trống")
        return value


# ===========================================================================
# Bước 10 — nhập truyện từ link (Phần B + C4)
# ===========================================================================

# A3.10: hiện chỉ dịch sang Tiếng Việt
SUPPORTED_TARGET_LANGS = ("vi",)


class ImportCreate(BaseModel):
    """POST /imports — { sourceUrl, targetLang }."""

    model_config = ConfigDict(populate_by_name=True)

    source_url: str = Field(alias="sourceUrl", min_length=10, max_length=1000)
    target_lang: str = Field(default="vi", alias="targetLang", max_length=20)

    @field_validator("source_url")
    @classmethod
    def _check_url(cls, value: str) -> str:
        value = value.strip()
        parsed = urlparse(value)
        if parsed.scheme not in ("http", "https") or not parsed.netloc:
            raise ValueError("sourceUrl không hợp lệ — cần link http(s) đầy đủ")
        return value

    @field_validator("target_lang")
    @classmethod
    def _check_lang(cls, value: str) -> str:
        value = value.strip().lower()
        if value not in SUPPORTED_TARGET_LANGS:
            raise ValueError("targetLang chưa được hỗ trợ (hiện chỉ có 'vi' — Tiếng Việt)")
        return value


class ImportJobOut(BaseModel):
    """GET /imports/{jobId} — { jobId, status, progress, storyId?, error? }.

    status: Pending | Running | Done | Failed; progress: % chương đã dịch (0–100).
    """

    model_config = ConfigDict(populate_by_name=True)

    job_id: int = Field(alias="jobId")
    status: str
    progress: int = Field(ge=0, le=100)
    story_id: int | None = Field(default=None, alias="storyId")
    error: str | None = None


# ===========================================================================
# Thêm chương vào truyện đã có — link Qidian / dán văn bản
# ===========================================================================


MAX_PASTED_TEXT = 100_000  # giới hạn ký tự cho dán văn bản (một chương thường ~5–10k)


class _ChapterImportFields(BaseModel):
    """Trường chung: số chương tuỳ chọn + tên chương tuỳ chọn + mức gợi ý."""

    model_config = ConfigDict(populate_by_name=True)

    chapter_no: int | None = Field(default=None, alias="chapterNo", ge=1, le=1_000_000)
    title: str | None = Field(default=None, max_length=255)
    # Mức gợi ý nhiều nghĩa khi dịch chương nhập: low | medium | high
    # (thiếu → MARK_LEVEL trong .env, mặc định low)
    mark_level: str | None = Field(default=None, alias="markLevel", max_length=10)

    @field_validator("mark_level")
    @classmethod
    def _check_mark_level(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        value = value.strip().lower()
        if value not in marking.LEVELS:
            raise ValueError("markLevel phải là 'low', 'medium' hoặc 'high'")
        return value

    @field_validator("title")
    @classmethod
    def _empty_title_to_none(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None  # không gửi title / gửi rỗng đều = tự lấy từ nguồn


class ChapterImportByUrl(_ChapterImportFields):
    """POST /stories/{id}/chapters/import — { chapterUrl, chapterNo?, title? }."""

    chapter_url: str = Field(alias="chapterUrl", min_length=10, max_length=1000)

    @field_validator("chapter_url")
    @classmethod
    def _strip_url(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("chapterUrl không được để trống")
        return value


class ChapterImportByText(_ChapterImportFields):
    """POST /stories/{id}/chapters/import-text

    — { text, sourceLang: zh|vi, chapterNo?, title? }.
    """

    # Không đặt min/max_length ở Field để validator dưới báo lỗi tiếng Việt
    # (ràng buộc của Pydantic in tiếng Anh).
    text: str
    source_lang: str = Field(default="zh", alias="sourceLang", max_length=10)

    @field_validator("text")
    @classmethod
    def _check_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Nội dung chương không được để trống")
        if len(value) > MAX_PASTED_TEXT:
            raise ValueError(f"Nội dung chương tối đa {MAX_PASTED_TEXT:,} ký tự".replace(",", "."))
        return value

    @field_validator("source_lang")
    @classmethod
    def _check_lang(cls, value: str) -> str:
        value = value.strip().lower()
        if value not in ("zh", "vi"):
            raise ValueError("sourceLang phải là 'zh' (Trung) hoặc 'vi' (Việt)")
        return value


# ===========================================================================
# Sửa bản dịch: gợi ý nhiều nghĩa (marker) + tìm & thay thế theo truyện
# ===========================================================================


class ReplaceRequest(BaseModel):
    """POST /stories/{id}/replace

    — { find, replace, matchCase, wholeWord, includeTitles, applyToFuture, dryRun }.
    """

    model_config = ConfigDict(populate_by_name=True)

    find: str
    replace: str = ""
    match_case: bool = Field(default=False, alias="matchCase")
    whole_word: bool = Field(default=False, alias="wholeWord")
    include_titles: bool = Field(default=False, alias="includeTitles")
    apply_to_future: bool = Field(default=False, alias="applyToFuture")
    dry_run: bool = Field(default=False, alias="dryRun")

    @field_validator("find")
    @classmethod
    def _check_find(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Chuỗi cần tìm không được để trống")
        if len(value) > 200:
            raise ValueError("Chuỗi cần tìm tối đa 200 ký tự")
        return value


class ReplaceChapterHit(BaseModel):
    """Một chương bị ảnh hưởng: { chapterId, chapterNo, matches }."""

    model_config = ConfigDict(populate_by_name=True)

    chapter_id: int = Field(alias="chapterId")
    chapter_no: int = Field(alias="chapterNo")
    matches: int


class ReplaceOut(BaseModel):
    """POST /stories/{id}/replace.

    `dryRun=true` → chỉ `{ dryRun, totalMatches, chapters }`;
    `dryRun=false` → thêm `batchId` + `chaptersChanged` (dùng cho hoàn tác).
    """

    model_config = ConfigDict(populate_by_name=True)

    dry_run: bool = Field(alias="dryRun")
    total_matches: int = Field(alias="totalMatches")
    chapters: list[ReplaceChapterHit]
    batch_id: str | None = Field(default=None, alias="batchId")
    chapters_changed: int | None = Field(default=None, alias="chaptersChanged")


class UndoOut(BaseModel):
    """POST /stories/{id}/replace/undo — { message, restored, skipped }."""

    message: str
    restored: int
    skipped: int


class GlossaryRuleOut(BaseModel):
    """GET /stories/{id}/glossary — một quy tắc đã lưu (A → B)."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    find_text: str = Field(alias="findText")
    replace_text: str = Field(alias="replaceText")
    match_case: bool = Field(alias="matchCase")
    whole_word: bool = Field(alias="wholeWord")
    apply_to_future: bool = Field(alias="applyToFuture")
    created_at: datetime = Field(alias="createdAt")


class RetranslateOut(BaseModel):
    """POST /chapters/{id}/retranslate — nội dung để nạp vào màn Sửa chương.

    KHÔNG tự lưu: chỉ trả về, người dùng bấm Lưu mới ghi vào `Content`.
    """

    model_config = ConfigDict(populate_by_name=True)

    chapter_id: int = Field(alias="chapterId")
    content: str


class DictionaryWordOut(BaseModel):
    """GET /dictionary/names — một từ của từ điển cá nhân.

    `{ id, zh, vi, tags, createdAt }` — tags tuỳ chọn, phân cách dấu phẩy.
    """

    model_config = ConfigDict(populate_by_name=True)

    id: int
    zh: str
    vi: str
    tags: str | None = None
    created_at: datetime = Field(alias="createdAt")


# ===========================================================================
# Gợi ý nhiều nghĩa: mức gợi ý + nghĩa đã chọn theo truyện + dọn marker (clean)
# ===========================================================================


def _check_mark_level_field(value: str | None) -> str | None:
    """Validate `markLevel` — None/rỗng → None (dùng mức mặc định từ .env)."""
    if value is None or not value.strip():
        return None
    value = value.strip().lower()
    if value not in marking.LEVELS:
        raise ValueError("markLevel phải là 'low', 'medium' hoặc 'high'")
    return value


class RetranslateRequest(BaseModel):
    """POST /chapters/{id}/retranslate — body TUỲ CHỌN `{ markLevel? }`.

    Không gửi body (client cũ) → giữ nguyên hành vi, lấy mức từ `MARK_LEVEL`.
    """

    model_config = ConfigDict(populate_by_name=True)

    mark_level: str | None = Field(default=None, alias="markLevel", max_length=10)

    @field_validator("mark_level")
    @classmethod
    def _check_level(cls, value: str | None) -> str | None:
        return _check_mark_level_field(value)


class ResolveAllRequest(BaseModel):
    """POST /stories/{id}/markers/clean — `{ onlyChapterId? }`.

    `onlyChapterId` — chỉ dọn một chương; thiếu = cả truyện.
    """

    model_config = ConfigDict(populate_by_name=True)

    only_chapter_id: int | None = Field(default=None, alias="onlyChapterId", ge=1)


class ResolveAllOut(BaseModel):
    """POST /stories/{id}/markers/clean — snapshot vào ChapterRevisions
    (dùng `POST /stories/{id}/replace/undo` để hoàn tác batch này)."""

    model_config = ConfigDict(populate_by_name=True)

    message: str
    batch_id: str = Field(alias="batchId")
    chapters_changed: int = Field(alias="chaptersChanged")
    markers_resolved: int = Field(alias="markersResolved")


def _clean_meanings_field(values: list[str]) -> list[str]:
    """Chuẩn hóa danh sách nghĩa gửi lên: bỏ trắng/trùng, LOẠI phần tử CJK
    (marker không bao giờ chứa chữ Hán), trần 6 nghĩa như [MAX_ALTERNATIVES]."""
    from . import alternatives  # import lỏng — tránh vòng phụ thuộc khi start

    out: list[str] = []
    for value in values:
        item = str(value).strip()
        if not item or alternatives.has_cjk(item):
            continue  # phòng thủ: không nhận phần tử chứa chữ Hán/dấu CJK
        if "{" in item or "}" in item or "|" in item or "\r" in item or "\n" in item:
            raise ValueError("Nghĩa không được chứa { } | hoặc xuống dòng")
        if item not in out:
            out.append(item)
    return out[:6]


class WordChoiceIn(BaseModel):
    """POST /stories/{id}/word-choices — `{ sourceKey?, chosenText, meanings? }`.

    Client gửi **danh sách nghĩa của marker** ([meanings]) thay vì khóa chữ
    Trung; backend tra ngược khóa từ điển (mọi khóa có marker trùng danh sách
    nghĩa) và lưu cho tất cả. [source_key] giữ nguyên cho client cũ / dữ liệu
    marker cũ (khóa vẫn parse được nội bộ). Cần ít nhất 1 trong 2.
    """

    model_config = ConfigDict(populate_by_name=True)

    source_key: str | None = Field(default=None, alias="sourceKey", max_length=200)
    chosen_text: str = Field(alias="chosenText", min_length=1, max_length=200)
    meanings: list[str] | None = Field(default=None)

    @field_validator("source_key")
    @classmethod
    def _check_source_key(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            raise ValueError("sourceKey không được để trống")
        if any(ch in value for ch in "{}|=\r\n"):
            raise ValueError("sourceKey không được chứa { } = | hoặc xuống dòng")
        return value

    @field_validator("meanings")
    @classmethod
    def _check_meanings(cls, value: list[str] | None) -> list[str] | None:
        return _clean_meanings_field(value) if value is not None else None

    @model_validator(mode="after")
    def _need_key_or_meanings(self) -> "WordChoiceIn":
        if not self.source_key and not self.meanings:
            raise ValueError("Cần gửi sourceKey hoặc meanings")
        return self

    @field_validator("chosen_text")
    @classmethod
    def _check_chosen_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("chosenText không được để trống")
        if "{" in value or "}" in value:
            raise ValueError("chosenText không được chứa dấu { hoặc } (dấu marker)")
        if "\r" in value or "\n" in value:
            raise ValueError("chosenText không được xuống dòng")
        return value


class WordChoiceOut(BaseModel):
    """GET /stories/{id}/word-choices — một nghĩa đã lưu theo truyện."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    source_key: str = Field(alias="sourceKey")
    chosen_text: str = Field(alias="chosenText")
    created_at: datetime = Field(alias="createdAt")


class WordChoiceSavedOut(WordChoiceOut):
    """Phản hồi POST — thêm [affected_ids]: MỌI khóa đã ghi (nhiều khóa có
    cùng danh sách nghĩa → lưu cho tất cả; client dùng để hoàn tác).

    GET vẫn dùng [WordChoiceOut] (không thêm trường). Client cũ bỏ qua
    trường thừa này.
    """

    affected_ids: list[int] = Field(default_factory=list, alias="affectedIds")


class IgnoredWordIn(BaseModel):
    """POST /stories/{id}/ignored-words — `{ sourceKey?, meanings? }` (không hỏi lại).

    Tương tự [WordChoiceIn]: client gửi danh sách nghĩa của marker, backend
    tra ngược khóa (mọi khóa trùng danh sách nghĩa); `sourceKey` cho client cũ.
    """

    model_config = ConfigDict(populate_by_name=True)

    source_key: str | None = Field(default=None, alias="sourceKey", max_length=200)
    meanings: list[str] | None = Field(default=None)

    @field_validator("source_key")
    @classmethod
    def _check_source_key(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        if not value:
            raise ValueError("sourceKey không được để trống")
        if any(ch in value for ch in "{}|=\r\n"):
            raise ValueError("sourceKey không được chứa { } = | hoặc xuống dòng")
        return value

    @field_validator("meanings")
    @classmethod
    def _check_meanings(cls, value: list[str] | None) -> list[str] | None:
        return _clean_meanings_field(value) if value is not None else None

    @model_validator(mode="after")
    def _need_key_or_meanings(self) -> "IgnoredWordIn":
        if not self.source_key and not self.meanings:
            raise ValueError("Cần gửi sourceKey hoặc meanings")
        return self


class IgnoredWordOut(BaseModel):
    """GET /stories/{id}/ignored-words — một khóa đã bỏ hỏi theo truyện."""

    model_config = ConfigDict(populate_by_name=True)

    id: int
    source_key: str = Field(alias="sourceKey")
    created_at: datetime = Field(alias="createdAt")


class IgnoredWordSavedOut(IgnoredWordOut):
    """Phản hồi POST — thêm [affected_ids]: mọi khóa đã ghi (xem [WordChoiceSavedOut])."""

    affected_ids: list[int] = Field(default_factory=list, alias="affectedIds")


class MarkRuleOut(BaseModel):
    """GET /me/mark-rules — quy tắc học từ hành vi (UserMarkRules).

    ``skipCount`` = số lượt bỏ qua đã tích luỹ lúc quy tắc được sinh
    (hiển thị ở màn Quy tắc để người đăng biết vì sao khoá này hết hỏi).

    ``meanings`` = nghĩa tiếng Việt của khoá (tra từ từ điển) — màn Quy tắc
    hiển thị NGHĨA thay cho khoá chữ Trung (``sourceKey`` vẫn trả về cho
    client cũ/đối chiếu, không hiển thị).
    """

    model_config = ConfigDict(populate_by_name=True)

    id: int
    source_key: str = Field(alias="sourceKey")
    skip_count: int = Field(alias="skipCount")
    created_at: datetime = Field(alias="createdAt")
    meanings: list[str] | None = Field(default=None)
