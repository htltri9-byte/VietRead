"""Kiểm duyệt truyện — trạng thái, quy tắc chuyển trạng thái, điều kiện hiển thị.

Trạng thái (ModerationStatus) và chuyển trạng thái hợp lệ:

    draft     → pending    (chủ truyện gửi duyệt: POST /stories/{id}/submit)
    pending   → approved   (Admin duyệt)
    pending   → rejected   (Admin từ chối, bắt buộc lý do)
    rejected  → pending    (chủ truyện sửa rồi gửi lại)
    approved  → draft      (chủ truyện hoặc Admin gỡ xuống)
    approved  → rejected   (Admin gỡ vì vi phạm, bắt buộc lý do)

Mọi chuyển khác trả 409.

ĐỒNG BỘ IsDraft ⇔ ModerationStatus (quy tắc duy nhất, không rải ở nơi khác):
    IsDraft = 0  ⇔  ModerationStatus = 'approved'
    trạng thái còn lại → IsDraft = 1
Mọi chỗ chuyển trạng thái đều gọi [set_status] nên hai cột không bao giờ lệch;
các câu lệnh cũ lọc "IsDraft = 0" vẫn chỉ thấy truyện đã duyệt.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import Depends, HTTPException
from sqlalchemy.orm import Session

from .models import ModerationLog, Story, User
from .security import get_current_user

MODERATION_STATUSES = ("draft", "pending", "approved", "rejected")

# Chuyển trạng thái hợp lệ — khóa là trạng thái hiện tại
VALID_TRANSITIONS: dict[str, set[str]] = {
    "draft": {"pending"},
    "pending": {"approved", "rejected"},
    "rejected": {"pending"},
    "approved": {"draft", "rejected"},
}


def utc_now() -> datetime:
    """Thời gian UTC kiểu naive, khớp DATETIME2 lưu SYSUTCDATETIME()."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def ensure_transition(current: str, target: str) -> None:
    """Chặn chuyển trạng thái không hợp lệ → 409 (dùng trong cùng transaction)."""
    if target not in VALID_TRANSITIONS.get(current, set()):
        raise HTTPException(
            status_code=409,
            detail=f"Không thể chuyển trạng thái '{current}' → '{target}'",
        )


def set_status(
    story: Story,
    status: str,
    *,
    submitted_at: datetime | None = None,
    reviewed_at: datetime | None = None,
    reviewed_by: int | None = None,
    reject_reason: str | None = None,
    clear_reject_reason: bool = False,
    needs_recheck: bool | None = None,
) -> None:
    """Chuyển trạng thái kiểm duyệt và GIỮ NHẤT QUÁN IsDraft (chưa commit).

    `reject_reason` = lý do mới khi từ chối; `clear_reject_reason=True` → xóa
    lý do cũ (khi gửi lại/duyệt); `needs_recheck` = None → giữ nguyên cờ.
    """
    story.moderation_status = status
    # Đồng bộ IsDraft: 0 CHỈ khi approved
    story.is_draft = status != "approved"
    if submitted_at is not None:
        story.submitted_at = submitted_at
    if reviewed_at is not None:
        story.reviewed_at = reviewed_at
    if reviewed_by is not None:
        story.reviewed_by = reviewed_by
    if clear_reject_reason:
        story.reject_reason = None
    if reject_reason is not None:
        story.reject_reason = reject_reason
    if needs_recheck is not None:
        story.needs_recheck = needs_recheck


def mark_needs_recheck(story: Story) -> None:
    """Đánh dấu truyện approved cần Admin xem lại sau khi chủ truyện sửa chương.

    Chỉ tác động tới truyện `approved`; truyện draft/pending/rejected giữ nguyên
    trạng thái (không có gì cần xem lại).
    """
    if story.moderation_status == "approved":
        story.needs_recheck = True


def can_view(story: Story, viewer: User | None) -> bool:
    """Điều kiện xem DUY NHẤT cho mọi endpoint người đọc (dùng ở get_story_or_404).

    - Truyện approved: ai cũng xem được.
    - Truyện chưa approved: chỉ chủ truyện và Admin.
    """
    if story.moderation_status == "approved":
        return True
    if viewer is None:
        return False
    return viewer.id == story.author_id or viewer.role == "admin"


def is_admin(user: User | None) -> bool:
    return user is not None and user.role == "admin"


def require_admin(
    user: User = Depends(get_current_user),
) -> User:
    """Dependency cho endpoint /admin/*: 401 khi chưa đăng nhập (get_current_user),
    403 khi đã đăng nhập nhưng không phải admin."""
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="Chỉ admin mới dùng được chức năng này")
    return user


def log_moderation(
    db: Session,
    story: Story,
    admin_id: int,
    action: str,
    reason: str | None = None,
) -> None:
    """Ghi lịch sử kiểm duyệt (gọi trong transaction hiện tại — commit cùng nơi)."""
    db.add(
        ModerationLog(
            story_id=story.id,
            admin_id=admin_id,
            action=action,  # 'approve' | 'reject' | 'unpublish'
            reason=reason,
        )
    )
