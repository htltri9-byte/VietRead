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

**Migration DB đã tồn tại (thêm cột theo dõi nguồn — idempotent, chạy lại an toàn):**

```bash
sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_source_tracking.sql
```

Thêm `Stories.SourceBookId`, `Chapters.SourceChapterId`, `Chapters.SourceChapterUrl`
+ unique index lọc `(StoryId, SourceChapterId) WHERE SourceChapterId IS NOT NULL`
(chống trùng chương khi thêm chương từ link Qidian). Dữ liệu cũ giữ nguyên
(cột mới đều NULL); DB tạo mới từ `schema.sql` đã có sẵn các cột này.

**Migration A3.12 — gợi ý nhiều nghĩa + tìm & thay thế + từ điển cá nhân
(idempotent, chạy lại an toàn):**

```bash
sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_glossary_revisions.sql
sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_dictionary_words.sql
```

- `StoryGlossary(Id, StoryId, FindText, ReplaceText, MatchCase, WholeWord,
  ApplyToFuture, CreatedAt)` — quy tắc "Tìm & thay thế" riêng của từng truyện
  (FK Stories, ON DELETE CASCADE).
- `ChapterRevisions(Id, ChapterId, StoryId, Title, Content, BatchId, CreatedAt)` —
  snapshot chương trước lần thay thế gần nhất của mỗi truyện (dùng cho
  `POST /stories/{id}/replace/undo`).
- `DictionaryWords(Id, UserId, Zh, Vi, Tags, CreatedAt)` — sổ theo dõi từ điển
  cá nhân (`POST/GET/DELETE /dictionary/names`); từ dịch thật vẫn nằm trong
  `dictionaries/names.txt`.

Endpoint mới: `POST /chapters/{id}/retranslate` (dịch lại có marker, không tự
lưu), `GET /chapters/{id}?raw=1` (bản thô có marker — chỉ chủ truyện),
`POST /stories/{id}/replace`, `POST /stories/{id}/replace/undo`,
`GET /stories/{id}/glossary`, `DELETE /stories/{id}/glossary/{ruleId}`,
`POST/GET/DELETE /dictionary/names`.

**Migration A3.13 — mức gợi ý nhiều nghĩa + nghĩa theo truyện (idempotent):**

```bash
sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_story_words.sql
```

- `StoryWordChoices(StoryId, SourceKey, ChosenText)` — "Luôn dùng nghĩa này"
  của riêng truyện; `StoryIgnoredWords(StoryId, SourceKey)` — "Không hỏi lại"
  của riêng truyện (khác file chung `no_mark.txt`).
- `.env` thêm `MARK_LEVEL=low|medium|high` — mức gợi ý mặc định (trần 15/40/∞);
  client ghi đè qua body `{ "markLevel": ... }` khi retranslate/import.
- 3 danh sách mới cạnh `vietphrase.txt`: `ambiguous.txt` (luôn đánh dấu),
  `no_mark.txt` (trợ từ/lượng từ — không đánh dấu), `synonyms.txt` (loại ở
  mức medium). Sửa file → tự nạp khi mtime đổi, hoặc
  `POST /dictionary/mark-lists/reload`.

Endpoint A3.13: `GET/POST/DELETE /stories/{id}/word-choices`,
`GET/POST/DELETE /stories/{id}/ignored-words` (`sourceKey` hoặc `meanings`),
`POST /dictionary/mark-lists/reload`.

Quy tắc học từ hành vi (`UserMarkRules`, bảng chung theo người dùng):
bỏ qua 1 từ đủ `LEARN_SKIP_THRESHOLD` (5) lượt → khóa hết marker ở mọi
truyện. `GET /me/mark-rules` trả kèm `meanings` (nghĩa tra từ từ điển) —
màn Quy tắc chỉ hiển thị nghĩa, không lộ khóa chữ Trung;
`DELETE /me/mark-rules/{ruleId}` xoá 1 quy tắc. Sửa từ điển xong gọi
`POST /dictionary/names/reload` để meanings mới nhất, không cần restart.

**Migration kiểm duyệt truyện (idempotent, chạy lại an toàn):**

```bash
sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_moderation.sql
```

- `Users.Role NVARCHAR(20) NOT NULL DEFAULT 'user'` (`user` | `admin`).
- `Stories`: `ModerationStatus` (`draft|pending|approved|rejected`),
  `RejectReason`, `SubmittedAt`, `ReviewedAt`, `ReviewedBy` (FK `Users`),
  `NeedsRecheck BIT DEFAULT 0`, `ScanStatus` (`none|clean|flagged|error`),
  `ScanSummary NVARCHAR(MAX)` (JSON — **chỉ tạo cột, chưa có logic quét**).
- Bảng `ModerationLog(Id, StoryId, AdminId, Action, Reason, CreatedAt)` ghi
  mỗi lần duyệt/từ chối/gỡ.
- **Chuyển dữ liệu cũ**: `IsDraft = 1` → `draft`; `IsDraft = 0` → `approved`
  (truyện đang công khai vẫn hiện sau migration).
- **Đồng bộ `IsDraft`**: `IsDraft = 0` ⇔ `ModerationStatus = 'approved'`,
  mọi endpoint sửa trạng thái đều đặt cả hai cột trong cùng một transaction
  (`set_status()` trong `app/moderation.py`) — cột cũ giữ lại để client cũ
  không vỡ.

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
| GET | `/auth/me` | header `Authorization: Bearer <token>` | `200 { id, name, email, avatarUrl, role }` | `401` thiếu/sai token |

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
| `admin@vietread.vn` | (mẫu trong `seed.sql`) | **admin** — dùng cho màn Kiểm duyệt |

> Tài khoản admin trong `seed.sql` chỉ phục vụ môi trường phát triển:
> **phải đổi mật khẩu (hoặc tạo lại bằng `tools/create_admin.py`) trước khi
> mở backend ra ngoài mạng.** Tài khoản admin thật nên tạo bằng script ở mục 9.

---

## 6. API Bước 2 (stories / chapters / genres)

| Method | Path | Query / body | Ghi chú |
|---|---|---|---|
| GET | `/genres` | – | `[{ id, name }]` |
| GET | `/stories` | `query, genre, status, sort, page, pageSize` | mảng `[Story]`, chỉ truyện đã đăng |
| GET | `/me/stories` | – | truyện của mình **kể cả nháp**, mới nhất trước; cần token (thêm ở Bước 9) |
| GET | `/stories/{id}` | – | `Story`; truyện nháp chỉ chủ nhân xem được (khách → 404) |
| POST | `/stories` | `{ title, description?, coverUrl?, status?, genres[], isDraft?, originalAuthor? }` | cần token; `genres` là **tên thể loại**, chưa có sẽ tự tạo; `originalAuthor` = tác giả nguyên tác (≤ 200 ký tự, rỗng → NULL) |
| PUT | `/stories/{id}` | trường nào gửi lên thì trường đó sửa | chỉ tác giả (khác → 403); gửi `originalAuthor` rỗng (`""`) để xoá tác giả |
| DELETE | `/stories/{id}` | – | chỉ tác giả; DB tự xoá chương/bình luận/follows/thể loại |
| GET | `/stories/{id}/chapters` | `page, pageSize` | `[ChapterSummary]` (không kèm content) |
| POST | `/stories/{id}/chapters` | `{ title, content, index? }` | bỏ `index` → tự đánh số tiếp; trùng index → 400 |
| GET | `/chapters/{id}` | – | `Chapter` (kèm `content`) |
| PUT | `/chapters/{id}` | `{ title?, content?, index? }` | chỉ tác giả |
| DELETE | `/chapters/{id}` | – | chỉ tác giả; tự xoá bình luận của chương đó |
| POST | `/imports` | `{ sourceUrl, targetLang? }` | cần token → `{ jobId, status, ... }`; chạy nền bằng `BackgroundTasks` (Bước 10) |
| GET | `/imports/{jobId}` | – | `{ status, progress, storyId?, error? }` — Pending/Running/Done/Failed + % chương; chỉ chủ job (khác → 404) |
| POST | `/stories/{id}/chapters/import` | `{ chapterUrl, chapterNo?, title? }` | **chỉ Qidian** + chỉ tác giả; cào 1 chương → dịch → trả `Chapter`; chạy đồng bộ trong request (~2s) |
| POST | `/stories/{id}/chapters/import-text` | `{ text, sourceLang: zh\|vi, chapterNo?, title? }` | dán văn bản; `vi` lưu nguyên, `zh` dịch rồi lưu bản gốc; text ≤ 100.000 ký tự |

- `status`: `ongoing` (đang ra) \| `completed` (hoàn thành) — sai → 400.
- `sort`: `newest` (mới, mặc định) \| `hot` (nhiều theo dõi) \| `rating` (điểm) \| `title` — sai → 400. Nhận cả `mới`, `điểm`.
- `query` tìm theo **tên truyện, tên tác giả (nguyên tác) hoặc tên người đăng**
  (không mất kết quả cũ — trước đây tìm theo tên người đăng qua `Users`);
  `genre` lọc theo tên thể loại.
- `pageSize` mặc định 12 (truyện) / 50 (chương), tối đa 100 / 200.
- Model `Story` trả về: `{ id, title, author, authorId, originalAuthor, uploaderName,
  coverUrl, description, genres[], status, rating, chapterCount, isDraft, updatedAt }`
  — `genres` là mảng tên thể loại; `authorId` + `isDraft` là trường thêm ngoài Phần B,
  phục vụ Bước 9/10.
- **TÁC GIẢ vs NGƯỜI ĐĂNG** (tách bạch 2 khái niệm):
  - `originalAuthor` — tác giả nguyên tác (người sáng tác truyện gốc; với truyện
    nhập từ Qidian là tác giả trên Qidian). `NULL` = chưa rõ → client hiện
    "Chưa rõ". Trữ trong cột `Stories.OriginalAuthor` (+ `OriginalAuthorRaw`
    giữ tên gốc chữ Trung khi đọc được từ nguồn).
  - `uploaderName` — tên hiển thị người đăng (tài khoản VietRead) — luôn join
    từ `Users`, không lưu trùng vào `Stories`.
  - `author` — **TRƯỜNG TƯƠNG THÍCH** cho bản Flutter cũ: bằng `originalAuthor`
    nếu có, không thì bằng `uploaderName`. Sẽ bỏ sau khi client cũ không còn
    dùng — Flutter mới dùng 2 trường phía trên, không đọc `author`.
  - Migration idempotent (đã chạy, không mất dữ liệu cũ — truyện cũ để
    `OriginalAuthor = NULL`):
    `sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_original_author.sql`
    (chạy lại vô hại; in số truyện còn NULL).
- **Bước 10 (nhập truyện từ link)**: worker nằm ở `app/services/` — `scraper.py`
  (adapter theo domain: Qidian + nguồn demo
  `demo.vietread.local` fixture không cần mạng), `translator.py` (dịch theo đoạn,
  chuỗi endpoint dự phòng — endpoint lỗi ≥2 lần tự tạm nghỉ rồi tự quay lại
  (5 phút với lỗi thường, hết quota thì nghỉ tới đúng lúc API báo hồi — tối đa
  12 giờ; không cần restart); lỗi dịch luôn nêu rõ tên endpoint + lý do +
  thời điểm hồi quota),  `import_worker.py` (Pending → Running → Done/Failed,
  truyện nhập là nháp IsDraft=1). Khi nhập cả bộ, worker đọc tên tác giả từ
  trang truyện (`parse_story`) rồi lưu `OriginalAuthorRaw` = tên gốc chữ Trung,
  `OriginalAuthor` = bản chuyển Hán-Việt viết hoa từng từ bằng từ điển offline
  (`convert_name`, `names.txt`/`hanviet.txt` — không dịch bằng dịch vụ online);
  không lấy được thì để NULL và job vẫn Done. Nguồn demo dùng fixture có sẵn
  (`演示作者` → `Diễn Kì Tác Người`). Cấu hình trong `.env`: `TRANSLATE_MODE`
  (`dict` mặc định = dịch offline bằng từ điển `app/vietphrase.py` +
  `dictionaries/` — kèm `vietphrase.txt` 679k cụm từ, `luatnhan.txt` 7.024
  mẫu `{0}` (Luật Nhân), `surnames.txt` 400 họ — không cần mạng/key; tiêu đề
  chương nhập tự bỏ tiền tố `第N章` `online` / `auto` = API dịch như cũ),
  `TRANSLATE_API_KEY` (tuỳ chọn), `TRANSLATE_EMAIL` (tăng quota MyMemory, tuỳ chọn),
  `IMPORT_CHAPTER_DELAY`, `IMPORT_MAX_CHAPTERS` (xem `.env.example`).
  Thêm tên riêng cho từ điển khi đang chạy: `POST /dictionary/names {"zh","vi"}`
- Trạng thái nguồn thật (kiểm tra live): **Qidian** ✅ — adapter rewrite
  `www.qidian.com` (bị anti-bot HTTP 202) về `m.qidian.com` + lấy catalog đủ
  chương, chương VIP → Failed "nội dung trả phí"; `demo.vietread.local` ✅ —
  fixture không cần mạng (dùng cho test/demo).
- **Thêm chương vào truyện đã có** (`app/routers/chapter_import.py`): chỉ chủ
  truyện (không tồn tại → 404, khác chủ → 403); link phải thuộc `qidian.com`
  (khác → 400 "Chỉ hỗ trợ thêm chương từ Qidian") và đúng định dạng chương
  `/chapter/{bookId}/{chapterId}/` (đã kiểm chứng thực tế trên `m.qidian.com`);
  tách `bookId`/`chapterId` để:
  - **chống nhầm truyện**: truyện đã có `SourceBookId` mà link khác bookId →
    400 "Link này thuộc truyện khác"; truyện chưa có thì ghi lại từ link;
  - **chống trùng**: `SourceChapterId` đã có trong truyện → 409 "Chương này đã
    được nhập (chương số N)" (unique index lọc ở DB chặn đồng thời);
  - **số chương**: `chapterNo` gửi lên → đọc `第N章` từ tiêu đề gốc → `MAX+1`;
    trùng số → 409. Chỉ THÊM, không sửa chương cũ; cập nhật `Stories.UpdatedAt`.
  - Lỗi phân biệt rõ: sai định dạng/domain/link truyện khác/VIP → 400; Qidian chặn
    hoặc cào rỗng → 502 (kèm HTTP status); hết quota/dịch lỗi → 503;
    traceback được log ra terminal uvicorn.

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

### Test tự động (chạy hết Bước 1 + Bước 2 + `GET /me/stories` (Bước 9) + `/imports` (Bước 10) + thêm chương (A3.11))

```bash
cd backend
.venv/Scripts/python.exe test_api.py        # Windows
.venv/bin/python test_api.py                # Linux/macOS
```

Chạy xong in `TẤT CẢ 314 KIỂM TRA ĐỀU PASS` (exit code 0); script tự tạo và tự xoá dữ liệu kiểm thử.

Bộ lọc marker riêng (không cần server): `test_marking.py` (80 kiểm tra)
và `test_alternatives.py` (55 kiểm tra) — cùng in `TẤT CẢ ... ĐỀU PASS`.
Golden test dịch (không cần server, khớp từng byte 3 mức low/medium/high):
`test_golden_translate.py` (10 kiểm tra, dữ liệu trong `tests_golden/`,
tái sinh bằng `_make_golden.py` khi đổi dữ liệu từ điển có chủ đích).

> Trong đó check import bản demo (`job → Done`) và check thêm chương bằng link
> Qidian thật cần có mạng (cào nguồn); các check còn lại chạy được offline
> (dịch dùng `TRANSLATE_MODE=dict` mặc định).

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

---

## 9. Kiểm duyệt truyện trước khi công khai (Admin)

Truyện chỉ hiện công khai khi `Stories.ModerationStatus = 'approved'`.

### Trạng thái & chuyển trạng thái

| Từ | Đến | Ai làm | Endpoint |
|---|---|---|---|
| `draft` | `pending` | chủ truyện | `POST /stories/{id}/submit` |
| `pending` | `approved` | admin | `POST /admin/stories/{id}/approve` |
| `pending` | `rejected` | admin | `POST /admin/stories/{id}/reject` |
| `rejected` | `pending` | chủ truyện | `POST /stories/{id}/submit` |
| `approved` | `draft` | chủ truyện / admin | `POST /stories/{id}/unpublish` |
| `approved` | `rejected` | admin (bắt buộc lý do) | `POST /admin/stories/{id}/reject` |

Mọi chuyển khác trả **409**; duyệt/từ chối kiểm tra trạng thái **trong cùng
transaction** nên hai Admin thao tác cùng lúc an toàn (người sau nhận 409).
`IsDraft` luôn đồng bộ (`approved` ⇔ `IsDraft = 0`) — xem mục 2.

### Endpoint chủ truyện

| Method | Path | Body / ghi chú |
|---|---|---|
| POST | `/stories/{id}/submit` | `{ "confirmRights": true }` — thiếu xác nhận hoặc thiếu tên/mô tả/thể loại/≥1 chương → **400** kèm lý do; chuyển `pending`, ghi `SubmittedAt`, xóa `RejectReason` |
| POST | `/stories/{id}/unpublish` | `approved → draft` (truyện biến mất khỏi app công khai) |
| POST | `/stories/{id}/chapters...` (thêm/sửa/xoá) | truyện `approved` → đặt `NeedsRecheck = 1` (vẫn hiển thị, Admin nên xem lại) |
| PUT | `/stories/{id}` | client cũ gửi `isDraft=false` ("Đăng công khai" cũ) → **400** hướng dẫn dùng `submit` (response vẫn `{message}` nên app cũ không vỡ); `isDraft=true` trên truyện approved = gỡ xuống |

### Endpoint Admin (cần `role = admin`; chưa đăng nhập 401, người thường 403)

| Method | Path | Ghi chú |
|---|---|---|
| GET | `/admin/stories?status=pending\|approved\|rejected\|draft\|recheck\|all&q=&page=&pageSize=` | tên, tác giả, số chương, `SubmittedAt`, `ModerationStatus`, `NeedsRecheck`, `ScanStatus`; mặc định chờ duyệt cũ nhất trước |
| GET | `/admin/stories/{id}` | thông tin + mô tả + thể loại + danh sách chương (xem trước khi chưa công khai) |
| GET | `/admin/chapters/{chapterId}` | nội dung **đã resolve marker** (không dấu `{}`) + `OriginalContent` |
| POST | `/admin/stories/{id}/approve` | `pending` hoặc `approved`+`NeedsRecheck` → `approved`; ghi `ReviewedAt`/`ReviewedBy`, xóa `NeedsRecheck`, ghi `ModerationLog` |
| POST | `/admin/stories/{id}/reject` | `{ "reason": "…" }` bắt buộc 5–1000 ký tự (thiếu → 400) — dùng cho cả gỡ truyện đã duyệt |
| GET | `/admin/stats` | số truyện theo từng trạng thái (badge "Chờ duyệt (N)") |

### Endpoint người đọc đã rà — chỉ trả truyện `approved`

Điều kiện dùng chung là `moderation.can_view()` / bộ lọc
`Story.moderation_status == 'approved'`:

- `GET /stories` — Khám phá, tìm kiếm `query`, lọc thể loại/trạng thái, sắp xếp,
  phân trang, đề cử (cùng 1 câu lệnh lọc).
- `GET /stories/{id}` — chi tiết; chưa duyệt → **404** với người ngoài, chủ truyện
  và Admin vẫn xem được.
- `GET /stories/{id}/chapters` — danh sách chương.
- `GET /chapters/{id}` — nội dung chương (kể cả khi tải offline).
- `GET|POST /stories/{id}/comments` — bình luận.
- `POST /follows`, `DELETE /follows/{storyId}`, `GET /me/follows` — theo dõi
  (danh sách lọc riêng những truyện approved).
- `GET /genres` — chỉ danh mục thể loại, không chứa truyện.
- `GET /me/stories` — trả đủ 4 trạng thái (chỉ chủ truyện), KHÔNG lọc để tác giả quản lý.
- Lịch sử đọc / tiến độ / tủ sách cục bộ: lưu ở máy, không qua endpoint.

### Tạo tài khoản Admin

```bash
cd backend
# nhận email/mật khẩu từ tham số hoặc biến môi trường (không hardcode):
./.venv/Scripts/python.exe tools/create_admin.py --email admin@vietread.vn --password '<MAT_KHAU_MANH>'
# hoặc: ADMIN_EMAIL=... ADMIN_PASSWORD=... ./.venv/Scripts/python.exe tools/create_admin.py
```

Script băm mật khẩu đúng cách hiện có của project (bcrypt) và đặt
`Users.Role = 'admin'`; chạy lại với email đã có → báo đã tồn tại (không ghi đè).

### Test tay nhanh

```bash
# migration (idempotent)
sqlcmd -S localhost -E -C -b -f 65001 -i database/migrate_moderation.sql
# toàn bộ test API (gồm kiểm duyệt: 409, 403, 400, 404, NeedsRecheck, 2 admin...)
cd backend && PYTHONUTF8=1 ./.venv/Scripts/python.exe test_api.py   # 333/333
# restart backend
.venv/Scripts/python.exe -m uvicorn app.main:app --port 8000
```
