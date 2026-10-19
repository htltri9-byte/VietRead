"""Điểm vào của backend VietRead — FastAPI + SQL Server."""

from __future__ import annotations

import os

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import database
from .routers import (
    auth,
    chapter_import,
    chapters,
    comments,
    dictionary,
    follows,
    genres,
    glossary,
    imports,
    markers,
    stories,
)

app = FastAPI(
    title="VietRead API",
    description="REST API cho ứng dụng đọc truyện chữ VietRead (Flutter + FastAPI + SQL Server).",
    version="0.1.0",
)

# --- CORS: cho phép app Flutter/website gọi API từ trình duyệt -----------------
_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "*").split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=_origins != ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Mọi lỗi trả về dạng { "message": "..." } theo Phần B ---------------------
@app.exception_handler(StarletteHTTPException)
def http_error_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    """Chuẩn hóa lỗi HTTP (400/401/403/404/...) về { message }."""
    return JSONResponse(
        status_code=exc.status_code,
        content={"message": str(exc.detail)},
    )


@app.exception_handler(RequestValidationError)
def validation_error_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    """Lỗi validate Pydantic → 400 kèm thông báo tiếng Việt."""
    first = exc.errors()[0] if exc.errors() else {}
    loc = ".".join(str(part) for part in first.get("loc", []) if part != "body")
    msg = first.get("msg", "Dữ liệu không hợp lệ")
    detail = f"{loc}: {msg}" if loc else msg
    return JSONResponse(status_code=400, content={"message": f"Dữ liệu không hợp lệ — {detail}"})


# --- Router --------------------------------------------------------------------
app.include_router(auth.router)
app.include_router(stories.router)
app.include_router(chapters.router)
app.include_router(chapter_import.router)
app.include_router(genres.router)
app.include_router(follows.router)
app.include_router(comments.router)
app.include_router(imports.router)
app.include_router(dictionary.router)
app.include_router(glossary.router)
app.include_router(markers.router)


# --- Endpoint kiểm tra nhanh ----------------------------------------------------
@app.get("/", tags=["meta"])
def root() -> dict:
    """Trang chủ API — chỉ để biết server đã chạy."""
    return {"name": "VietRead API", "version": app.version, "docs": "/docs"}


@app.get("/health", tags=["meta"])
def health() -> JSONResponse:
    """Kiểm tra kết nối SQL Server: 200 nếu nối được, 503 nếu không."""
    try:
        database.ping_database()
    except Exception as exc:  # noqa: BLE001 — muốn trả về thông báo lỗi cụ thể
        return JSONResponse(
            status_code=503,
            content={"message": f"Không kết nối được SQL Server: {exc}"},
        )
    return JSONResponse(status_code=200, content={"status": "ok", "database": "connected"})
