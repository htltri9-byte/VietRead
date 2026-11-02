"""API nhập truyện từ link: POST /imports, GET /imports/{jobId} (Phần B, Bước 10).

App chỉ tạo job và poll trạng thái; việc cào + dịch chạy nền ở
`app.services.import_worker` (C4). Truyện nhập về là nháp (IsDraft=1) thuộc
người tạo job — hiển thị trong "Truyện của tôi" để chỉnh sửa trước khi đăng.
"""

from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from sqlalchemy.orm import Session

from .. import security
from ..database import get_db
from ..models import ImportJob, User
from ..schemas import ImportCreate, ImportJobOut
from ..services.import_worker import run_import_job

router = APIRouter(tags=["imports"])


def _job_out(job: ImportJob) -> ImportJobOut:
    return ImportJobOut(
        jobId=job.id,
        status=job.status,
        progress=job.progress,
        storyId=job.story_id,
        error=job.error,
    )


@router.post("/imports", response_model=ImportJobOut)
def create_import(
    payload: ImportCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ImportJobOut:
    """Tạo import job (Pending) rồi chạy nền — trả `{ jobId }` để client poll.

    Nguồn không hỗ trợ / link sai không chặn request: worker sẽ ghi rõ
    lỗi vào `error` và chuyển job sang Failed (C4).
    """
    job = ImportJob(
        user_id=user.id,
        source_url=payload.source_url,
        target_lang=payload.target_lang,
        status="Pending",
        progress=0,
    )
    db.add(job)
    db.commit()
    db.refresh(job)

    background_tasks.add_task(run_import_job, job.id)
    return _job_out(job)


@router.get("/imports/{job_id}", response_model=ImportJobOut)
def get_import(
    job_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(security.get_current_user),
) -> ImportJobOut:
    """Trạng thái job: { status, progress, storyId?, error? } — chỉ chủ job thấy."""
    job = db.get(ImportJob, job_id)
    if job is None or job.user_id != user.id:
        raise HTTPException(status_code=404, detail="Không tìm thấy import job")
    return _job_out(job)
