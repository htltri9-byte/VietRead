"""Schema Pydantic validate request / định dạng response JSON (Phần B)."""

from __future__ import annotations

from datetime import datetime
from urllib.parse import urlparse

from pydantic import BaseModel, ConfigDict, Field, field_validator


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
