"""Định nghĩa model ORM — khớp 1-1 với các bảng trong database/schema.sql.

Lưu ý: database/schema.sql là nguồn chuẩn của cấu trúc bảng (tạo bằng SSMS/sqlcmd);
file này chỉ mô tả lại để SQLAlchemy đọc/ghi dữ liệu.
"""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    UnicodeText,
    UniqueConstraint,
    Unicode,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


def _utc_now_db():
    """Mặc định thời gian ở DB (DATETIME2, UTC) — khớp DEFAULT trong schema.sql."""
    return func.sysutcdatetime()


class User(Base):
    """Người dùng (tác giả / độc giả)."""

    __tablename__ = "Users"

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column("Name", Unicode(100), nullable=False)
    email: Mapped[str] = mapped_column("Email", Unicode(255), nullable=False, unique=True)
    password_hash: Mapped[str] = mapped_column("PasswordHash", Unicode(255), nullable=False)
    avatar_url: Mapped[str | None] = mapped_column("AvatarUrl", Unicode(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class Story(Base):
    """Truyện (có thể là nháp IsDraft=1 khi vừa import xong)."""

    __tablename__ = "Stories"

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    author_id: Mapped[int] = mapped_column(
        "AuthorId", Integer, ForeignKey("Users.Id"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column("Title", Unicode(255), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column("Description", UnicodeText, nullable=True)
    cover_url: Mapped[str | None] = mapped_column("CoverUrl", Unicode(500), nullable=True)
    # 'ongoing' = đang ra, 'completed' = hoàn thành
    status: Mapped[str] = mapped_column("Status", Unicode(20), nullable=False, default="ongoing")
    rating: Mapped[Decimal] = mapped_column(
        "Rating", Numeric(3, 2), nullable=False, default=Decimal("0")
    )
    source_url: Mapped[str | None] = mapped_column("SourceUrl", Unicode(1000), nullable=True)
    # Mã truyện trên nguồn (vd: bookId Qidian) — NULL với truyện nhập trước migration
    source_book_id: Mapped[str | None] = mapped_column(
        "SourceBookId", Unicode(100), nullable=True
    )
    is_draft: Mapped[bool] = mapped_column("IsDraft", Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )
    updated_at: Mapped[datetime] = mapped_column(
        "UpdatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class Genre(Base):
    """Thể loại truyện."""

    __tablename__ = "Genres"

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column("Name", Unicode(100), nullable=False, unique=True)


class StoryGenre(Base):
    """Quan hệ nhiều-nhiều giữa truyện và thể loại (khoá chính kép)."""

    __tablename__ = "StoryGenres"

    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"), primary_key=True
    )
    genre_id: Mapped[int] = mapped_column(
        "GenreId", Integer, ForeignKey("Genres.Id", ondelete="CASCADE"), primary_key=True
    )


class Chapter(Base):
    """Chương của truyện; Content là bản dịch, OriginalContent là bản gốc."""

    __tablename__ = "Chapters"
    __table_args__ = (
        UniqueConstraint("StoryId", "ChapterIndex", name="UQ_Chapters_StoryId_ChapterIndex"),
    )

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"), nullable=False, index=True
    )
    chapter_index: Mapped[int] = mapped_column("ChapterIndex", Integer, nullable=False)
    title: Mapped[str] = mapped_column("Title", Unicode(255), nullable=False)
    content: Mapped[str] = mapped_column("Content", UnicodeText, nullable=False)
    original_content: Mapped[str | None] = mapped_column(
        "OriginalContent", UnicodeText, nullable=True
    )
    # Mã chương + link trên nguồn (vd: Qidian) — NULL với chương nhập trước migration.
    # Unique index lọc (StoryId, SourceChapterId) WHERE SourceChapterId IS NOT NULL
    # chặn cùng một chương được nhập 2 lần vào cùng truyện (xem migrate_source_tracking.sql).
    source_chapter_id: Mapped[str | None] = mapped_column(
        "SourceChapterId", Unicode(200), nullable=True
    )
    source_chapter_url: Mapped[str | None] = mapped_column(
        "SourceChapterUrl", Unicode(1000), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )
    updated_at: Mapped[datetime] = mapped_column(
        "UpdatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class Comment(Base):
    """Bình luận theo truyện, hoặc theo chương nếu ChapterId khác NULL."""

    __tablename__ = "Comments"

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"), nullable=False, index=True
    )
    # Xoá chương thì xoá comment bằng code (xem ghi chú trong schema.sql)
    chapter_id: Mapped[int | None] = mapped_column(
        "ChapterId", Integer, ForeignKey("Chapters.Id"), nullable=True
    )
    user_id: Mapped[int] = mapped_column(
        "UserId", Integer, ForeignKey("Users.Id", ondelete="CASCADE"), nullable=False, index=True
    )
    content: Mapped[str] = mapped_column("Content", UnicodeText, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class Follow(Base):
    """Người dùng theo dõi truyện (khoá chính kép)."""

    __tablename__ = "Follows"

    user_id: Mapped[int] = mapped_column(
        "UserId", Integer, ForeignKey("Users.Id", ondelete="CASCADE"), primary_key=True
    )
    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"), primary_key=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class ImportJob(Base):
    """Job nhập truyện từ link nước ngoài (Pending/Running/Done/Failed)."""

    __tablename__ = "ImportJobs"

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        "UserId", Integer, ForeignKey("Users.Id", ondelete="CASCADE"), nullable=False, index=True
    )
    source_url: Mapped[str] = mapped_column("SourceUrl", Unicode(1000), nullable=False)
    target_lang: Mapped[str] = mapped_column(
        "TargetLang", Unicode(20), nullable=False, default="vi"
    )
    status: Mapped[str] = mapped_column("Status", Unicode(20), nullable=False, default="Pending")
    progress: Mapped[int] = mapped_column("Progress", Integer, nullable=False, default=0)
    # SET NULL khi truyện bị xoá (job vẫn giữ lại để theo dõi)
    story_id: Mapped[int | None] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="SET NULL"), nullable=True
    )
    error: Mapped[str | None] = mapped_column("Error", UnicodeText, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )
    updated_at: Mapped[datetime] = mapped_column(
        "UpdatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )
