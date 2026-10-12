"""Chạy thử toàn bộ API Bước 1 + Bước 2 của VietRead.

Cách dùng (server phải đang chạy):
    .venv/Scripts/python.exe test_api.py
    (hoặc trỏ sang host khác: .venv/Scripts/python.exe test_api.py http://127.0.0.1:8000)
"""

from __future__ import annotations

import sys
import time

import httpx

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
client = httpx.Client(base_url=BASE, timeout=20)
PASSED = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    """Bắt buộc điều kiện đúng; in kết quả và dừng chương trình nếu sai."""
    global PASSED
    if not ok:
        raise AssertionError(f"FAILED — {label} {detail}")
    PASSED += 1
    print(f"  OK  {label}")


def login(email: str, password: str) -> str:
    """Đăng nhập và trả về token."""
    r = client.post("/auth/login", json={"email": email, "password": password})
    check(f"login {email}", r.status_code == 200, r.text)
    return r.json()["token"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


STORY_KEYS = {
    "id", "title", "author", "coverUrl", "description", "genres",
    "status", "rating", "chapterCount", "updatedAt",
}

print("\n=== GENRES ===")
r = client.get("/genres")
check("GET /genres = 200", r.status_code == 200, r.text)
genres = r.json()
check("có ít nhất 8 thể loại (seed)", len(genres) >= 8, str(len(genres)))
check("mỗi thể loại có id + name", all({"id", "name"} <= set(g) for g in genres))

print("\n=== DANH SÁCH TRUYỆN ===")
r = client.get("/stories")
check("GET /stories = 200", r.status_code == 200, r.text)
stories = r.json()
check("trả về mảng", isinstance(stories, list) and len(stories) >= 4)
check("đủ field theo Phần B", all(STORY_KEYS <= set(s) for s in stories))
check("không có truyện nháp trong danh sách công khai",
      all(s["isDraft"] is False for s in stories))
check("genres là mảng chuỗi", all(isinstance(s["genres"], list) for s in stories))
seed = next((s for s in stories if s["title"] == "Kiếm Sư Vọng Tường"), None)
check("tìm thấy truyện seed Kiếm Sư Vọng Tường", seed is not None)
check("số chương + thể loại + tác giả đúng",
      seed and seed["chapterCount"] == 3 and "Tiên Hiệp" in seed["genres"]
      and seed["author"] == "Trần Nhật Nam", str(seed))

r = client.get("/stories", params={"genre": "Tiên Hiệp"})
check("lọc theo genre", r.status_code == 200 and len(r.json()) >= 1
      and all("Tiên Hiệp" in s["genres"] for s in r.json()), r.text)

r = client.get("/stories", params={"status": "completed"})
check("lọc theo status=completed", r.status_code == 200 and len(r.json()) >= 1
      and all(s["status"] == "completed" for s in r.json()), r.text)

r = client.get("/stories", params={"status": "abc"})
check("status sai → 400 {message}", r.status_code == 400 and "message" in r.json(), r.text)

r = client.get("/stories", params={"query": "Kiếm Sư"})
check("tìm theo tên truyện", r.status_code == 200 and len(r.json()) == 1, r.text)

r = client.get("/stories", params={"query": "Trần Nhật Nam"})
check("tìm theo tên tác giả", r.status_code == 200 and len(r.json()) >= 4, r.text)

r = client.get("/stories", params={"sort": "rating"})
check("sort=rating giảm dần", r.status_code == 200
      and all(a["rating"] >= b["rating"] for a, b in zip(r.json(), r.json()[1:])), r.text)

r = client.get("/stories", params={"sort": "sai"})
check("sort sai → 400", r.status_code == 400 and "message" in r.json(), r.text)

r = client.get("/stories", params={"page": 1, "pageSize": 2})
p1 = [s["id"] for s in r.json()]
r = client.get("/stories", params={"page": 2, "pageSize": 2})
p2 = [s["id"] for s in r.json()]
check("phân trang 2 trang không trùng nhau", len(p1) == 2 and len(p2) == 2 and not set(p1) & set(p2))

print("\n=== CHI TIẾT TRUYỆN ===")
r = client.get(f"/stories/{seed['id']}")
check("GET /stories/{id} = 200", r.status_code == 200 and r.json()["id"] == seed["id"], r.text)
r = client.get("/stories/999999")
check("truyện không tồn tại → 404 {message}", r.status_code == 404 and "message" in r.json(), r.text)

print("\n=== CHƯƠNG ===")
r = client.get(f"/stories/{seed['id']}/chapters")
check("GET /stories/{id}/chapters = 200", r.status_code == 200, r.text)
chs = r.json()
check("đủ 3 chương seed, index tăng dần",
      len(chs) == 3 and [c["index"] for c in chs] == [1, 2, 3], str(chs))
check("ChapterSummary không chứa content", all("content" not in c for c in chs))
check("có đủ field {id, storyId, index, title, updatedAt}",
      all({"id", "storyId", "index", "title", "updatedAt"} <= set(c) for c in chs))

r = client.get(f"/stories/{seed['id']}/chapters", params={"pageSize": 2})
check("phân trang chương", r.status_code == 200 and len(r.json()) == 2, r.text)

r = client.get(f"/chapters/{chs[0]['id']}")
check("GET /chapters/{id} = 200 kèm content", r.status_code == 200
      and r.json()["content"] and r.json()["storyId"] == seed["id"], r.text)
r = client.get("/chapters/999999")
check("chương không tồn tại → 404", r.status_code == 404 and "message" in r.json(), r.text)

print("\n=== PHÂN QUYỀN (chưa đăng nhập) ===")
r = client.post("/stories", json={"title": "Truyện Mới"})
check("POST /stories chưa đăng nhập → 401", r.status_code == 401 and "message" in r.json(), r.text)
r = client.put(f"/stories/{seed['id']}", json={"title": "X"})
check("PUT /stories/{id} chưa đăng nhập → 401", r.status_code == 401, r.text)
r = client.delete(f"/stories/{seed['id']}")
check("DELETE /stories/{id} chưa đăng nhập → 401", r.status_code == 401, r.text)
r = client.post(f"/stories/{seed['id']}/chapters", json={"title": "X", "content": "Y"})
check("POST chương chưa đăng nhập → 401", r.status_code == 401, r.text)

print("\n=== TẠO / SỬA / XOÁ TRUYỆN (tác giả) ===")
tac_gia = login("tacgia@vietread.vn", "VietRead@123")
doc_gia = login("docgia@vietread.vn", "VietRead@123")

r = client.post("/stories", json={"title": "  B2 Sai Trạng Thái  ", "status": "abc"}, headers=auth(tac_gia))
check("status sai → 400", r.status_code == 400 and "message" in r.json(), r.text)

r = client.post("/stories", json={
    "title": "Truyện Kiểm Thử B2",
    "description": "Do script test_api.py tạo ra.",
    "status": "ongoing",
    "genres": ["Tiên Hiệp", "Kiểm Thử"],
}, headers=auth(tac_gia))
check("POST /stories = 200", r.status_code == 200, r.text)
new_story = r.json()
check("trả đúng title/author/chapterCount/genres",
      new_story["title"] == "Truyện Kiểm Thử B2"
      and new_story["author"] == "Trần Nhật Nam"
      and new_story["chapterCount"] == 0
      and set(new_story["genres"]) == {"Tiên Hiệp", "Kiểm Thử"}, str(new_story))
sid = new_story["id"]

r = client.get("/stories", params={"genre": "Kiểm Thử"})
check("thể loại mới tự tạo và lọc được",
      r.status_code == 200 and any(s["id"] == sid for s in r.json()), r.text)
r = client.get("/genres")
check("GET /genres có 'Kiểm Thử'",
      any(g["name"] == "Kiểm Thử" for g in r.json()))

r = client.put(f"/stories/{sid}", json={"title": "B2 Đổi Tên", "status": "completed"},
               headers=auth(doc_gia))
check("người khác sửa → 403 {message}", r.status_code == 403 and "message" in r.json(), r.text)

r = client.put(f"/stories/{sid}", json={"title": "B2 Đổi Tên", "status": "completed",
                                        "genres": ["Hệ Thống"]}, headers=auth(tac_gia))
check("PUT /stories/{id} = 200", r.status_code == 200
      and r.json()["title"] == "B2 Đổi Tên" and r.json()["status"] == "completed"
      and r.json()["genres"] == ["Hệ Thống"], r.text)

print("\n=== CRUD CHƯƠNG ===")
r = client.post(f"/stories/{sid}/chapters",
                json={"title": "Chương 1", "content": "Nội dung thử chương 1."},
                headers=auth(tac_gia))
check("tạo chương 1 (tự đánh số)", r.status_code == 200 and r.json()["index"] == 1, r.text)
ch1 = r.json()
r = client.post(f"/stories/{sid}/chapters",
                json={"title": "Chương 2", "content": "Nội dung thử chương 2."},
                headers=auth(tac_gia))
check("tạo chương 2 (tự đánh số)", r.status_code == 200 and r.json()["index"] == 2, r.text)
r = client.post(f"/stories/{sid}/chapters",
                json={"title": "Trùng", "content": "X", "index": 2}, headers=auth(tac_gia))
check("index trùng → 400", r.status_code == 400 and "message" in r.json(), r.text)

r = client.get(f"/stories/{sid}/chapters")
check("danh sách chương của truyện mới", r.status_code == 200 and len(r.json()) == 2, r.text)
r = client.put(f"/chapters/{ch1['id']}", json={"content": "Nội dung đã sửa."},
               headers=auth(tac_gia))
check("PUT /chapters/{id} = 200", r.status_code == 200
      and r.json()["content"] == "Nội dung đã sửa.", r.text)
r = client.put(f"/chapters/{ch1['id']}", json={"content": "   "}, headers=auth(tac_gia))
check("content rỗng → 400", r.status_code == 400, r.text)
r = client.delete(f"/chapters/{ch1['id']}", headers=auth(doc_gia))
check("người khác xoá chương → 403", r.status_code == 403, r.text)
r = client.delete(f"/chapters/{ch1['id']}", headers=auth(tac_gia))
check("DELETE /chapters/{id} = 200", r.status_code == 200 and "message" in r.json(), r.text)
check("chương đã xoá → 404", client.get(f"/chapters/{ch1['id']}").status_code == 404)

print("\n=== THEO DÕI TRUYỆN ===")
r = client.get("/me/follows")
check("GET /me/follows chưa đăng nhập → 401 {message}",
      r.status_code == 401 and "message" in r.json(), r.text)
r = client.post(f"/follows/{seed['id']}")
check("POST /follows chưa đăng nhập → 401", r.status_code == 401, r.text)

client.delete(f"/follows/{seed['id']}", headers=auth(doc_gia))  # dọn trạng thái cũ
r = client.post(f"/follows/{seed['id']}", headers=auth(doc_gia))
check("POST /follows/{id} = 200", r.status_code == 200 and "message" in r.json(), r.text)
r = client.post(f"/follows/{seed['id']}", headers=auth(doc_gia))
check("theo dõi lần 2 vẫn 200 (idempotent)", r.status_code == 200, r.text)

r = client.get("/me/follows", headers=auth(doc_gia))
check("GET /me/follows = 200 có truyện vừa theo dõi", r.status_code == 200
      and any(s["id"] == seed["id"] for s in r.json()), r.text)
check("me/follows đủ field theo Phần B",
      all(STORY_KEYS <= set(s) for s in r.json()), r.text)

r = client.post("/follows/999999", headers=auth(doc_gia))
check("theo dõi truyện không tồn tại → 404 {message}",
      r.status_code == 404 and "message" in r.json(), r.text)

r = client.delete(f"/follows/{seed['id']}", headers=auth(doc_gia))
check("DELETE /follows/{id} = 200", r.status_code == 200 and "message" in r.json(), r.text)
r = client.delete(f"/follows/{seed['id']}", headers=auth(doc_gia))
check("bỏ theo dõi lần 2 vẫn 200 (idempotent)", r.status_code == 200, r.text)
r = client.get("/me/follows", headers=auth(doc_gia))
check("sau khi bỏ theo dõi thì không còn trong danh sách",
      r.status_code == 200 and all(s["id"] != seed["id"] for s in r.json()), r.text)

print("\n=== BÌNH LUẬN ===")
COMMENT_KEYS = {"id", "storyId", "chapterId", "userId", "userName", "content", "createdAt"}

r = client.get(f"/stories/{seed['id']}/comments")
check("GET comments chưa đăng nhập = 200", r.status_code == 200, r.text)
comments0 = r.json()
check("có bình luận mẫu của seed", len(comments0) >= 1, r.text)
check("đủ field Comment theo Phần B",
      all(COMMENT_KEYS <= set(c) for c in comments0), r.text)
check("bình luận seed gắn đúng người dùng",
      any(c["userName"] == "Lê Minh Anh" for c in comments0), r.text)

r = client.get("/stories/999999/comments")
check("comments truyện không tồn tại → 404 {message}",
      r.status_code == 404 and "message" in r.json(), r.text)

r = client.post(f"/stories/{seed['id']}/comments", json={"content": "Hay"})
check("POST comments chưa đăng nhập → 401 {message}",
      r.status_code == 401 and "message" in r.json(), r.text)
r = client.delete("/comments/1")
check("DELETE comment chưa đăng nhập → 401", r.status_code == 401, r.text)

r = client.post(f"/stories/{seed['id']}/comments", json={"content": "   "},
                headers=auth(doc_gia))
check("content rỗng → 400 {message}",
      r.status_code == 400 and "message" in r.json(), r.text)

r = client.post(f"/stories/{seed['id']}/comments",
                json={"content": "Truyện hay, mong chương mới!"},
                headers=auth(doc_gia))
check("POST /stories/{id}/comments = 200", r.status_code == 200, r.text)
my_c = r.json()
check("trả đúng Comment + user đã đăng nhập",
      COMMENT_KEYS <= set(my_c)
      and my_c["content"] == "Truyện hay, mong chương mới!"
      and my_c["userName"] == "Lê Minh Anh"
      and my_c["chapterId"] is None, str(my_c))

r = client.post(f"/stories/{seed['id']}/comments",
                json={"content": "Comment theo chương", "chapterId": chs[0]["id"]},
                headers=auth(tac_gia))
check("gửi comment theo chương (chapterId)", r.status_code == 200
      and r.json()["chapterId"] == chs[0]["id"], r.text)
my_c2 = r.json()

r = client.post(f"/stories/{seed['id']}/comments",
                json={"content": "Sai chương", "chapterId": 999999},
                headers=auth(doc_gia))
check("chapterId không thuộc truyện → 400", r.status_code == 400, r.text)

r = client.get(f"/stories/{seed['id']}/comments")
clist = r.json()
check("danh sách sau POST có 2 comment mới",
      r.status_code == 200 and {my_c["id"], my_c2["id"]} <= {c["id"] for c in clist}, r.text)
check("mới nhất đứng đầu (created_at giảm dần)",
      all(a["createdAt"] >= b["createdAt"] for a, b in zip(clist, clist[1:])),
      str([c["createdAt"] for c in clist]))

r = client.delete(f"/comments/{my_c['id']}", headers=auth(tac_gia))
check("xoá comment người khác → 403 {message}",
      r.status_code == 403 and "message" in r.json(), r.text)

r = client.delete(f"/comments/{my_c['id']}", headers=auth(doc_gia))
check("DELETE /comments/{id} = 200", r.status_code == 200 and "message" in r.json(), r.text)
check("comment đã xoá không còn trong danh sách",
      my_c["id"] not in {c["id"] for c in client.get(
          f"/stories/{seed['id']}/comments").json()})
r = client.delete(f"/comments/{my_c['id']}", headers=auth(doc_gia))
check("xoá lại comment đã xoá → 404", r.status_code == 404, r.text)

# dọn nốt comment theo chương để chạy lại được nhiều lần
check("dọn comment theo chương",
      client.delete(f"/comments/{my_c2['id']}", headers=auth(tac_gia)).status_code == 200)

print("\n=== TRUYỆN NHÁP ===")
r = client.post("/stories", json={"title": "Nháp Kiểm Thử B2", "isDraft": True},
                headers=auth(tac_gia))
check("tạo truyện nháp", r.status_code == 200 and r.json()["isDraft"] is True, r.text)
draft_id = r.json()["id"]
r = client.get("/stories", params={"query": "Nháp Kiểm Thử B2"})
check("nháp không có trong danh sách công khai", r.status_code == 200 and r.json() == [], r.text)
check("khách không xem được nháp → 404", client.get(f"/stories/{draft_id}").status_code == 404)
check("chủ nhân xem được nháp",
      client.get(f"/stories/{draft_id}", headers=auth(tac_gia)).status_code == 200)
check("khách không xem được chương của nháp → 404",
      client.get(f"/stories/{draft_id}/chapters").status_code == 404)

print("\n=== TRUYỆN CỦA TÔI — GET /me/stories (Bước 9) ===")
r = client.get("/me/stories")
check("GET /me/stories chưa đăng nhập → 401 {message}",
      r.status_code == 401 and "message" in r.json(), r.text)

r = client.get("/me/stories", headers=auth(tac_gia))
check("GET /me/stories = 200", r.status_code == 200, r.text)
mine = r.json()
check("đủ field theo Phần B + authorId + isDraft",
      all(STORY_KEYS | {"authorId", "isDraft"} <= set(s) for s in mine), str(mine))
check("có truyện công khai của tôi",
      any(s["id"] == sid for s in mine), str([s["id"] for s in mine]))
check("có truyện nháp của tôi (kể cả nháp)",
      any(s["id"] == draft_id and s["isDraft"] for s in mine), str(mine))
check("chỉ truyện của mình",
      all(s["authorId"] == mine[0]["authorId"] for s in mine), str(mine))

r = client.get("/me/stories", headers=auth(doc_gia))
check("người khác không thấy truyện của tôi",
      r.status_code == 200 and all(s["id"] not in {sid, draft_id} for s in r.json()),
      r.text)

print("\n=== NHẬP TRUYỆN TỪ LINK — POST/GET /imports (Bước 10) ===")
r = client.post("/imports", json={"sourceUrl": "https://m.qidian.com/book/1/"})
check("POST /imports chưa đăng nhập → 401 {message}",
      r.status_code == 401 and "message" in r.json(), r.text)

r = client.post("/imports", json={"sourceUrl": "khong-phai-la-link"},
                headers=auth(tac_gia))
check("sourceUrl không phải link http(s) → 400", r.status_code == 400, r.text)

r = client.post("/imports",
                json={"sourceUrl": "https://m.qidian.com/book/1/", "targetLang": "fr"},
                headers=auth(tac_gia))
check("targetLang chưa được hỗ trợ → 400", r.status_code == 400, r.text)

# Nguồn không hỗ trợ → vẫn tạo job, worker ghi lỗi rõ ràng (không cần mạng)
r = client.post("/imports", json={"sourceUrl": "https://example.com/book/1"},
                headers=auth(tac_gia))
check("POST /imports (nguồn lạ) → 200 {jobId}",
      r.status_code == 200 and "jobId" in r.json(), r.text)
bad_job = r.json()["jobId"]
check("job trả đủ field {jobId, status, progress, storyId, error}",
      {"jobId", "status", "progress", "storyId", "error"} <= set(r.json()), r.text)

r = client.get(f"/imports/{bad_job}")
check("GET /imports/{id} chưa đăng nhập → 401", r.status_code == 401, r.text)

job_state = None
for _ in range(40):
    r = client.get(f"/imports/{bad_job}", headers=auth(tac_gia))
    if r.status_code == 200 and r.json()["status"] in {"Done", "Failed"}:
        job_state = r.json()
        break
    time.sleep(0.5)
check("nguồn lạ → job kết thúc Failed",
      job_state is not None and job_state["status"] == "Failed", str(job_state))
check("Failed kèm error nói rõ nguồn chưa hỗ trợ",
      "hỗ trợ" in (job_state or {}).get("error", ""), str(job_state))
check("job lỗi không tạo truyện", job_state.get("storyId") is None, str(job_state))

r = client.get(f"/imports/{bad_job}", headers=auth(doc_gia))
check("job của người khác → 404", r.status_code == 404, r.text)
check("GET /imports/999999999 → 404",
      client.get("/imports/999999999", headers=auth(tac_gia)).status_code == 404)

# Nguồn demo (fixture) → toàn bộ luồng: cào → tạo nháp → dịch → Done
# (phần dịch dùng API công khai nên check này CẦN có mạng)
mine_before = client.get("/me/stories", headers=auth(tac_gia)).json()
ids_before = {s["id"] for s in mine_before}
r = client.post("/imports", json={"sourceUrl": "https://demo.vietread.local/book/1"},
                headers=auth(tac_gia))
check("POST /imports (nguồn demo) → 200 {jobId}",
      r.status_code == 200 and "jobId" in r.json(), r.text)
demo_job = r.json()["jobId"]

demo_state = None
for _ in range(60):
    r = client.get(f"/imports/{demo_job}", headers=auth(tac_gia))
    state = r.json()
    if state["status"] in {"Done", "Failed"}:
        demo_state = state
        break
    time.sleep(1)
check("job demo hoàn tất → Done (progress 100)",
      demo_state is not None and demo_state["status"] == "Done"
      and demo_state["progress"] == 100, str(demo_state))
demo_sid = demo_state["storyId"]
check("Done kèm storyId", demo_sid is not None, str(demo_state))

mine_after = client.get("/me/stories", headers=auth(tac_gia)).json()
imported = next((s for s in mine_after if s["id"] == demo_sid), None)
check("truyện nhập hiện trong /me/stories",
      imported is not None and demo_sid not in ids_before, str(imported))
check("truyện nhập là nháp (isDraft=true) để chỉnh sửa trước khi đăng",
      imported is not None and imported["isDraft"] is True, str(imported))
check("truyện nhập có chương",
      imported is not None and imported["chapterCount"] >= 1, str(imported))

chs = client.get(f"/stories/{demo_sid}/chapters", headers=auth(tac_gia)).json()
check("GET /stories/{id}/chapters (nháp, chủ nhân) ≥ 1 chương",
      len(chs) >= 1, str(chs))
first_ch = client.get(f"/chapters/{chs[0]['id']}", headers=auth(tac_gia))
check("GET /chapters/{id} = 200", first_ch.status_code == 200, first_ch.text)
ch_body = first_ch.json()
check("Content là bản dịch tiếng Việt (khác bản gốc tiếng Trung)",
      "少年站在山巅" not in ch_body["content"]
      and any(v in ch_body["content"] for v in "ăâđêôơư"),
      ch_body["content"][:80])
check("job của người khác với bản demo → 404",
      client.get(f"/imports/{demo_job}", headers=auth(doc_gia)).status_code == 404)

# Dọn truyện nhập (job không có DELETE — giữ lại vô hại, storyId trỏ NULL khi xoá story)
r = client.delete(f"/stories/{demo_sid}", headers=auth(tac_gia))
check("xoá truyện nhập sau kiểm thử", r.status_code == 200, r.text)

print("\n=== THÊM CHƯƠNG VÀO TRUYỆN ĐÃ CÓ — /chapters/import + /import-text ===")
# Truyện mới tinh để kiểm thử riêng (không đụng truyện seed).
r = client.post("/stories", json={"title": "Truyện Kiểm Thử B11 Thêm Chương"},
                headers=auth(tac_gia))
check("tạo truyện cho kiểm thử thêm chương", r.status_code == 200, r.text)
imp_sid = r.json()["id"]

FREE_QIDIAN = "https://www.qidian.com/chapter/1040765595/806596284/"  # 第1章 永夜 (miễn phí)

r = client.post(f"/stories/{imp_sid}/chapters/import",
                json={"chapterUrl": FREE_QIDIAN})
check("chưa đăng nhập → 401 {message}",
      r.status_code == 401 and "message" in r.json(), r.text)

r = client.post("/stories/999999/chapters/import",
                json={"chapterUrl": FREE_QIDIAN}, headers=auth(tac_gia))
check("truyện không tồn tại → 404 {message}",
      r.status_code == 404 and "message" in r.json(), r.text)

r = client.post(f"/stories/{imp_sid}/chapters/import",
                json={"chapterUrl": FREE_QIDIAN}, headers=auth(doc_gia))
check("không phải chủ truyện → 403 {message}",
      r.status_code == 403 and "message" in r.json(), r.text)

r = client.post(f"/stories/{imp_sid}/chapters/import",
                json={"chapterUrl": "https://example.com/chapter/1/2"},
                headers=auth(tac_gia))
check("domain không phải Qidian → 400",
      r.status_code == 400 and "Chỉ hỗ trợ thêm chương từ Qidian" in r.json()["message"],
      r.text)

r = client.post(f"/stories/{imp_sid}/chapters/import",
                json={"chapterUrl": "https://m.qidian.com/book/1040765595/"},
                headers=auth(tac_gia))
check("link Qidian nhưng không phải link chương → 400 kèm hướng dẫn",
      r.status_code == 400 and "chương Qidian" in r.json()["message"], r.text)

# Thêm thật chương miễn phí (cần mạng) — www.qidian (bị chặn bot) phải tự
# rewrite sang m.qidian.com; Content = bản dịch, chương đánh số từ "第1章".
r = client.post(f"/stories/{imp_sid}/chapters/import",
                json={"chapterUrl": FREE_QIDIAN}, headers=auth(tac_gia))
check("thêm chương Qidian bằng link = 200", r.status_code == 200, r.text)
new_ch = r.json()
check("phản hồi đúng format chương {id, storyId, index, title, content}",
      {"id", "storyId", "index", "title", "content"} <= set(new_ch), str(new_ch))
check("số chương đọc từ tiêu đề 第1章 → index 1", new_ch["index"] == 1, str(new_ch))
check("content là bản dịch (khác bản gốc tiếng Trung)",
      new_ch["content"] and "那一天太阳落下" not in new_ch["content"],
      new_ch["content"][:80])

r = client.get(f"/stories/{imp_sid}/chapters", headers=auth(tac_gia))
check("danh sách chương sau thêm = 1", r.status_code == 200 and len(r.json()) == 1,
      r.text)

# Trùng chương: dán lại đúng chương đó (bản mobile — khác host, cùng chapterId)
r = client.post(f"/stories/{imp_sid}/chapters/import",
                json={"chapterUrl": "https://m.qidian.com/chapter/1040765595/806596284/"},
                headers=auth(tac_gia))
check("dán lại cùng chương → 409 'Chương này đã được nhập' + số chương",
      r.status_code == 409 and "Chương này đã được nhập" in r.json()["message"]
      and "1" in r.json()["message"], r.text)
check("trùng chương không tạo bản ghi mới",
      len(client.get(f"/stories/{imp_sid}/chapters", headers=auth(tac_gia)).json()) == 1)

# Truyện đã có SourceBookId=1040765595 → link book khác bị chặn
r = client.post(f"/stories/{imp_sid}/chapters/import",
                json={"chapterUrl": "https://m.qidian.com/chapter/1035420986/806596284/"},
                headers=auth(tac_gia))
check("link thuộc truyện khác → 400 'Link này thuộc truyện khác'",
      r.status_code == 400 and r.json()["message"] == "Link này thuộc truyện khác",
      r.text)

# Số chương trùng với chương đã có (client gửi chapterNo=1)
r = client.post(f"/stories/{imp_sid}/chapters/import-text",
                json={"text": "Nội dung Việt dán vào.", "sourceLang": "vi",
                      "chapterNo": 1}, headers=auth(tac_gia))
check("chapterNo trùng chương đã có → 409", r.status_code == 409, r.text)

print("\n=== DÁN VĂN BẢN — POST /stories/{id}/chapters/import-text ===")
r = client.post(f"/stories/{imp_sid}/chapters/import-text",
                json={"text": "Đoạn văn bản tiếng Việt dán thẳng vào chương."})
check("import-text chưa đăng nhập → 401", r.status_code == 401, r.text)

r = client.post(f"/stories/{imp_sid}/chapters/import-text",
                json={"text": "   ", "sourceLang": "vi"}, headers=auth(tac_gia))
check("text rỗng → 400", r.status_code == 400 and "message" in r.json(), r.text)

r = client.post(f"/stories/{imp_sid}/chapters/import-text",
                json={"text": "abc", "sourceLang": "fr"}, headers=auth(tac_gia))
check("sourceLang sai → 400", r.status_code == 400 and "message" in r.json(), r.text)

r = client.post(f"/stories/{imp_sid}/chapters/import-text",
                json={"text": "x" * 100001, "sourceLang": "vi"},
                headers=auth(tac_gia))
check("text quá 100.000 ký tự → 400", r.status_code == 400 and "message" in r.json(),
      r.text)

# sourceLang=vi: lưu nguyên, không dịch; không có chapterNo → MAX+1 = 2
vi_text = "Chương mới dán bằng tiếng Việt — giữ nguyên 100% nội dung."
r = client.post(f"/stories/{imp_sid}/chapters/import-text",
                json={"text": vi_text, "sourceLang": "vi"}, headers=auth(tac_gia))
check("import-text vi = 200", r.status_code == 200, r.text)
text_ch = r.json()
check("text vi lưu nguyên làm content", text_ch["content"] == vi_text, str(text_ch))
check("tự đánh số MAX+1 → index 2", text_ch["index"] == 2, str(text_ch))

# Ưu tiên chapterNo client gửi
r = client.post(f"/stories/{imp_sid}/chapters/import-text",
                json={"text": "Nội dung chương số 10.", "sourceLang": "vi",
                      "chapterNo": 10, "title": "Tên do client đặt"},
                headers=auth(tac_gia))
check("chapterNo client gửi được ưu tiên → index 10",
      r.status_code == 200 and r.json()["index"] == 10, r.text)
check("title client gửi được dùng", r.json()["title"] == "Tên do client đặt", r.text)

# sourceLang=zh: dịch Trung → Việt, lưu content là bản dịch (yêu cầu
# "dán tiếng Trung → tự ra chương tiếng Việt")
zh_text = "那一天太阳落下再也没有升起。"
r = client.post(f"/stories/{imp_sid}/chapters/import-text",
                json={"text": zh_text, "sourceLang": "zh"}, headers=auth(tac_gia))
check("import-text zh = 200 (dịch Trung → Việt)", r.status_code == 200, r.text)
zh_ch = r.json()
check("zh: content là bản dịch, khác bản gốc tiếng Trung",
      zh_ch["content"] and zh_ch["content"] != zh_text
      and "那一天" not in zh_ch["content"], zh_ch["content"][:80])
check("zh: số chương MAX+1 → index 11", zh_ch["index"] == 11, str(zh_ch))

r = client.get(f"/stories/{imp_sid}", headers=auth(tac_gia))
check("truyện có 4 chương sau khi thêm (1 link + 3 text)",
      r.status_code == 200 and r.json()["chapterCount"] == 4, r.text)

r = client.delete(f"/stories/{imp_sid}", headers=auth(tac_gia))
check("dọn truyện kiểm thử thêm chương", r.status_code == 200, r.text)

print("\n=== DỌN DẸP ===")
r = client.delete(f"/stories/{draft_id}", headers=auth(tac_gia))
check("xoá truyện nháp", r.status_code == 200, r.text)
r = client.delete(f"/stories/{sid}", headers=auth(tac_gia))
check("DELETE /stories/{id} = 200", r.status_code == 200 and "message" in r.json(), r.text)
check("truyện đã xoá → 404", client.get(f"/stories/{sid}").status_code == 404)
check("chương của truyện đã xoá → 404",
      client.get(f"/stories/{sid}/chapters").status_code == 404)

print(f"\nTẤT CẢ {PASSED} KIỂM TRA ĐỀU PASS ✔")
