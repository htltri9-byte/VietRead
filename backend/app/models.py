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
    # Vai trò: 'user' | 'admin' — admin xét duyệt truyện (tools/create_admin.py)
    role: Mapped[str] = mapped_column(
        "Role", Unicode(20), nullable=False, default="user"
    )
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
    # TÁC GIẢ nguyên tác — tên hiển thị (Hán-Việt/ghi tay); NULL = chưa rõ.
    # Khác AuthorId: AuthorId là NGƯỜI ĐĂNG (tài khoản VietRead).
    original_author: Mapped[str | None] = mapped_column(
        "OriginalAuthor", Unicode(200), nullable=True
    )
    # Tên gốc chữ Trung của tác giả (lấy được từ nguồn, vd Qidian)
    original_author_raw: Mapped[str | None] = mapped_column(
        "OriginalAuthorRaw", Unicode(200), nullable=True
    )
    is_draft: Mapped[bool] = mapped_column("IsDraft", Boolean, nullable=False, default=False)
    # --- Kiểm duyệt trước khi công khai (migrate_moderation.sql) ------------
    # draft | pending | approved | rejected.
    # QUY TẮC NHẤT QUÁN: is_draft = False CHỈ khi moderation_status = 'approved'
    # — mọi thao tác chuyển trạng thái đều đi qua helpers của routers/moderation.py.
    moderation_status: Mapped[str] = mapped_column(
        "ModerationStatus", Unicode(20), nullable=False, default="draft"
    )
    reject_reason: Mapped[str | None] = mapped_column(
        "RejectReason", Unicode(1000), nullable=True
    )
    submitted_at: Mapped[datetime | None] = mapped_column("SubmittedAt", DateTime, nullable=True)
    reviewed_at: Mapped[datetime | None] = mapped_column("ReviewedAt", DateTime, nullable=True)
    reviewed_by: Mapped[int | None] = mapped_column(
        "ReviewedBy", Integer, ForeignKey("Users.Id"), nullable=True
    )
    # Truyện approved nhưng chủ truyện sửa/thêm chương → Admin nên xem lại
    needs_recheck: Mapped[bool] = mapped_column(
        "NeedsRecheck", Boolean, nullable=False, default=False
    )
    # Chỗ dành cho dịch vụ quét tự động sau này (chỉ tạo cột, chưa dùng):
    # none | clean | flagged | error; ScanSummary = JSON kết quả
    scan_status: Mapped[str | None] = mapped_column("ScanStatus", Unicode(20), nullable=True)
    scan_summary: Mapped[str | None] = mapped_column("ScanSummary", UnicodeText, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )
    updated_at: Mapped[datetime] = mapped_column(
        "UpdatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class ModerationLog(Base):
    """Lịch sử kiểm duyệt: mỗi lần Admin duyệt/từ chối/gỡ truyện là một dòng."""

    __tablename__ = "ModerationLog"

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"), nullable=False, index=True
    )
    admin_id: Mapped[int] = mapped_column(
        "AdminId", Integer, ForeignKey("Users.Id"), nullable=False
    )
    # 'approve' | 'reject' | 'unpublish'
    action: Mapped[str] = mapped_column("Action", Unicode(20), nullable=False)
    reason: Mapped[str | None] = mapped_column("Reason", Unicode(1000), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
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


class StoryGlossary(Base):
    """Quy tắc "Tìm & thay thế" riêng của MỘT truyện (chỉ tác giả thao tác).

    `ApplyToFuture=1` → tự áp dụng cho chương thêm sau này của truyện đó.
    Xoá truyện thì xoá kèm (ON DELETE CASCADE).
    """

    __tablename__ = "StoryGlossary"

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    find_text: Mapped[str] = mapped_column("FindText", Unicode(200), nullable=False)
    replace_text: Mapped[str] = mapped_column("ReplaceText", Unicode(200), nullable=False)
    match_case: Mapped[bool] = mapped_column(
        "MatchCase", Boolean, nullable=False, default=False
    )
    whole_word: Mapped[bool] = mapped_column(
        "WholeWord", Boolean, nullable=False, default=False
    )
    apply_to_future: Mapped[bool] = mapped_column(
        "ApplyToFuture", Boolean, nullable=False, default=True
    )
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class ChapterRevision(Base):
    """Snapshot chương TRƯỚC một lần tìm & thay thế — để hoàn tác batch gần nhất.

    Mỗi truyện giữ tối đa 1 batch: batch mới xoá batch cũ. `CreatedAt` là mốc
    thời gian của batch — chương nào `UpdatedAt > CreatedAt` nghĩa là đã bị sửa
    tiếp sau batch → bỏ qua khi hoàn tác (giống ghi chú FK trong schema.sql).
    """

    __tablename__ = "ChapterRevisions"

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    # FK ChapterId cố tình KHÔNG cascade (giống Comments) — xoá chương thì xoá
    # revision trong code để không tạo 2 đường cascade từ Stories.
    chapter_id: Mapped[int] = mapped_column(
        "ChapterId", Integer, ForeignKey("Chapters.Id"), nullable=False, index=True
    )
    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    title: Mapped[str] = mapped_column("Title", Unicode(255), nullable=False)
    content: Mapped[str] = mapped_column("Content", UnicodeText, nullable=False)
    batch_id: Mapped[str] = mapped_column("BatchId", Unicode(36), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class DictionaryWord(Base):
    """Từ điển cá nhân — mỗi từ người dùng thêm qua POST /dictionary/names.

    Từ điển dịch thật vẫn nằm trong `dictionaries/names.txt` (vietphrase nạp
    vào bộ nhớ); bảng này là sổ theo dõi để app liệt kê / xoá từ của mình.
    """

    __tablename__ = "DictionaryWords"
    __table_args__ = (
        UniqueConstraint("UserId", "Zh", name="UQ_DictionaryWords_UserId_Zh"),
    )

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        "UserId", Integer, ForeignKey("Users.Id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    zh: Mapped[str] = mapped_column("Zh", Unicode(100), nullable=False)
    vi: Mapped[str] = mapped_column("Vi", Unicode(200), nullable=False)
    # Tags tuỳ chọn ("tên riêng, sư huynh") — phân cách bằng dấu phẩy
    tags: Mapped[str | None] = mapped_column("Tags", Unicode(200), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class StoryWordChoice(Base):
    """""Luôn dùng nghĩa này cho truyện này" — khóa Trung → nghĩa đã chọn.

    Người đăng chọn nghĩa trong sheet marker của bộ truyện này; lần dịch sau
    của TRUYỆN NÀY tự dùng nghĩa đó (không tạo marker). Khóa chung với
    `StoryIgnoredWords` nhưng cột khác chức năng. Xoá truyện → xoá kèm.
    """

    __tablename__ = "StoryWordChoices"
    __table_args__ = (
        UniqueConstraint("StoryId", "SourceKey", name="UQ_StoryWordChoices_StoryId_SourceKey"),
    )

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    source_key: Mapped[str] = mapped_column("SourceKey", Unicode(200), nullable=False)
    chosen_text: Mapped[str] = mapped_column("ChosenText", Unicode(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class StoryIgnoredWord(Base):
    """""Không hỏi lại từ này" — khóa bỏ marker của RIÊNG bộ truyện.

    Khác file chung `no_mark.txt` (toàn hệ thống): bảng này chỉ tác động tới
    bộ truyện sở hữu. Xoá truyện → xoá kèm.
    """

    __tablename__ = "StoryIgnoredWords"
    __table_args__ = (
        UniqueConstraint("StoryId", "SourceKey", name="UQ_StoryIgnoredWords_StoryId_SourceKey"),
    )

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    story_id: Mapped[int] = mapped_column(
        "StoryId", Integer, ForeignKey("Stories.Id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    source_key: Mapped[str] = mapped_column("SourceKey", Unicode(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
    )


class UserWordStat(Base):
    """Thống kê hành vi "không hỏi lại" của MỘT người dùng theo khóa.

    Mỗi lần người dùng bấm "Không hỏi lại từ này" (bất kỳ truyện nào) →
    ``SkipCount`` +1 cho khóa đó. Đủ ``LEARN_SKIP_THRESHOLD`` lần (env,
    mặc định 5; <=0 = tắt học) → ghi một ``UserMarkRule``: khóa không marker
    nữa ở MỌI truyện của người này. Unique (UserId, SourceKey) nên thống kê
    gộp mọi truyện. Xoá người dùng → xoá kèm.
    """

    __tablename__ = "UserWordStats"
    __table_args__ = (
        UniqueConstraint("UserId", "SourceKey", name="UQ_UserWordStats_UserId_SourceKey"),
    )

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        "UserId", Integer, ForeignKey("Users.Id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    source_key: Mapped[str] = mapped_column("SourceKey", Unicode(200), nullable=False)
    skip_count: Mapped[int] = mapped_column(
        "SkipCount", Integer, nullable=False, default=1
    )
    updated_at: Mapped[datetime] = mapped_column(
        "UpdatedAt", DateTime, nullable=False, server_default=_utc_now_db(),
        onupdate=_utc_now_db(),
    )


class UserMarkRule(Base):
    """Quy tắc học từ hành vi người đăng — khoá hết marker sau đủ lượt bỏ qua.

    Khác ``StoryIgnoredWords`` (theo truyện, bấm 1 lần là có hiệu lực ngay):
    quy tắc này của RIÊNG người dùng và áp cho mọi truyện; chỉ sinh ra khi
    ``UserWordStats.SkipCount`` chạm ``LEARN_SKIP_THRESHOLD``. Xoá quy tắc
    (màn Quy tắc) → marker trở lại. ``SkipCount`` lưu lúc học để hiển thị.
    """

    __tablename__ = "UserMarkRules"
    __table_args__ = (
        UniqueConstraint("UserId", "SourceKey", name="UQ_UserMarkRules_UserId_SourceKey"),
    )

    id: Mapped[int] = mapped_column("Id", Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(
        "UserId", Integer, ForeignKey("Users.Id", ondelete="CASCADE"),
        nullable=False, index=True,
    )
    source_key: Mapped[str] = mapped_column("SourceKey", Unicode(200), nullable=False)
    skip_count: Mapped[int] = mapped_column("SkipCount", Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(
        "CreatedAt", DateTime, nullable=False, server_default=_utc_now_db()
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
