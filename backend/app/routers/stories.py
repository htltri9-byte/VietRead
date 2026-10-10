"""API truyện: GET/POST/PUT/DELETE /stories (Phần B của đề bài).

Quy tắc:
- Danh sách công khai chỉ chứa truyện đã đăng (IsDraft = 0).
- Truyện nháp chỉ chủ nhân xem được (trả 404 cho người khác).
- Sửa/xoá chỉ tác giả (403 nếu không phải).
"""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import delete as sa_delete
from sqlalchemy import false, func, or_, select
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..models import Chapter, Follow, Genre, Story, StoryGenre, User
from ..schemas import StoryCreate, StoryOut, StoryUpdate

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


def get_story_or_404(db: Session, story_id: int, viewer: User | None) -> Story:
    """Lấy truyện theo id; không tồn tại hoặc là nháp của người khác → 404."""
    story = db.get(Story, story_id)
    if story is None or (story.is_draft and (viewer is None or viewer.id != story.author_id)):
        raise HTTPException(status_code=404, detail="Không tìm thấy truyện")
    return story


def require_owner(story: Story, user: User) -> None:
    """Chỉ tác giả được sửa/xoá truyện của mình."""
    if story.author_id != user.id:
        raise HTTPException(status_code=403, detail="Bạn không có quyền thao tác trên truyện này")


def story_outs(db: Session, stories: list[Story]) -> list[StoryOut]:
    """Ghép truyện với tên tác giả, danh sách thể loại, số chương (không N+1)."""
    if not stories:
        return []
    ids = [s.id for s in stories]
    authors = dict(
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
            author=authors.get(s.author_id, ""),
            authorId=s.author_id,
            coverUrl=s.cover_url,
            description=s.description,
            genres=genres.get(s.id, []),
            status=s.status,
            rating=float(s.rating or 0),
            chapterCount=int(counts.get(s.id, 0)),
            isDraft=s.is_draft,
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
    """Danh sách truyện đã đăng (không gồm nháp), có tìm kiếm/lọc/sắp xếp/phân trang."""
    stmt = select(Story).where(Story.is_draft == false())

    if query and query.strip():
        pattern = f"%{query.strip()}%"
        stmt = stmt.join(User, User.id == Story.author_id).where(
            or_(Story.title.ilike(pattern), User.name.ilike(pattern))
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
    """Tạo truyện mới (tác giả là người đang đăng nhập)."""
    story = Story(
        author_id=user.id,
        title=payload.title,
        description=payload.description,
        cover_url=payload.cover_url,
        status=payload.status,
        is_draft=payload.is_draft,
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
    if "status" in data:
        if payload.status not in _STATUSES:
            raise HTTPException(status_code=400, detail="Trạng thái phải là 'ongoing' hoặc 'completed'")
        story.status = payload.status
    if "is_draft" in data:
        if payload.is_draft is None:
            raise HTTPException(status_code=400, detail="isDraft phải là true/false")
        story.is_draft = payload.is_draft
    if "genres" in data:
        _replace_genres(db, story.id, payload.genres or [])
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
