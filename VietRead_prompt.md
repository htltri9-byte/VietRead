# VAI TRÒ
Bạn là Senior Full-stack Developer (Flutter + Python). Hãy xây dựng hệ thống "VietRead" gồm:
- **Ứng dụng Android (Flutter)**: đọc và đăng truyện chữ, có tính năng nhập truyện từ link nguồn nước ngoài và tự động dịch sang tiếng Việt.
- **Backend (Python/FastAPI + SQL Server)**: cung cấp REST API JSON cho ứng dụng.

Đây là đồ án môn Lập trình trên thiết bị di động. Giảng viên yêu cầu dùng SQL Server làm CSDL.

---

# PHẦN A. ỨNG DỤNG FLUTTER

## A1. Công nghệ
- Flutter (Dart, null-safety), chỉ build Android (minSdk 24).
- Gọi API: package `http`. Dùng Future/FutureBuilder hoặc Provider cho state.
- Lưu cục bộ trên điện thoại: `sqflite` (truyện/chương tải offline, lịch sử đọc), `shared_preferences` (token, cài đặt đọc: cỡ chữ, font, nền, chế độ sáng/tối). Lưu ý: SQLite chỉ để dùng offline trên máy, CSDL chính nằm ở SQL Server phía backend.
- Ảnh: `cached_network_image`. Đường dẫn file: `path_provider`.
- Ngôn ngữ giao diện: Tiếng Việt.

## A2. Phong cách giao diện (khác biệt, không sao chép app tham khảo)
- Chủ đề "Mực & Giấy": nền kem giấy (#FAF6EE), card trắng ngà, bo góc 16px, viền mảnh thay vì đổ bóng nặng.
- Màu chính: xanh ngọc đậm #1F6F6B; màu nhấn: san hô #FF6B57; chữ: #23201C.
- Chế độ tối: nền #14181A, giữ màu nhấn.
- Font: tiêu đề/UI dùng sans-serif (Be Vietnam Pro); nội dung chương dùng serif (Noto Serif) để dễ đọc.
- Bottom navigation dạng viên thuốc nổi (floating pill), 4 mục: Khám phá, Tủ sách, Đăng truyện, Tài khoản. Mục đang chọn là pill màu xanh ngọc kèm nhãn.
- Trang chủ gồm:
  1) Header chào người dùng + ô tìm kiếm bo tròn,
  2) Thẻ lớn "Đọc tiếp" (truyện đang đọc dở, thanh tiến độ),
  3) Chip thể loại cuộn ngang,
  4) Mục "Đang hot" dạng lưới 2 cột (bìa dọc, tên, tác giả, số chương, điểm),
  5) Mục "Mới cập nhật" dạng danh sách ngang kèm thời gian cập nhật.
- Có skeleton loading, trạng thái rỗng, trạng thái lỗi kèm nút "Thử lại".

## A3. Chức năng & màn hình
1. **Đăng ký / Đăng nhập** (email + mật khẩu), giữ đăng nhập bằng token trong shared_preferences. Chưa đăng nhập vẫn đọc được, nhưng bình luận/đăng truyện/theo dõi phải đăng nhập.
2. **Khám phá (trang chủ)** như mô tả ở A2.
3. **Tìm kiếm & lọc**: theo tên/tác giả, thể loại, trạng thái (đang ra/hoàn thành), sắp xếp (mới, hot, điểm).
4. **Chi tiết truyện**: bìa, tên, tác giả, thể loại, mô tả, điểm, trạng thái, danh sách chương (phân trang), nút Đọc/Đọc tiếp, Theo dõi, Tải offline, tab Bình luận.
5. **Màn hình đọc**: nội dung chương, chuyển chương trước/sau, tuỳ chỉnh cỡ chữ – font – nền (sáng/tối/sepia) – giãn dòng, tự lưu tiến độ đọc, hiển thị tiến độ %.
6. **Bình luận**: xem, gửi, xoá bình luận của mình (theo truyện, có thể theo chương).
7. **Tủ sách**: tab Theo dõi | Lịch sử | Đã tải. Lịch sử hiển thị "Chương N – Tên chương", nút "…" (menu) và "×" (xoá). Tab Đã tải đọc được khi mất mạng.
8. **Tải offline**: tải toàn bộ/một khoảng chương vào SQLite, hiển thị tiến trình, xoá để giải phóng bộ nhớ.
9. **Đăng truyện (tác giả)**: tạo/sửa/xoá truyện (tên, mô tả, thể loại, ảnh bìa), thêm/sửa/xoá chương.
10. **Nhập truyện từ link**: người dùng dán link (Qidian, B.faloo, Fanqie…) → chọn ngôn ngữ đích (Tiếng Việt) → gửi yêu cầu tạo "import job" lên server → màn hình theo dõi trạng thái (Pending/Running/Done/Failed, % chương) → khi xong, truyện xuất hiện trong "Truyện của tôi" ở dạng nháp để chỉnh sửa trước khi đăng. Việc cào và dịch thực hiện ở BACKEND, app chỉ gọi API và poll trạng thái.
11. **Tài khoản**: avatar, tên hiển thị, truyện của tôi, cài đặt (giao diện, cỡ chữ mặc định), đăng xuất.

## A4. SQLite cục bộ (trên điện thoại)
- downloaded_stories(id, title, author, coverPath, description)
- downloaded_chapters(id, storyId, idx, title, content)
- reading_history(storyId, chapterIndex, chapterTitle, progress, updatedAt)

## A5. Cấu trúc project Flutter
```
lib/
  models/      (story, chapter, comment, user, import_job)
  services/    (api_service.dart, auth_service.dart, db_helper.dart, prefs_service.dart)
  providers/   hoặc controllers/
  screens/     (auth, home, search, story_detail, reader, library, upload, import, profile)
  widgets/     (story_card, chip_genre, floating_nav, skeleton, empty_state, error_state)
  theme/       (app_theme.dart – light & dark)
```

## A6. Yêu cầu code Flutter
- Dùng dữ liệu mock trước (MockApiService) rồi dễ chuyển sang API thật bằng đổi 1 cờ cấu hình.
- Mỗi model có `factory fromJson()` và `toJson()` (serialize/deserialize như Bài 6).
- Bắt mọi lỗi mạng (try/catch, timeout), hiển thị thông báo thân thiện bằng tiếng Việt.
- Không hard-code màu/size trong widget, lấy từ theme.
- Code có comment tiếng Việt ngắn gọn ở các hàm chính.
- README: cách chạy, cấu hình `API_BASE_URL` (emulator dùng `10.0.2.2`, máy thật dùng IP LAN của máy chạy backend).

---

# PHẦN B. API (REST + JSON)
Base URL: `[API_BASE_URL]`. Header: `Authorization: Bearer <token>`.
Mọi response lỗi: `{ "message": "..." }` kèm mã HTTP 400/401/403/404/429.

- POST /auth/register, POST /auth/login → `{ token, user }`
- GET /stories?query=&genre=&status=&sort=&page= → `[Story]`
- GET /stories/{id} → `Story`
- POST /stories, PUT /stories/{id}, DELETE /stories/{id}
- GET /stories/{id}/chapters?page= → `[ChapterSummary]`
- GET /chapters/{id} → `Chapter` (có content)
- POST/PUT/DELETE chương: /stories/{id}/chapters, /chapters/{id}
- GET/POST /stories/{id}/comments, DELETE /comments/{id}
- POST /follows/{storyId}, DELETE /follows/{storyId}, GET /me/follows
- POST /imports `{ sourceUrl, targetLang }` → `{ jobId }`
- GET /imports/{jobId} → `{ status, progress, storyId?, error? }`

Model JSON mẫu:
- Story: `{ id, title, author, coverUrl, description, genres[], status, rating, chapterCount, updatedAt }`
- ChapterSummary: `{ id, storyId, index, title, updatedAt }`
- Chapter: `{ id, storyId, index, title, content }`
- Comment: `{ id, storyId, chapterId?, userId, userName, avatarUrl?, content, createdAt }`
- User: `{ id, name, email, avatarUrl? }`

---

# PHẦN C. BACKEND PYTHON + SQL SERVER

## C1. Công nghệ
- Framework: FastAPI + Uvicorn.
- CSDL: Microsoft SQL Server (bản Express/Developer). Kết nối bằng SQLAlchemy + pyodbc, chuỗi kết nối:
  `mssql+pyodbc://<user>:<pass>@<server>/<database>?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes`
- Chuỗi kết nối đặt trong `.env` (DATABASE_URL), không commit lên git.
- Xác thực: JWT (python-jose), băm mật khẩu bằng passlib/bcrypt.
- Validate bằng Pydantic; response đúng cấu trúc JSON ở Phần B. Bật CORS, tài liệu tự sinh tại /docs.

## C2. Bảng CSDL (SQL Server)
- Users(Id, Name, Email UNIQUE, PasswordHash, AvatarUrl, CreatedAt)
- Stories(Id, AuthorId→Users, Title, Description, CoverUrl, Status, Rating, SourceUrl NULL, IsDraft, CreatedAt, UpdatedAt)
- Genres(Id, Name UNIQUE)
- StoryGenres(StoryId→Stories, GenreId→Genres) — khoá chính kép
- Chapters(Id, StoryId→Stories, ChapterIndex, Title, Content NVARCHAR(MAX), OriginalContent NVARCHAR(MAX) NULL, CreatedAt, UpdatedAt) — UNIQUE(StoryId, ChapterIndex)
- Comments(Id, StoryId→Stories, ChapterId→Chapters NULL, UserId→Users, Content, CreatedAt)
- Follows(UserId→Users, StoryId→Stories, CreatedAt) — khoá chính kép
- ImportJobs(Id, UserId→Users, SourceUrl, TargetLang, Status, Progress, StoryId→Stories NULL, Error NULL, CreatedAt, UpdatedAt)

Quy tắc:
- Dùng NVARCHAR/NVARCHAR(MAX) cho mọi chuỗi (hỗ trợ tiếng Việt và tiếng Trung), DATETIME2 cho thời gian.
- Xoá Story thì xoá Chapters, Comments, Follows liên quan (ON DELETE CASCADE hoặc xử lý trong code).
- Viết sẵn `database/schema.sql` (T-SQL: CREATE DATABASE, CREATE TABLE, khoá chính/ngoại, index) và `database/seed.sql` (vài truyện, chương, thể loại mẫu) để chạy trực tiếp trong SSMS.

## C3. Cấu trúc backend
```
backend/
  app/main.py, app/database.py (engine, session), app/models.py, app/schemas.py
  app/routers/   (auth, stories, chapters, comments, follows, imports)
  app/services/  (scraper.py, translator.py, import_worker.py)
  database/schema.sql, database/seed.sql
  requirements.txt  (fastapi, uvicorn, sqlalchemy, pyodbc, python-jose, passlib[bcrypt], httpx, python-dotenv)
  .env.example
  README.md  (cài ODBC Driver 18, bật TCP/IP cho SQL Server, tạo DB, chạy server)
```

## C4. Import & dịch tự động
- POST /imports tạo ImportJob (Pending) rồi chạy nền bằng FastAPI BackgroundTasks.
- Worker: lấy thông tin truyện + danh sách chương từ link → với mỗi chương: tải nội dung → dịch theo từng đoạn (chunk) → lưu Chapters (Content = bản dịch, OriginalContent = bản gốc) → cập nhật Progress.
- Mỗi nguồn (Qidian, B.faloo, Fanqie…) là một adapter riêng cùng interface `parse_story(url)` / `parse_chapter(url)` để dễ thêm nguồn mới.
- Có retry, delay giữa các request; lỗi thì Status = Failed kèm Error rõ ràng (nguồn chặn, link không hợp lệ).
- Truyện import mặc định IsDraft = 1, thuộc về người dùng đã import.
- Khoá API dịch (`TRANSLATE_API_KEY`) đặt trong `.env`.

---

# PHẦN D. LỘ TRÌNH (làm tuần tự, mỗi bước phải chạy được)
1. Backend: khởi tạo FastAPI, kết nối SQL Server, schema.sql + seed.sql, API auth.
2. Backend: API stories, chapters, genres.
3. Flutter: khởi tạo project, theme sáng/tối, floating bottom nav, điều hướng.
4. Flutter: models + ApiService (mock) + Trang Khám phá.
5. Flutter: chi tiết truyện + màn hình đọc + lưu tiến độ.
6. Flutter: đăng nhập/đăng ký + token; chuyển từ mock sang API thật.
7. Flutter: tủ sách (theo dõi, lịch sử) + SQLite + tải offline.
8. Tìm kiếm & lọc; bình luận (backend + Flutter).
9. Đăng truyện (CRUD truyện/chương).
10. Nhập truyện từ link + theo dõi import job (backend worker + Flutter).
11. Hoàn thiện: skeleton, empty/error state, kiểm thử các luồng chính, viết README.

# GHI CHÚ
- Tính năng import chỉ phục vụ demo kỹ thuật cho đồ án; bản dịch lưu riêng cho người dùng, không công khai nội dung có bản quyền.
- Nếu thiếu thông tin (tên miền/IP server, API dịch, tài khoản SQL Server), hãy dùng giá trị giữ chỗ trong `.env.example` và ghi rõ trong README thay vì tự giả định.
