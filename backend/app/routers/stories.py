"""API truyện: GET/POST/PUT/DELETE /stories (Phần B của đề bài).

Quy tắc:
- Danh sách công khai chỉ chứa truyện ĐÃ DUYỆT (ModerationStatus = 'approved').
- Truyện chưa duyệt (draft/pending/rejected) chỉ chủ nhân và Admin xem được
  (trả 404 cho người khác) — điều kiện dùng chung ở moderation.can_view.
- Sửa/xoá chỉ tác giả (403 nếu không phải).
- "Đăng công khai" cũ (PUT isDraft=false) → 400 hướng dẫn dùng POST /submit;
  POST /stories/{id}/submit + POST /stories/{id}/unpublish là luồng mới.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete as sa_delete
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..moderation import (
    can_view,
    ensure_transition,
    set_status,
)
from ..models import Chapter, Follow, Genre, Story, StoryGenre, User
from ..schemas import StoryCreate, StoryOut, StorySubmitIn, StoryUpdate

router = APIRouter(tags=["stories"])

STORY_PAGE_SIZE = 12  # lưới 2 cột trên trang chủ

_STATUSES = ("ongoing", "completed")
# Nhận cả tên tiếng Việt / viết tắt cho tham số sort
_SORT_KEYS = {
    "newest": "newest", "new": "newest", "updated": "newest",
    "moi": "newest", "mới": "newest",
    "hot": "hot", "noibat": "hot", "nổi bật": "hot",
    "rating": "rating", "point": "rating", "diem": "rating", "điểm": "rating",
    "title": "title", "name": "title", "tentruyen": "title", "tên truyện": "title",
}
# Số lượt theo dõi — dùng để xếp hạng "hot"
_follow_count = (
    select(func.count()).where(Follow.story_id == Story.id).correlate(Story).scalar_subquery()
)
_ORDERS = {
    "newest": (Story.updated_at.desc(), Story.id.desc()),
    "hot": (_follow_count.desc(), Story.updated_at.desc()),
    "rating": (Story.rating.desc(), Story.updated_at.desc()),
    "title": (Story.title.asc(), Story.id.asc()),
}


def utc_now() -> datetime:
    """Thời gian UTC kiểu naive, khớp DATETIME2 lưu SYSUTCDATETIME()."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _submit_validation_errors(db: Session, story: Story) -> list[str]:
    """Điều kiện gửi duyệt — trả về danh sách lý do thiếu (rỗng = đạt)."""
    errors: list[str] = []
    if not (story.title and story.title.strip()):
        errors.append("truyện cần có tên")
    if not (story.description and story.description.strip()):
        errors.append("truyện cần có mô tả")
    genre_count = db.execute(
        select(func.count()).where(StoryGenre.story_id == story.id)
    ).scalar()
    if not genre_count:
        errors.append("truyện cần có ít nhất 1 thể loại")
    chapter_count = db.execute(
        select(func.count()).where(Chapter.story_id == story.id)
    ).scalar()
    if not chapter_count:
        errors.append("truyện cần có ít nhất 1 chương")
    return errors


def _submit_story(
    db: Session,
    story: Story,
    user: User,
    payload: StorySubmitIn | None = None,
) -> Story:
    """Chuyển truyện sang `pending` (dùng bởi POST /submit).

    Điều kiện: ≥ 1 chương, có tên/mô tả/thể loại, và `confirmRights = true`.
    Thiếu → 400 kèm lý do. Chuyển không hợp lệ (đã pending/approved) → 409.
    """
    if payload is not None and not payload.confirm_rights:
        raise HTTPException(
            status_code=400,
            detail="Cần xác nhận 'Tôi là tác giả hoặc có quyền đăng nội dung này' (confirmRights)",
        )
    errors = _submit_validation_errors(db, story)
    if errors:
        raise HTTPException(status_code=400, detail="Chưa đủ điều kiện gửi duyệt: " + "; ".join(errors))
    ensure_transition(story.moderation_status, "pending")
    set_status(
        story,
        "pending",
        submitted_at=utc_now(),
        clear_reject_reason=True,
    )
    story.updated_at = utc_now()
    db.commit()
    db.refresh(story)
    return story


def get_story_or_404(db: Session, story_id: int, viewer: User | None) -> Story:
    """Lấy truyện theo id cho endpoint NGƯỜI ĐỌC; không tồn tại hoặc chưa được
    duyệt mà không phải chủ/admin → 404.

    Điều kiện hiển thị dùng chung ở [app.moderation.can_view] — mọi router người
    đọc (stories, chapters, comments, follows) đi qua hàm này nên không rải
    điều kiện lặp.
    """
    story = db.get(Story, story_id)
    if story is None or not can_view(story, viewer):
        raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
    return story


def require_owner(story: Story, user: User) -> None:
    """Chỉ tác giả được sửa/xoá truyện của mình."""
    if story.author_id != user.id:
        raise HTTPException(status_code=403, detail="Bạn không có quyền thao tác trên truyện này")


def get_owned_story(db: Session, story_id: int, user: User) -> Story:
    """Lấy truyện để thao tác của CHỦ truyện: không tồn tại → 404, khác chủ → 403.

    Dùng chung cho mọi endpoint sửa/thêm/xoá theo truyện (chapters,
    chapter_import, glossary, markers) — trước đây bị nhân bản ở 4 router.
    """
    story = db.get(Story, story_id)
    if story is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
    require_owner(story, user)
    return story


def story_outs(db: Session, stories: list[Story]) -> list[StoryOut]:
    """Ghép truyện với tên người đăng, tác giả gốc, thể loại, số chương (không N+1).

    `authorId`/`Users` join = NGƯỜI ĐĂNG; `OriginalAuthor` = TÁC GIẢ nguyên tác.
    `author` (tương thích) = originalAuthor hoặc fallback uploaderName.
    """
    if not stories:
        return []
    ids = [s.id for s in stories]
    uploaders = dict(
        db.execute(select(User.id, User.name).where(User.id.in_({s.author_id for s in stories}))).all()
    )
    genre_rows = db.execute(
        select(StoryGenre.story_id, Genre.name)
        .join(Genre, Genre.id == StoryGenre.genre_id)
        .where(StoryGenre.story_id.in_(ids))
        .order_by(Genre.name)
    ).all()
    genres: dict[int, list[str]] = defaultdict(list)
    for story_id, name in genre_rows:
        genres[story_id].append(name)
    counts = dict(
        db.execute(
            select(Chapter.story_id, func.count())
            .where(Chapter.story_id.in_(ids))
            .group_by(Chapter.story_id)
        ).all()
    )
    return [
        StoryOut(
            id=s.id,
            title=s.title,
            # TRƯỜNG TƯƠNG THÍCH cho bản Flutter cũ: tác giả gốc nếu có,
            # không thì tên người đăng (đúng nghĩa trước đây của `author`).
            author=(s.original_author or uploaders.get(s.author_id, "")),
            authorId=s.author_id,
            originalAuthor=s.original_author,
            uploaderName=uploaders.get(s.author_id, ""),
            coverUrl=s.cover_url,
            description=s.description,
            genres=genres.get(s.id, []),
            status=s.status,
            rating=float(s.rating or 0),
            chapterCount=int(counts.get(s.id, 0)),
            isDraft=s.is_draft,
            moderationStatus=s.moderation_status,
            rejectReason=s.reject_reason,
            needsRecheck=s.needs_recheck,
            submittedAt=s.submitted_at,
            scanStatus=s.scan_status,
            updatedAt=s.updated_at,
        )
        for s in stories
    ]


def _replace_genres(db: Session, story_id: int, names: list[str]) -> None:
    """Đổi danh sách thể loại của truyện; thể loại chưa có thì tạo mới."""
    db.execute(sa_delete(StoryGenre).where(StoryGenre.story_id == story_id))
    for name in names:
        genre = db.execute(select(Genre).where(Genre.name == name)).scalar_one_or_none()
        if genre is None:
            genre = Genre(name=name)
            db.add(genre)
            db.flush()  # lấy genre.id
        db.add(StoryGenre(story_id=story_id, genre_id=genre.id))


@router.get("/stories", response_model=list[StoryOut])
def list_stories(
    db: Session = Depends(get_db),
    query: str | None = Query(default=None, description="Tìm theo tên truyện hoặc tên tác giả"),
    genre: str | None = Query(default=None, description="Lọc theo tên thể loại"),
    status: str | None = Query(default=None, description="ongoing | completed"),
    sort: str = Query(default="newest", description="newest | hot | rating | title"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=STORY_PAGE_SIZE, ge=1, le=100, alias="pageSize"),
) -> list[StoryOut]:
    """Danh sách truyện CÔNG KHAI — chỉ truyện đã duyệt (approved). Có tìm kiếm/
    lọc/sắp xếp/phân trang."""
    stmt = select(Story).where(Story.moderation_status == "approved")

    if query and query.strip():
        pattern = f"%{query.strip()}%"
        # Tìm theo tên truyện, tên tác giả nguyên tác HOẶC tên người đăng
        # (không mất kết quả cũ — trước đây tìm theo tên người đăng qua Users).
        stmt = stmt.outerjoin(User, User.id == Story.author_id).where(
            or_(
                Story.title.ilike(pattern),
                Story.original_author.ilike(pattern),
                User.name.ilike(pattern),
            )
        )

    if genre and genre.strip():
        stmt = stmt.where(
            Story.id.in_(
                select(StoryGenre.story_id)
                .join(Genre, Genre.id == StoryGenre.genre_id)
                .where(Genre.name == genre.strip())
            )
        )

    if status and status.strip():
        key = status.strip().lower()
        if key not in _STATUSES:
            raise HTTPException(status_code=400, detail="Trạng thái phải là 'ongoing' hoặc 'completed'")
        stmt = stmt.where(Story.status == key)

    sort_key = _SORT_KEYS.get((sort or "newest").strip().lower())
    if sort_key is None:
        raise HTTPException(
            status_code=400, detail="Giá trị sort không hợp lệ (newest | hot | rating | title)"
        )

    stmt = (
        stmt.order_by(*_ORDERS[sort_key])
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    return story_outs(db, list(db.execute(stmt).scalars().all()))


@router.get("/me/stories", response_model=list[StoryOut])
def list_my_stories(
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> list[StoryOut]:
    """Truyện của người đang đăng nhập, **kể cả nháp** — màn Đăng truyện (Bước 9).

    Danh sách công khai `GET /stories` luôn loại nháp nên cần endpoint riêng.
    """
    rows = (
        db.execute(
            select(Story)
            .where(Story.author_id == user.id)
            .order_by(Story.updated_at.desc(), Story.id.desc())
        )
        .scalars()
        .all()
    )
    return story_outs(db, list(rows))


@router.get("/stories/{story_id}", response_model=StoryOut)
def get_story(
    story_id: int,
    db: Session = Depends(get_db),
    viewer: User | None = Depends(security.get_current_user_optional),
) -> StoryOut:
    """Chi tiết một truyện (nháp chỉ chủ nhân xem được)."""
    story = get_story_or_404(db, story_id, viewer)
    return story_outs(db, [story])[0]


@router.post("/stories", response_model=StoryOut)
def create_story(
    payload: StoryCreate,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> StoryOut:
    """Tạo truyện mới (người đăng là người đang đăng nhập; tác giả gốc tuỳ chọn).

    Luôn tạo ở trạng thái **draft** — truyện chỉ công khai sau khi Admin duyệt
    (bấm "Gửi duyệt" → POST /stories/{id}/submit). Trường `isDraft` được nhận
    để tương thích client cũ nhưng không còn ý nghĩa "công khai ngay".
    """
    story = Story(
        author_id=user.id,
        title=payload.title,
        description=payload.description,
        cover_url=payload.cover_url,
        status=payload.status,
        is_draft=True,          # đồng bộ với ModerationStatus='draft'
        moderation_status="draft",
        original_author=payload.original_author,
    )
    db.add(story)
    db.flush()
    _replace_genres(db, story.id, payload.genres)
    db.commit()
    db.refresh(story)
    return story_outs(db, [story])[0]


@router.put("/stories/{story_id}", response_model=StoryOut)
def update_story(
    story_id: int,
    payload: StoryUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> StoryOut:
    """Sửa truyện (chỉ tác giả); trường nào không gửi thì giữ nguyên."""
    story = db.get(Story, story_id)
    if story is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
    require_owner(story, user)

    data = payload.model_dump(exclude_unset=True)
    if "title" in data:
        if not payload.title:
            raise HTTPException(status_code=400, detail="Tên truyện không được để trống")
        story.title = payload.title
    if "description" in data:
        story.description = payload.description
    if "cover_url" in data:
        story.cover_url = payload.cover_url
    if "original_author" in data:
        # None/rỗng → xoá tác giả (NULL); chuỗi bình thường → lưu đã trim
        story.original_author = payload.original_author
    if "status" in data:
        if payload.status not in _STATUSES:
            raise HTTPException(status_code=400, detail="Trạng thái phải là 'ongoing' hoặc 'completed'")
        story.status = payload.status
    if "is_draft" in data:
        if payload.is_draft is None:
            raise HTTPException(status_code=400, detail="isDraft phải là true/false")
        if payload.is_draft:
            # Client cũ gửi isDraft=true nghĩa là "không công khai" — nếu truyện
            # đang approved thì đây là GỠ XUỐNG (approved → draft); trạng thái
            # khác đã không công khai rồi → giữ nguyên (không phá luồng sửa
            # truyện pending/rejected bằng PUT nhiều trường).
            if story.moderation_status == "approved":
                ensure_transition(story.moderation_status, "draft")
                set_status(story, "draft")
        elif story.moderation_status == "approved":
            pass  # đã công khai rồi — idempotent, không 409
        else:
            # "Đăng công khai" cũ (client cũ PUT isDraft=false) → trả 400 hướng
            # dẫn dùng endpoint submit mới (response vẫn dạng { message } nên
            # Flutter cũ hiện lỗi đúng cách, không vỡ). Không tự chuyển trạng
            # thái vì client cũ KHÔNG gửi confirmRights.
            raise HTTPException(
                status_code=400,
                detail=(
                    "Truyện cần được Admin duyệt trước khi công khai — dùng "
                    "POST /stories/{id}/submit với { \"confirmRights\": true }"
                ),
            )
    if "genres" in data:
        _replace_genres(db, story.id, payload.genres or [])
    story.updated_at = utc_now()
    db.commit()
    db.refresh(story)
    return story_outs(db, [story])[0]


@router.post("/stories/{story_id}/submit", response_model=StoryOut)
def submit_story(
    story_id: int,
    payload: StorySubmitIn,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> StoryOut:
    """Chủ truyện GỬI DUYỆT: draft/rejected → pending.

    Body: `{ confirmRights: true }` — xác nhận quyền đăng nội dung.
    Thiếu điều kiện → 400 kèm lý do; chuyển không hợp lệ → 409.
    """
    story = get_owned_story(db, story_id, user)
    story = _submit_story(db, story, user, payload)
    return story_outs(db, [story])[0]


@router.post("/stories/{story_id}/unpublish", response_model=StoryOut)
def unpublish_story(
    story_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> StoryOut:
    """Chủ truyện GỠ XUỐNG: approved → draft (truyện biến mất khỏi app công khai)."""
    story = get_owned_story(db, story_id, user)
    ensure_transition(story.moderation_status, "draft")
    set_status(story, "draft")
    story.updated_at = utc_now()
    db.commit()
    db.refresh(story)
    return story_outs(db, [story])[0]


@router.delete("/stories/{story_id}")
def delete_story(
    story_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> dict:
    """Xoá truyện (chỉ tác giả). DB tự xoá chapters/comments/follows thể loại kèm theo."""
    story = db.get(Story, story_id)
    if story is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
    require_owner(story, user)
    db.delete(story)
    db.commit()
    return {"message": "Đã xoá truyện"}
