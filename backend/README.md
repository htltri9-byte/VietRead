# VietRead — Backend (FastAPI + SQL Server)

Đây là **Bước 1** của Lộ trình (Phần D): khởi tạo FastAPI, kết nối SQL Server,
`schema.sql` + `seed.sql` và API xác thực.

---

## 1. Yêu cầu máy

| Thành phần | Ghi chú |
|---|---|
| Python 3.10+ | Máy đang dùng Python 3.14 (tải tại python.org) |
| SQL Server Express/Developer | Máy này đã cài sẵn instance `MSSQLSERVER`, service đang chạy |
| ODBC Driver 18 for SQL Server | [Tải ODBC Driver](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server) (máy này đã cài cả bản 17 và 18) |
| Kích hoạt TCP/IP | SQL Server Configuration Manager → Protocols → bật **TCP/IP** (bắt buộc nếu app gọi từ điện thoại/máy khác) |

Kiểm tra driver đã thấy chưa:

```bash
python -c "import pyodbc; print(pyodbc.drivers())"
# phải có: 'ODBC Driver 18 for SQL Server'
```

---

## 2. Tạo CSDL (schema.sql + seed.sql)

**Cách A — SSMS:** mở `database/schema.sql` → F5, rồi mở `database/seed.sql` → F5.

**Cách B — sqlcmd (từ thư mục `backend/`):**

```bash
sqlcmd -S localhost -E -C -b -f 65001 -i database/schema.sql
sqlcmd -S localhost -E -C -b -f 65001 -i database/seed.sql
```

- `-E` = Windows Authentication; nếu dùng tài khoản SQL Server thì thay bằng `-U sa -P <matkhau>`.
- `-f 65001` = đọc file UTF-8 (tiếng Việt trong seed).
- `seed.sql` chạy lại được: nếu đã có dữ liệu mẫu thì nó tự bỏ qua.

Làm lại từ đầu (chỉ khi chắc chắn, sẽ xoá toàn bộ dữ liệu):

```bash
sqlcmd -S localhost -E -C -Q "ALTER DATABASE VietRead SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE VietRead;"
```

---

## 3. Cấu hình `.env`

```bash
cd backend
cp .env.example .env      # Windows: copy .env.example .env
```

Hai cách nối SQL Server (đặt vào `DATABASE_URL`):

- **Windows Authentication (khuyến nghị khi chạy cục bộ trên chính máy có SQL Server):**

  ```
  DATABASE_URL=mssql+pyodbc://./VietRead?trusted_connection=yes&driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes
  ```

- **SQL Server Authentication (đúng định dạng đề bài):**

  ```
  DATABASE_URL=mssql+pyodbc://<user>:<pass>@<server>/<database>?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes
  ```

Ngoài ra: `SECRET_KEY` (chuỗi bí mật ký JWT — đổi thành chuỗi ngẫu nhiên), `ALGORITHM`,
`ACCESS_TOKEN_EXPIRE_MINUTES` (mặc định 10080 phút = 7 ngày), `CORS_ORIGINS`.
File `.env` **không commit lên git** (đã thêm vào `.gitignore`).

---

## 4. Cài đặt & chạy server

```bash
cd backend
python -m venv .venv                 # nếu `python` báo lỗi trên WindowsApps thì dùng: py -m venv .venv
.venv\Scripts\activate               # PowerShell; bash: source .venv/Scripts/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

- Swagger (test tương tác): http://127.0.0.1:8000/docs
- Kiểm tra server + kết nối DB: http://127.0.0.1:8000/health → `{"status":"ok","database":"connected"}`

> Máy này đã có sẵn venv tại `backend/.venv`, nên chạy thẳng được:
> `backend/.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000`

---

## 5. API Bước 1

| Method | Path | Body | Thành công | Lỗi |
|---|---|---|---|---|
| POST | `/auth/register` | `{ name, email, password }` | `200 { token, user }` | `400` email đã dùng / dữ liệu sai |
| POST | `/auth/login` | `{ email, password }` | `200 { token, user }` | `401` sai thông tin |
| GET | `/auth/me` | header `Authorization: Bearer <token>` | `200 { id, name, email, avatarUrl }` | `401` thiếu/sai token |

Mọi lỗi trả về dạng `{ "message": "..." }` (xem [Phần B của đề bài](../VietRead_prompt.md)).
Email được chuẩn hoá: bỏ khoảng trắng + viết thường; mật khẩu băm bằng bcrypt (`$2b$12$...`),
không lưu mật khẩu gốc. `password` tối thiểu 6 ký tự.

### Test bằng curl (PowerShell dùng `curl.exe`, Git Bash dùng `curl`)

```bash
# 1) Đăng ký
curl -s -X POST http://127.0.0.1:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Nguyễn Văn A","email":"a.nguyen@vietread.vn","password":"matkhau123"}'

# 2) Đăng nhập (lấy token)
curl -s -X POST http://127.0.0.1:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"tacgia@vietread.vn","password":"VietRead@123"}'

# 3) Dùng token (thay <TOKEN> bằng giá trị trả về ở bước 2)
curl -s http://127.0.0.1:8000/auth/me -H "Authorization: Bearer <TOKEN>"

# 4) Kiểm tra lỗi
curl -s -i -X POST http://127.0.0.1:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"tacgia@vietread.vn","password":"sai-mat-khau"}'     # → 401 {"message":"Email hoặc mật khẩu không đúng"}
```

Ngoài ra có thể test trực tiếp trên http://127.0.0.1:8000/docs (nhấn **Try it out**).

### Tài khoản mẫu (tạo bởi seed.sql)

| Email | Mật khẩu | Vai trò |
|---|---|---|
| `tacgia@vietread.vn` | `VietRead@123` | tác giả, có 4 truyện |
| `docgia@vietread.vn` | `VietRead@123` | độc giả, có theo dõi + bình luận |

---

## 6. API Bước 2 (stories / chapters / genres)

| Method | Path | Query / body | Ghi chú |
|---|---|---|---|
| GET | `/genres` | – | `[{ id, name }]` |
| GET | `/stories` | `query, genre, status, sort, page, pageSize` | mảng `[Story]`, chỉ truyện đã đăng |
| GET | `/me/stories` | – | truyện của mình **kể cả nháp**, mới nhất trước; cần token (thêm ở Bước 9) |
| GET | `/stories/{id}` | – | `Story`; truyện nháp chỉ chủ nhân xem được (khách → 404) |
| POST | `/stories` | `{ title, description?, coverUrl?, status?, genres[], isDraft? }` | cần token; `genres` là **tên thể loại**, chưa có sẽ tự tạo |
| PUT | `/stories/{id}` | trường nào gửi lên thì trường đó sửa | chỉ tác giả (khác → 403) |
| DELETE | `/stories/{id}` | – | chỉ tác giả; DB tự xoá chương/bình luận/follows/thể loại |
| GET | `/stories/{id}/chapters` | `page, pageSize` | `[ChapterSummary]` (không kèm content) |
| POST | `/stories/{id}/chapters` | `{ title, content, index? }` | bỏ `index` → tự đánh số tiếp; trùng index → 400 |
| GET | `/chapters/{id}` | – | `Chapter` (kèm `content`) |
| PUT | `/chapters/{id}` | `{ title?, content?, index? }` | chỉ tác giả |
| DELETE | `/chapters/{id}` | – | chỉ tác giả; tự xoá bình luận của chương đó |
| POST | `/imports` | `{ sourceUrl, targetLang? }` | cần token → `{ jobId, status, ... }`; chạy nền bằng `BackgroundTasks` (Bước 10) |
| GET | `/imports/{jobId}` | – | `{ status, progress, storyId?, error? }` — Pending/Running/Done/Failed + % chương; chỉ chủ job (khác → 404) |

- `status`: `ongoing` (đang ra) \| `completed` (hoàn thành) — sai → 400.
- `sort`: `newest` (mới, mặc định) \| `hot` (nhiều theo dõi) \| `rating` (điểm) \| `title` — sai → 400. Nhận cả `mới`, `điểm`.
- `query` tìm theo **tên truyện hoặc tên tác giả**; `genre` lọc theo tên thể loại.
- `pageSize` mặc định 12 (truyện) / 50 (chương), tối đa 100 / 200.
- Model `Story` trả về: `{ id, title, author, authorId, coverUrl, description, genres[], status, rating, chapterCount, isDraft, updatedAt }` — `genres` là mảng tên thể loại; `authorId` + `isDraft` là trường thêm ngoài Phần B, phục vụ Bước 9/10.
- **Bước 10 (nhập truyện từ link)**: worker nằm ở `app/services/` — `scraper.py`
  (adapter theo domain: Qidian / B.faloo / Fanqie + nguồn demo
  `demo.vietread.local` fixture không cần mạng), `translator.py` (dịch theo đoạn,
  chuỗi endpoint dự phòng — endpoint lỗi ≥2 lần tự tạm nghỉ rồi tự quay lại
  (5 phút với lỗi thường, hết quota thì nghỉ tới đúng lúc API báo hồi — tối đa
  12 giờ; không cần restart); lỗi dịch luôn nêu rõ tên endpoint + lý do +
  thời điểm hồi quota), `import_worker.py` (Pending → Running → Done/Failed,
  truyện nhập là nháp IsDraft=1). Cấu hình trong `.env`: `TRANSLATE_MODE`
  (`dict` mặc định = dịch offline bằng từ điển `app/vietphrase.py` +
  `dictionaries/`, không cần mạng/key; `online` / `auto` = API dịch như cũ),
  `TRANSLATE_API_KEY` (tuỳ chọn), `TRANSLATE_EMAIL` (tăng quota MyMemory, tuỳ chọn),
  `IMPORT_CHAPTER_DELAY`, `IMPORT_MAX_CHAPTERS` (xem `.env.example`).
  Thêm tên riêng cho từ điển khi đang chạy: `POST /dictionary/names {"zh","vi"}`
- Trạng thái nguồn thật (kiểm tra live): **Qidian** ✅ — adapter rewrite
  `www.qidian.com` (bị anti-bot HTTP 202) về `m.qidian.com` + lấy catalog đủ
  chương, chương VIP → Failed "nội dung trả phí"; **Fanqie** ⚠️ — nội dung mã hoá
  font anti-scrape (ký tự PUA) → Failed "chưa giải mã được"; **Faloo** ⚠️ — trang
  chương yêu cầu đăng nhập → Failed "cần đăng nhập"; `demo.vietread.local` ✅ —
  fixture không cần mạng (dùng cho test/demo).

Ví dụ:

```bash
# Nên dùng -G --data-urlencode để curl tự mã hoá tiếng Việt
curl -s -G http://127.0.0.1:8000/stories --data-urlencode "genre=Tiên Hiệp" --data-urlencode "sort=rating"
curl -s -G http://127.0.0.1:8000/stories --data-urlencode "query=Kiếm Sư" --data-urlencode "pageSize=2"
curl -s http://127.0.0.1:8000/genres
curl -s http://127.0.0.1:8000/stories/1/chapters
curl -s http://127.0.0.1:8000/chapters/1

# Tạo truyện (cần token — lấy từ /auth/login)
curl -s -X POST http://127.0.0.1:8000/stories \
  -H "Content-Type: application/json" -H "Authorization: Bearer <TOKEN>" \
  -d '{"title":"Truyện Của Tôi","status":"ongoing","genres":["Đô Thị"]}'
```

### Test tự động (chạy hết Bước 1 + Bước 2 + `GET /me/stories` (Bước 9) + `/imports` (Bước 10))

```bash
cd backend
.venv/Scripts/python.exe test_api.py        # Windows
.venv/bin/python test_api.py                # Linux/macOS
```

Chạy xong in `TẤT CẢ 116 KIỂM TRA ĐỀU PASS` (exit code 0); script tự tạo và tự xoá dữ liệu kiểm thử.

> Trong đó check import bản demo (`job → Done`) cần có mạng để gọi API dịch;
> các check còn lại chạy được offline.

> Windows: nếu chạy qua pipe (`| tail`) mà bị `UnicodeEncodeError` (cp1252), thêm
> `PYTHONUTF8=1` phía trước lệnh python.

---

## 7. Lỗi thường gặp

| Triệu chứng | Nguyên nhân / cách xử lý |
|---|---|
| `Can't open lib 'ODBC Driver 18 for SQL Server'` | Chưa cài ODBC Driver 18, hoặc cung cấp sai tên driver trong `DATABASE_URL` |
| `/health` trả `503` | Service SQL Server dừng → chạy `services.msc` → bật `SQL Server (MSSQLSERVER)` |
| `Login failed for user` | Sai user/pass ở Cách 2 → kiểm tra lại, hoặc chuyển sang Windows Authentication |
| Không kết nối từ điện thoại | Chưa bật TCP/IP, firewall chặn cổng 1433, hoặc `API_BASE_URL` sai IP (emulator: `10.0.2.2`) |
| `Thiếu biến DATABASE_URL` | Chưa tạo `backend/.env` (xem mục 3) |

---

## 8. Cấu trúc thư mục (Bước 1 + 2)

```
backend/
  app/
    main.py        # khởi tạo FastAPI, CORS, handler lỗi {message}, nạp router
    database.py    # engine, SessionLocal, get_db(), ping_database()
    models.py      # ORM 8 bảng (Users, Stories, Genres, StoryGenres, Chapters, Comments, Follows, ImportJobs)
    schemas.py     # Pydantic: auth + StoryOut/ChapterOut/GenreOut + request tạo/sửa
    security.py    # bcrypt + JWT + get_current_user / get_current_user_optional
    routers/
      auth.py      # POST /auth/register, /auth/login, GET /auth/me
      stories.py   # GET/POST/PUT/DELETE /stories (+ tìm kiếm, lọc, sort, phân trang)
      chapters.py  # /stories/{id}/chapters + /chapters/{id}
      genres.py    # GET /genres
  database/schema.sql, seed.sql
  test_api.py      # script test tự động toàn bộ API Bước 1 + 2
  requirements.txt, .env.example, README.md
```

**Tiếp theo (Bước 3 của Lộ trình):** Flutter — khởi tạo project, theme sáng/tối, floating bottom nav, điều hướng.
