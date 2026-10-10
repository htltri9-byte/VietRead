# VietRead

Đồ án **Lập trình trên thiết bị di động**: ứng dụng đọc & đăng truyện chữ (Android – Flutter)
kèm backend REST (FastAPI + SQL Server).

- **Phần A – Flutter**: đọc/trả truyện, nhập truyện từ link và tự dịch sang tiếng Việt.
- **Phần C – Backend**: nằm trong [`backend/`](backend/README.md) (đã làm xong Bước 1 & 2).
- Đặc tả đầy đủ: [`VietRead_prompt.md`](VietRead_prompt.md).

---

## 1. Chạy app Flutter (Bước 3)

```bash
flutter pub get      # cài dependencies
flutter run          # chọn thiết bị / emulator Android
flutter analyze      # kiểm tra code (hiện: No issues found)
flutter test         # 107 test: models, mock API, Khám phá, chi tiết truyện, màn đọc,
                    # auth, SQLite/offline, Tủ sách, Đăng truyện + Nhập link (Bước 9/10),
                    # skeleton cho màn Đăng truyện / Quản lý chương (Bước 11)
flutter build apk --debug   # build APK → build/app/outputs/flutter-apk/app-debug.apk

# Kiểm tra HttpApiService gọi backend thật (bật backend trước):
dart run tool/check_real_api.dart http://127.0.0.1:8000
```

Yêu cầu: Flutter 3.x (máy này đang dùng Flutter 3.47.4 / Dart 3.13.3), Android SDK (đã cài),
minSdk 24 (đúng yêu cầu A1 — là giá trị mặc định của Flutter).

> Ghi chú build: [`android/gradle.properties`](android/gradle.properties) có đặt `kotlin.incremental=false`
> vì Pub Cache nằm ở ổ `C:` còn project ở ổ `D:` — Kotlin incremental sẽ lỗi
> "this and base files have different roots" nếu bật.

### Cấu hình `API_BASE_URL`

Backend mặc định chạy tại `http://127.0.0.1:8000`. Từ Bước 6 app gọi API thật (`useMock = false`) nên cần đặt `API_BASE_URL` đúng theo nơi chạy app:

| Chỗ chạy app | `API_BASE_URL` |
|---|---|
| Emulator Android (máy ảo) | `http://10.0.2.2:8000` — địa chỉ này trỏ về `localhost` của máy tính |
| Máy thật (điện thoại) | IP LAN của máy chạy backend, ví dụ `http://192.168.1.10:8000` |

- Xem IP máy: Windows `ipconfig` → IPv4 Address; Linux/macOS `ip addr`.
- Cần bật tường lửa cho cổng 8000; backend đã bật CORS (`CORS_ORIGINS=*` trong `backend/.env`).
- Danh sách endpoint: [`backend/README.md`](backend/README.md).

---

## 2. Giao diện — chủ đề "Mực & Giấy" (Phần A2)

- Nền kem giấy `#FAF6EE`, card trắng ngà, **bo góc 16px**, viền mảnh thay vì đổ bóng nặng.
- Màu chính xanh ngọc đậm `#1F6F6B`, màu nhấn san hô `#FF6B57`, chữ `#23201C`.
- Chế độ tối: nền `#14181A`, giữ nguyên màu nhấn — app tự chuyển theo hệ thống (`ThemeMode.system`).
- Font bundle trong [`assets/fonts/`](assets/fonts): UI/tiêu đề **Be Vietnam Pro** (sans-serif),
  nội dung chương **Noto Serif** (serif) — đã kiểm tra đủ dấu tiếng Việt.
- Bottom navigation dạng **viên thuốc nổi**, 4 mục: Khám phá · Tủ sách · Đăng truyện · Tài khoản;
  mục đang chọn là pill xanh ngọc kèm nhãn.

Tất cả màu/bo góc lấy từ [`lib/theme/app_theme.dart`](lib/theme/app_theme.dart)
(`AppTheme.light()` / `AppTheme.dark()`) — widget không hard-code màu.

- Icon app (launcher Android): nguồn [`assets/icon/vietread_icon_1024.png`](assets/icon/vietread_icon_1024.png)
  (chỉ để sinh icon, không đưa vào bundle) → sinh 5 mức `mipmap-*` (48/72/96/144/192px)
  bằng [`tool/generate_android_icons.ps1`](tool/generate_android_icons.ps1) — chạy lại script này
  khi thay ảnh app.

---

## 3. Cấu trúc thư mục (theo A5)

```
lib/
  main.dart        # MaterialApp: theme sáng/tối, locale vi, home = MainShell
  theme/           # app_theme.dart — màu, font, style nút/thẻ/nhập liệu
  models/          # story, chapter, comment, user, import_job, genre,
                    # reading_progress, downloaded_story (fromJson/toJson)
  services/         # api_config (cờ useMock), api_service (interface + HTTP),
                    # mock_api_service, auth_service (phiên đăng nhập + token),
                    # db_helper (SQLite: đã tải + lịch sử, A4),
                    # offline_service (tải chương vào SQLite),
                    # prefs_service (cỡ chữ/nền + tiến độ đọc),
                    # reading_progress_store
  screens/         # main_shell, home (trang Khám phá), story_detail, reader,
                    # library (Tủ sách 3 tab), upload, import, auth, profile
  widgets/         # floating_nav, empty_state, error_state (nút Thử lại),
                    # skeleton, story_card, chip_genre
assets/fonts/      # Be Vietnam Pro + Noto Serif
test/              # models, mock_api_service, home, story_detail, reader, widget,
                    # auth (service/screen/profile), db_helper, offline, library,
                    # upload + 3 màn CRUD (Bước 9), import (Bước 10)
tool/              # check_real_api.dart — kiểm tra backend thật (auth + follows),
                    # helpers/sqflite_test_setup.dart — SQLite FFI cho test thuần
backend/           # FastAPI + SQL Server (Bước 1, 2 hoàn thành)
```

### Chuyển giữa dữ liệu mock và API thật

Mọi nơi trong app chỉ gọi qua interface `ApiService`. Từ Bước 6 app mặc định gọi
backend thật; muốn chạy offline (không cần backend) thì mở
[`lib/services/api_config.dart`](lib/services/api_config.dart) và đổi:

```dart
static const bool useMock = false;   // false = API thật (mặc định từ Bước 6), true = mock offline
```

`API_BASE_URL` vẫn cấu hình bằng `--dart-define=API_BASE_URL=...` hoặc biến môi trường.

---

## 4. Chi tiết truyện & màn đọc (Bước 5)

### Màn chi tiết truyện (`lib/screens/story_detail_screen.dart`)

- Bìa, tên, tác giả, chip thể loại, điểm, số chương, trạng thái ("Đang ra"/"Hoàn thành").
- Nút **Đọc** / **Đọc tiếp** (nếu đã từng đọc truyện này), **Theo dõi**, **Tải offline**
  (2 nút sau hoạt động thật từ Bước 7 — xem mục 6).
- Mô tả có nút **Xem thêm** / **Thu gọn**.
- Tab **Chương** (danh sách phân trang 50 chương/lần + nút "Xem thêm chương") và
  tab **Bình luận** (Bước 8: xem / gửi / xoá của mình; chưa đăng nhập thì thấy lời mời đăng nhập).

### Màn đọc (`lib/screens/reader_screen.dart`)

- Nội dung chương lấy từ API (hoặc mock), kết thúc chương hiện "Hết chương N".
- Thanh dưới: **chương trước / chương sau** + % tiến độ; bấm avatar cài đặt để đổi
  **nền Sáng · Tối · Sepia**, **font Serif/Sans**, **cỡ chữ 14–28**, **giãn dòng 1.3–2.1**
  (lưu vào `shared_preferences`, mở lại giữ nguyên).
- **Tự lưu tiến độ đọc**: cuộn ≥ 0.5 giây (debounce 700 ms) hoặc bấm quay lại là lưu
  `{chương, tiêu đề chương, %}` — trang Khám phá hiện thẻ "Đọc tiếp" + %.

### Hướng dẫn test Bước 5

```bash
flutter analyze    # No issues found
flutter test       # 107/107 pass (toàn bộ suite, gồm test Bước 7)

# Backend thật (3 endpoint mới):
cd backend && ./.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
dart run tool/check_real_api.dart http://127.0.0.1:8000
# → in GET /stories/{id}, /stories/{id}/chapters, /chapters/{id} + số ký tự nội dung
```

Tay trên máy/emulator (dữ liệu mock, không cần backend):

1. `flutter run` → tab **Khám phá** → chạm một thẻ truyện → vào màn chi tiết.
2. Chạm 1 chương → màn đọc; thử đổi cỡ chữ / nền Sepia / font; cuộn xuống cuối.
3. Bấm quay lại → về Khám phá → thẻ **Đọc tiếp** giờ hiện % và chương vừa đọc
   (đã lưu bằng `shared_preferences`, restart app vẫn còn).
4. Quay lại chi tiết truyện → nút đọc đổi thành **Đọc tiếp** và mở đúng chương cũ.
5. Mặc định từ Bước 6 là API thật (`useMock = false`); muốn test bản mock offline thì đổi
   thành `true` trong [`lib/services/api_config.dart`](lib/services/api_config.dart).

---

## 5. Đăng nhập/Đăng ký + token (Bước 6)

### Thành phần

- [`lib/services/auth_service.dart`](lib/services/auth_service.dart) — `AuthService` (singleton) giữ
  `AuthSession {token, user}`: `restore()` đọc token đã lưu khi mở app (lỗi 401/403 thì tự xoá token,
  lỗi mạng thì giữ lại), `login()` / `register()` / `logout()` lưu vào `shared_preferences`
  (key `auth_token`, `auth_user`) và báo `notifyListeners()` khi trạng thái đổi.
- [`lib/services/api_service.dart`](lib/services/api_service.dart) — `HttpApiService` đính kèm
  `Authorization: Bearer <token>` cho mọi request sau đăng nhập; interface thêm `login`, `register`,
  `fetchMe`, `setToken`. Bản mock ([`lib/services/mock_api_service.dart`](lib/services/mock_api_service.dart))
  giả lập cùng giao diện nên app chạy được cả 2 chế độ.
- [`lib/screens/auth_screen.dart`](lib/screens/auth_screen.dart) — Form Đăng nhập/Đăng ký bằng
  `SegmentedButton`, validate tiếng Việt (email hợp lệ, mật khẩu ≥ 6 ký tự khi đăng ký), hiện thông
  báo lỗi backend trả về, nút có spinner khi đang gửi.
- [`lib/screens/profile_screen.dart`](lib/screens/profile_screen.dart) — chưa đăng nhập: 2 nút
  Đăng nhập / Đăng ký; đã đăng nhập: avatar initials, tên, email và **Đăng xuất**.
- Trang Khám phá chào kèm tên user; icon tài khoản ở header mở màn đăng nhập khi chưa đăng nhập;
  ở chi tiết truyện, bấm **Theo dõi** khi chưa đăng nhập cũng chuyển tới màn đăng nhập.

Từ Bước 6 [`lib/services/api_config.dart`](lib/services/api_config.dart) đặt `useMock = false` —
app gọi backend thật; muốn chạy không cần backend thì đổi lại thành `true`.

### Hướng dẫn test Bước 6

```bash
flutter analyze        # No issues found
flutter test           # 107/107 pass

# Backend thật + script kiểm tra HTTP (khối auth đã được thêm vào script):
cd backend && ./.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
# (terminal khác)
dart run tool/check_real_api.dart http://127.0.0.1:8000
# → in token đăng ký, GET /auth/me, login docgia, sai mật khẩu → 401 tiếng Việt
```

Tay trên emulator (`flutter run`, backend đang chạy; `API_BASE_URL` mặc định `http://10.0.2.2:8000`):

1. Tab **Tài khoản** → **Đăng nhập** bằng tài khoản demo (mật khẩu `VietRead@123`):
   - `docgia@vietread.vn`
   - `tacgia@vietread.vn`
2. Đăng nhập sai mật khẩu → hiện thông báo lỗi tiếng Việt từ backend, form giữ nguyên.
3. Đăng nhập đúng → tab Tài khoản hiện tên/email, lời chào ở Khám phá kèm tên;
   **kill app rồi chạy lại** → vẫn đăng nhập (token lưu bằng `shared_preferences`).
4. Bấm **Đăng xuất** → về trạng thái chưa đăng nhập; icon tài khoản ở header Khám phá
   mở lại màn đăng nhập.
5. Chưa đăng nhập mà bấm **Theo dõi** ở chi tiết truyện → bị đưa tới màn đăng nhập.
6. Chạy offline (không cần backend): đổi `useMock = true` trong
   [`lib/services/api_config.dart`](lib/services/api_config.dart), rồi đăng nhập 2 tài khoản demo ở trên.

---

## 6. Tủ sách — theo dõi, lịch sử, tải offline (Bước 7)

### SQLite cục bộ (A4)

[`lib/services/db_helper.dart`](lib/services/db_helper.dart) tạo đúng 3 bảng theo A4:
`downloaded_stories(id, title, author, coverPath, description)`,
`downloaded_chapters(id, storyId, idx, title, content)` và
`reading_history(storyId, chapterIndex, chapterTitle, progress, updatedAt)`.
Mỗi lần app lưu tiến độ đọc (Bước 5) song song ghi thêm 1 dòng vào `reading_history`.

### Tính năng

- **Tab Theo dõi**: đọc `GET /me/follows` — Bước 7 bổ sung router
  [`backend/app/routers/follows.py`](backend/app/routers/follows.py)
  (`POST/DELETE /follows/{storyId}`, `GET /me/follows`). Chưa đăng nhập → nút Đăng nhập.
  Nút **Theo dõi** ở màn chi tiết truyện giờ hoạt động thật: bấm lần đầu → theo dõi
  (nút đổi thành "Đã theo dõi"), bấm lại → bỏ theo dõi.
- **Tab Lịch sử**: dòng "Chương N – Tên chương" (đúng mẫu A3.7) kèm nút "…"
  (menu Đọc tiếp / Xoá khỏi lịch sử) và nút "×" xoá nhanh.
- **Tab Đã tải**: truyện trong SQLite; bấm vào → mở **màn đọc offline**
  (`ReaderScreen(offline: true)`) đọc hoàn toàn từ SQLite, không cần mạng;
  nút thùng rác xoá bản tải để giải phóng bộ nhớ (A3.8).
- **Tải offline** (nút ở màn chi tiết truyện): dialog *Tải toàn bộ* hoặc *khoảng
  chương (từ–đến, có validate)* → dialog tiến trình % + nút **Huỷ** → ghi vào
  SQLite; sau khi tải nút hiện "Đã tải (N)" với menu **Tải lại / Xoá bản tải**.
- Mất mạng giữa chừng khi đang đọc online → màn đọc tự chuyển sang bản đã tải
  trong SQLite (nếu có).
- **Tự làm mới khi quay về**: tab Tủ sách nghe sự kiện chọn tab ở thanh nav
  (MainShell) và nạp lại cả 3 tab mỗi lần được mở lại — nên sau khi theo dõi /
  đọc / tải ở màn khác, danh sách luôn cập nhật (IndexedStack không tự reload).

### Hướng dẫn test Bước 7

```bash
flutter analyze        # No issues found
flutter test           # 107/107 pass

# Backend thật (đã gồm router follows) + script HTTP:
./.venv/Scripts/python.exe -m uvicorn --app-dir backend app.main:app --host 127.0.0.1 --port 8000
dart run tool/check_real_api.dart http://127.0.0.1:8000
# → in POST /follows, GET /me/follows, DELETE /follows, 401 khi chưa đăng nhập

# Test backend đầy đủ (116 kiểm tra):
cd backend && ./.venv/Scripts/python.exe test_api.py
```

Tay trên emulator:

1. Đăng nhập (`docgia@vietread.vn` / `VietRead@123`) → mở một truyện → bấm
   **Theo dõi** → nút đổi "Đã theo dõi" + snackbar; vào **Tủ sách → Theo dõi**
   thấy truyện vừa theo dõi.
2. Đọc vài chương → tab **Lịch sử** hiện "Chương N – Tên chương"; bấm "…" →
   Đọc tiếp / Xoá khỏi lịch sử; bấm "×" xoá nhanh (restart app dữ liệu local vẫn còn).
3. Ở chi tiết truyện → **Tải offline** → "Tải toàn bộ (N chương)" → xem % tải
   (bấm Huỷ giữa chừng được) → nút chuyển "Đã tải (N)".
4. Bật chế độ máy bay → **Tủ sách → Đã tải** → bấm truyện → đọc bình thường
   khi mất mạng; tab Lịch sử vẫn xem/đọc tiếp được (dữ liệu local).
5. Tab **Đã tải** → thùng rác → xác nhận **Xoá** → mất bản tải để giải phóng bộ nhớ.

---

## 7. Tìm kiếm & lọc + Bình luận (Bước 8)

### Tìm kiếm & lọc (A3.3)

- Màn [`lib/screens/search_screen.dart`](lib/screens/search_screen.dart): ô tìm kiếm
  (Enter để tìm, nút × để xoá), chip thể loại (Tất cả + 8 thể loại mẫu) và 2 menu
  **Trạng thái** (Tất cả / Đang ra / Hoàn thành) + **Sắp xếp** (Mới nhất / Hot /
  Điểm cao / Tên A→Z) — gọi `GET /stories?query=&genre=&status=&sort=`
  (API đã có sẵn từ Bước 2).
- Trang Khám phá: bấm ô tìm kiếm hoặc chip thể loại → mở màn tìm kiếm
  (chip được chọn sẵn từ thể loại bạn bấm).
- Trạng thái đầy đủ: skeleton lưới 2 cột, rỗng "Không tìm thấy truyện nào",
  lỗi + nút "Thử lại" (A6).
- Bấm thẻ kết quả → màn chi tiết truyện.

### Bình luận (A3.6 — backend + Flutter)

- Backend [`backend/app/routers/comments.py`](backend/app/routers/comments.py):
  `GET/POST /stories/{id}/comments`, `DELETE /comments/{id}` — khách xem được (200),
  gửi bắt buộc đăng nhập (401), content rỗng → 400, chapterId không thuộc truyện
  → 400, xoá của người khác → 403, không tìm thấy → 404. Schema
  `CommentOut` / `CommentCreate` trong [`backend/app/schemas.py`](backend/app/schemas.py).
- Tab Bình luận màn chi tiết truyện: skeleton / lỗi + "Thử lại" / rỗng
  "Chưa có bình luận nào". Đã đăng nhập: ô nhập + nút gửi (bình luận mới lên đầu
  danh sách + snackbar); bình luận của mình có nút xoá có xác nhận; chưa đăng nhập:
  card "Đăng nhập để bình luận" (A3.1).
- `ApiService` thêm `fetchComments` / `addComment` / `deleteComment` (Http + Mock).

### Hướng dẫn test Bước 8

```bash
flutter analyze        # No issues found
flutter test           # 107/107 pass

# Backend thật (router comments mới) + script HTTP:
./.venv/Scripts/python.exe -m uvicorn --app-dir backend app.main:app --host 127.0.0.1 --port 8000
dart run tool/check_real_api.dart http://127.0.0.1:8000
# → in GET/POST/DELETE comments + 401 khi chưa đăng nhập

# Test backend đầy đủ (116 kiểm tra):
cd backend && ./.venv/Scripts/python.exe test_api.py
```

Tay trên emulator (`flutter run`, backend đang chạy):

1. Trang Khám phá → bấm ô **"Tìm truyện, tác giả..."** → gõ "Hoàng Đạo" → Enter →
   chỉ còn truyện khớp; bấm **×** để xoá từ khoá.
2. Chọn chip **Trinh Thám** → chỉ truyện Trinh Thám; menu **Trạng thái** → Hoàn thành;
   menu **Sắp xếp** → Điểm cao. Về trang chủ bấm thẳng chip thể loại → màn tìm kiếm
   mở với thể loại chọn sẵn.
3. Mở một truyện → tab **Bình luận**: đăng nhập `docgia@vietread.vn` / `VietRead@123`
   (nếu chưa) → gõ nội dung → nút gửi (mũi tên) → comment mới hiện đầu danh sách.
4. Bấm icon thùng rác trên bình luận của mình → xác nhận **Xoá** → biến mất + snackbar.
   Bình luận của người khác không có nút xoá (backend trả 403 nếu gỡ ép).
5. Đăng xuất rồi vào tab Bình luận → vẫn xem được, thay ô nhập bằng nút **Đăng nhập**.

---

## 8. Đăng truyện — CRUD truyện/chương (Bước 9)

### Tính năng (A3.9)

- Backend [`backend/app/routers/stories.py`](backend/app/routers/stories.py): thêm
  **`GET /me/stories`** — truyện của mình **kể cả nháp**, mới nhất trước (cần token;
  `GET /stories` công khai luôn loại nháp). Các endpoint `POST/PUT/DELETE /stories`,
  `/stories/{id}/chapters`, `/chapters/{id}` có sẵn từ Bước 1–2: chỉ tác giả mới sửa/xoá
  được (khác → 403), nháp chỉ chủ nhân xem được (khách → 404).
- Tab **Đăng truyện** ([`lib/screens/upload_screen.dart`](lib/screens/upload_screen.dart)):
  chưa đăng nhập → lời mời + nút **Đăng nhập**; đã đăng nhập → danh sách "Truyện của tôi"
  (dòng có chip **Nháp**), kéo để làm mới, FAB **Truyện mới**, menu từng dòng:
  **Sửa thông tin / Quản lý chương / Đăng công khai (hoặc Chuyển về nháp) / Xoá truyện**
  (xoá có dialog xác nhận → snackbar).
- [`lib/screens/story_form_screen.dart`](lib/screens/story_form_screen.dart) — tạo/sửa
  truyện: tên*, mô tả, ảnh bìa (URL), trạng thái (Đang ra / Hoàn thành), chip thể loại
  (chọn từ server hoặc nhập tay), công tắc **Lưu làm nháp**; lưu xong pop `Story` về.
- [`lib/screens/chapter_manager_screen.dart`](lib/screens/chapter_manager_screen.dart) —
  header truyện + danh sách chương (phân trang 200), thêm/sửa/xoá chương có dialog xác
  nhận, icon AppBar sửa thông tin truyện;
  [`lib/screens/chapter_form_screen.dart`](lib/screens/chapter_form_screen.dart) — số
  chương (để trống → tự đánh số), tên*, nội dung*.
- Tab **Tài khoản → "Truyện của tôi"** mở thẳng tab Đăng truyện.
- `ApiService` thêm `fetchMyStories`, `createStory`, `updateStory`, `deleteStory`,
  `createChapter`, `updateChapter`, `deleteChapter` (cả Http lẫn Mock; mock có
  `resetStoriesForTest()` để test reset state static).

### Hướng dẫn test Bước 9

```bash
flutter analyze        # No issues found
flutter test           # 107/107 pass

# Backend thật (đã gồm GET /me/stories):
./.venv/Scripts/python.exe -m uvicorn --app-dir backend app.main:app --host 127.0.0.1 --port 8000
# (terminal khác — 116 kiểm tra HTTP):
cd backend && ./.venv/Scripts/python.exe test_api.py
# → TẤT CẢ 94 KIỂM TRA ĐỀU PASS
```

Tay trên emulator (`flutter run`, backend đang chạy; `API_BASE_URL` mặc định
`http://10.0.2.2:8000`):

1. Tab **Đăng truyện** khi chưa đăng nhập → bấm **Đăng nhập** → đăng nhập
   `tacgia@vietread.vn` / `VietRead@123` → thấy 4 truyện của mình.
2. FAB **Truyện mới** → nhập tên (bắt buộc; bỏ trống → lỗi ngay ô tên) → **Lưu**
   → truyện mới ở đầu danh sách kèm chip **Nháp**.
3. Bấm "…" → **Quản lý chương** → **Chương mới** → nhập tên + nội dung → **Lưu**
   → chương hiện trong danh sách (ô "Số chương" để trống là tự đánh số).
4. Menu → **Đăng công khai** → snackbar + mất chip Nháp (vào lại menu thấy
   **Chuyển về nháp**); **Sửa thông tin** → đổi tên/thể loại → **Lưu** → danh sách cập nhật.
5. Menu → **Xoá truyện** → dialog xác nhận → **Xoá** → biến mất + snackbar
   (bấm **Huỷ** thì giữ nguyên).
6. Đăng xuất, đăng nhập `docgia@vietread.vn` → tab Đăng truyện → trạng thái rỗng
   "Chưa có truyện nào" (độc giả chưa tác phẩm nào).

---

## 9. Nhập truyện từ link — import job (Bước 10)

### Backend worker (C4)

- Router [`backend/app/routers/imports.py`](backend/app/routers/imports.py):
  `POST /imports { sourceUrl, targetLang }` → `{ jobId, status, progress, storyId,
  error }` (tạo job **Pending** rồi chạy nền bằng `BackgroundTasks`);
  `GET /imports/{jobId}` để poll — Pending / Running / Done / Failed + % chương,
  chỉ chủ job thấy (khác → 404).
- [`backend/app/services/import_worker.py`](backend/app/services/import_worker.py):
  chọn adapter theo domain → cào thông tin + danh sách chương → tạo **truyện nháp**
  (IsDraft=1, thuộc người đã import) → mỗi chương: cào → **dịch** → lưu
  `Chapters(Content = bản dịch, OriginalContent = bản gốc)` → cập nhật Progress →
  Done. Bất kỳ lỗi nào (nguồn chặn, link sai, dịch lỗi) → Failed kèm `Error` tiếng
  Việt; truyện nhập dở vẫn giữ lại để chỉnh sửa.
- [`backend/app/services/scraper.py`](backend/app/services/scraper.py): interface
  `parse_story(url)` / `parse_chapter(url)`; adapter **Qidian / B.faloo / Fanqie**
  (retry + delay giữa các request, `IMPORT_CHAPTER_DELAY` / `IMPORT_MAX_CHAPTERS`
  trong `.env`) + nguồn demo **`demo.vietread.local`** dùng fixture có sẵn
  (không cào mạng) để demo/kiểm thử cả luồng.
- [`backend/app/services/translator.py`](backend/app/services/translator.py): dịch
  theo từng đoạn (chunk); chuỗi endpoint dự phòng API cấu hình → Google gtx →
  MyMemory. Endpoint lỗi ≥2 lần liên tiếp **tự tạm nghỉ rồi tự quay lại** (5 phút
  với lỗi thường; hết quota thì nghỉ **đúng tới thời điểm API báo hồi** — đọc
  "NEXT AVAILABLE IN …", tối đa 12 giờ) — không bỏ vĩnh viễn, không cần restart
  server; mọi lỗi dịch luôn nêu rõ **tên endpoint + lý do + thời điểm hồi quota**
  (đã fix "Dịch thất bại ()" rỗng). `TRANSLATE_API_KEY` / `TRANSLATE_API_URL` /  `TRANSLATE_EMAIL` (tăng quota MyMemory) đặt trong `.env` (xem [`backend/.env.example`](backend/.env.example)).
- **Chế độ dịch offline bằng từ điển (mặc định `TRANSLATE_MODE=dict`)** — không
  cần mạng, không cần API key, không giới hạn số lần dịch:
  [`backend/app/vietphrase.py`](backend/app/vietphrase.py) so khớp **cụm dài nhất**
  theo thứ tự Names → VietPhrase → Hán-Việt từng chữ (dữ liệu trong
  [`backend/dictionaries/`](backend/dictionaries/README.md): `hanviet.txt` sinh từ
  Unihan ~9,5k chữ; `names.txt` thêm tên riêng; `vietphrase.txt` do người dùng cung
  cấp — thiếu file này vẫn chạy, chỉ ra âm từng chữ + log cảnh báo). Thêm tên riêng
  không cần restart: `POST /dictionary/names {"zh":"李明","vi":"Lý Minh"}`.
  `online` = chỉ API dịch như cũ; `auto` = online trước, lỗi rơi về từ điển.

### App Flutter (A3.10)

- [`lib/models/import_job.dart`](lib/models/import_job.dart): `ImportJob`
  `{ jobId, status, progress, storyId?, error? }` + nhãn tiếng Việt.
- [`lib/screens/import_screen.dart`](lib/screens/import_screen.dart): dán link →
  chọn ngôn ngữ đích (Tiếng Việt) → **Bắt đầu nhập** → theo dõi trạng thái (chip
  Đang chờ / Đang chạy / Hoàn tất / Thất bại + thanh %), poll mỗi 1.5s; poll lỗi
  có nút **Thử lại**; Done → **Về Truyện của tôi**, Failed → hiện `error` + **Thử lại**.
- Lối vào: tab **Đăng truyện** → icon AppBar **Nhập truyện từ link**; quay về
  danh sách tự nạp lại nên truyện nhập hiện ngay (ở dạng nháp).
- `ApiService` thêm `startImport` / `fetchImportJob` (cả Http lẫn Mock; mock có
  `resetImportsForTest()` và mô phỏng worker chạy nền theo từng lần poll).

### Trạng thái 3 nguồn thật (kiểm tra live trên máy này)

| Nguồn | Trạng thái | Ghi chú |
|---|---|---|
| Qidian (`www.` / `m.qidian.com`) | ✅ đọc được | link `www.` bị anti-bot (HTTP 202) → adapter tự rewrite về `m.qidian.com` + lấy catalog (840 chương, sắp theo 第N章); chương miễn phí dịch OK; chương **VIP** → Failed rõ "nội dung trả phí" |
| Fanqie (`fanqienovel.com`) | ⚠️ danh mục OK, nội dung bị chặn | chữ trong trang chương bị thay bằng ký tự PUA + render bằng font web mã hoá → adapter đọc `chapterData.content` rồi báo rõ "Fanqie mã hoá nội dung… chưa giải mã được" (giải mã thật cần OCR font — ngoài phạm vi đồ án) |
| Faloo (`wap.faloo.com`) | ⚠️ danh mục OK, nội dung bị chặn | trang chương yêu cầu đăng nhập tài khoản (thẻ `noLogin`) → adapter báo rõ "Faloo yêu cầu đăng nhập…" |
| `demo.vietread.local` | ✅ | nguồn demo fixture — đủ luồng Pending → Done không cần mạng cào |

> Sách Qidian dễ có hàng trăm chương: khi demo nên đặt `IMPORT_MAX_CHAPTERS`
> (ví dụ `5`) trong `backend/.env` để job chạy nhanh; để `0` là nhập toàn bộ.

### Hướng dẫn test Bước 10

```bash
flutter analyze        # No issues found
flutter test           # 107/107 pass (5 test mới của màn Nhập truyện)

# Backend thật (đã gồm POST/GET /imports):
./.venv/Scripts/python.exe -m uvicorn --app-dir backend app.main:app --host 127.0.0.1 --port 8000
# (terminal khác — 116 kiểm tra HTTP; check import Done cần mạng để dịch):
cd backend && PYTHONUTF8=1 ./.venv/Scripts/python.exe test_api.py
# → TẤT CẢ 116 KIỂM TRA ĐỀU PASS
```

Tay trên emulator (`flutter run`, backend đang chạy):

1. Đăng nhập `tacgia@vietread.vn` / `VietRead@123` → tab **Đăng truyện** → icon
   link trên AppBar (tooltip "Nhập truyện từ link").
2. Dán `https://demo.vietread.local/book/1` (nguồn demo) → ngôn ngữ đích
   **Tiếng Việt** → **Bắt đầu nhập** → chip trạng thái + thanh % chạy tới
   **Hoàn tất** (100%).
3. Bấm **Về Truyện của tôi** → truyện "Đường Qingyun" hiện đầu danh sách kèm chip
   **Nháp** → mở **Quản lý chương** thấy 3 chương đã dịch (sửa/xoá như Bước 9).
4. Dán `abc` → lỗi ngay trên ô; `https://example.com/book/1` → job **Thất bại**
   kèm "...chưa được hỗ trợ..." → nút **Thử lại**.
5. Nguồn thật (Qidian/Fanqie): dán link bình thường — nếu nguồn chặn IP hoặc nội
   dung trả phí thì job Failed kèm lý do rõ ràng (đúng C4).

---

## 10. Hoàn thiện — skeleton, trạng thái rỗng/lỗi, kiểm thử (Bước 11)

### Trạng thái UI — đủ 3 trạng thái trên mọi màn hình chính (A2/A6)

| Màn hình | Đang tải | Rỗng | Lỗi + nút "Thử lại" |
|---|---|---|---|
| Khám phá | `HomeSkeleton` | ✔ | ✔ |
| Tìm kiếm & lọc | skeleton lưới 2 cột | ✔ "Không tìm thấy truyện nào" | ✔ |
| Chi tiết truyện — tab Chương | skeleton dòng chương | ✔ | ✔ |
| Chi tiết truyện — tab Bình luận | skeleton dòng bình luận | ✔ "Chưa có bình luận nào" | ✔ |
| Màn đọc | skeleton tiêu đề + khối nội dung | — (chương luôn có nội dung) | ✔ |
| Tủ sách (3 tab) | skeleton dòng thẻ | ✔ | ✔ |
| Đăng truyện | `ListSkeleton` **(mới — Bước 11)** | ✔ | ✔ |
| Quản lý chương | `ListSkeleton` **(mới — Bước 11)** | ✔ "Chưa có chương nào" | ✔ |
| Nhập từ link | chip trạng thái + thanh % | ✔ (ô dán link) | job Failed hiện `error` + **Thử lại** |

- Widget tái sử dụng: [`lib/widgets/skeleton.dart`](lib/widgets/skeleton.dart)
  (`SkeletonBox`, `ListSkeleton` **mới**, `HomeSkeleton`),
  [`lib/widgets/empty_state.dart`](lib/widgets/empty_state.dart),
  [`lib/widgets/error_state.dart`](lib/widgets/error_state.dart).

### Kiểm thử các luồng chính

```bash
flutter analyze        # No issues found
flutter test           # 107/107 pass (2 test mới: skeleton Đăng truyện & Quản lý chương)

# Backend — 116 kiểm tra HTTP (bật server trước):
cd backend && PYTHONUTF8=1 ./.venv/Scripts/python.exe test_api.py
# → TẤT CẢ 116 KIỂM TRA ĐỀU PASS
```

Kết quả mới nhất trên máy này: `flutter analyze` 0 lỗi · `flutter test` **107/107**
· `test_api.py` **116/116** (đều exit code 0).

### Checklist tổng hợp — tự chạy tay 1 vòng (mỗi mục 1–2 phút)

1. **Khám phá**: mở app → thấy skeleton trước khi có dữ liệu → kéo để làm mới;
   tắt backend → hiện lỗi + **Thử lại** (bật lại backend rồi bấm là khỏi).
2. **Đọc**: mở truyện → đọc 2–3 chương → đổi cỡ chữ / nền / font trong màn đọc →
   thoát, vào lại thấy thẻ **Đọc tiếp** kèm %.
3. **Đăng nhập**: đăng xuất → tab Bình luận vẫn xem được → **Đăng nhập**
   `docgia@vietread.vn` / `VietRead@123`.
4. **Tủ sách**: Theo dõi 1 truyện → tab Theo dõi thấy; tab Lịch sử có
   "Chương N – Tên chương"; Tải offline → bật máy bay → tab Đã tải đọc được.
5. **Bình luận**: gửi 1 bình luận → hiện đầu danh sách → xoá (dialog xác nhận).
6. **Đăng truyện**: `tacgia@vietread.vn` → tạo truyện nháp → thêm chương →
   Đăng công khai → xoá (dialog xác nhận).
7. **Nhập link**: dán `https://demo.vietread.local/book/1` → chạy tới 100%
   **Hoàn tất** → truyện nháp hiện trong "Truyện của tôi".
8. **Trạng thái lỗi import**: dán `https://example.com/book/1` → job **Thất bại**
   kèm lý do + nút **Thử lại**.

---

## 11. Lộ trình (Phần D)

- [x] **1.** Backend: khởi tạo FastAPI, kết nối SQL Server, `schema.sql` + `seed.sql`, API auth
- [x] **2.** Backend: API stories, chapters, genres
- [x] **3.** Flutter: khởi tạo project, theme sáng/tối, floating bottom nav, điều hướng
- [x] **4.** Flutter: models + ApiService (mock) + trang Khám phá
- [x] **5.** Flutter: chi tiết truyện + màn hình đọc + lưu tiến độ
- [x] **6.** Flutter: đăng nhập/đăng ký + token; chuyển sang API thật
- [x] **7.** Flutter: tủ sách (theo dõi, lịch sử) + SQLite + tải offline
- [x] **8.** Tìm kiếm & lọc; bình luận (backend + Flutter)
- [x] **9.** Đăng truyện (CRUD truyện/chương)
- [x] **10.** Nhập truyện từ link + theo dõi import job
- [x] **11.** Hoàn thiện: skeleton, empty/error state, kiểm thử, README
