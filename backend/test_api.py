"""Chạy thử toàn bộ API Bước 1 + Bước 2 của VietRead.

Cách dùng (server phải đang chạy):
    .venv/Scripts/python.exe test_api.py
    (hoặc trỏ sang host khác: .venv/Scripts/python.exe test_api.py http://127.0.0.1:8000)
"""

from __future__ import annotations

import re
import sys
import time

import httpx

from app import alternatives, vietphrase  # parser marker + tra ngược nghĩa → khóa

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

print("\n=== GỢI Ý NHIỀU NGHĨA (marker) — bản thô chỉ chủ truyện thấy ===")


def resolve_markers(text: str) -> str:
    """Gỡ marker về nghĩa đầu — dùng thẳng app/alternatives.py

    (khớp mọi dạng: {a|b} chuẩn, dữ liệu cũ {中文|a|b} và cũ {a:b}).
    """
    return alternatives.resolve(text)


# Dọn quy tắc 见過 sót từ lần chạy trước (run bị ngắt có thể để lại quy tắc
# học — nó sẽ suppress marker 见过 ở phần kiểm thử ngay bên dưới).
r = client.get("/me/mark-rules", headers=auth(tac_gia))
for stale in r.json():
    client.delete(f"/me/mark-rules/{stale['id']}", headers=auth(tac_gia))

r = client.post("/stories", json={"title": "Truyện Kiểm Thử Marker B12"},
                headers=auth(tac_gia))
check("tạo truyện kiểm thử marker", r.status_code == 200, r.text)
mk_sid = r.json()["id"]

r = client.post(f"/stories/{mk_sid}/chapters/import-text",
                json={"text": "他为你而来，定为此子，见过此人。", "sourceLang": "zh",
                      "title": "Chương marker"}, headers=auth(tac_gia))
check("import-text zh = 200", r.status_code == 200, r.text)
mk_ch = r.json()
raw = mk_ch["content"]
markers = re.findall(r"\{[^{}]+\}", raw)
check("bản thô có marker {...}", len(markers) >= 1, raw[:120])
check("mỗi marker ≥ 2 nghĩa và ≤ 6 nghĩa (mọi phần tử là tiếng Việt)",
      all(2 <= len(m.meanings) <= 6 for m in alternatives.parse(raw)),
      str(markers))
check("MỌI marker trong bản thô không chứa ký tự CJK",
      all(not alternatives.has_cjk(mk) for mk in markers), raw[:200])

r = client.get(f"/chapters/{mk_ch['id']}")
check("GET /chapters (khách) = 200", r.status_code == 200, r.text)
reader_text = r.json()["content"]
check("người đọc KHÔNG thấy dấu {}", "{" not in reader_text, reader_text[:120])
check("bản đọc = bản thô đã resolve (nghĩa đầu)",
      reader_text == resolve_markers(raw),
      f"{reader_text[:80]!r} vs {resolve_markers(raw)[:80]!r}")

check("raw=1 chưa đăng nhập → 401",
      client.get(f"/chapters/{mk_ch['id']}", params={"raw": "1"}).status_code == 401)
r = client.get(f"/chapters/{mk_ch['id']}", params={"raw": "1"}, headers=auth(doc_gia))
check("raw=1 người khác → 403 {message}",
      r.status_code == 403 and "message" in r.json(), r.text)
r = client.get(f"/chapters/{mk_ch['id']}", params={"raw": "1"}, headers=auth(tac_gia))
check("raw=1 chủ truyện → bản thô giữ marker",
      r.status_code == 200 and "{" in r.json()["content"], r.text)

# --- Dịch lại có gợi ý nghĩa (KHÔNG tự lưu) ---
r = client.post(f"/chapters/{mk_ch['id']}/retranslate")
check("retranslate chưa đăng nhập → 401", r.status_code == 401, r.text)
r = client.post(f"/chapters/{mk_ch['id']}/retranslate", headers=auth(doc_gia))
check("retranslate người khác → 403 {message}",
      r.status_code == 403 and "message" in r.json(), r.text)
r = client.post(f"/chapters/{mk_ch['id']}/retranslate", headers=auth(tac_gia))
check("retranslate = 200 {chapterId, content}",
      r.status_code == 200 and {"chapterId", "content"} <= set(r.json()), r.text)
check("nội dung dịch lại có marker", "{" in r.json()["content"],
      r.json()["content"][:80])
check("retranslate KHÔNG tự lưu",
      client.get(f"/chapters/{mk_ch['id']}", params={"raw": "1"},
                 headers=auth(tac_gia)).json()["content"] == raw)
# Chương tạo tay không có OriginalContent → 400 (dùng truyện mới để không đụng seed)
r = client.post("/stories", json={"title": "Truyện Kiểm Thử Không Gốc B12b"},
                headers=auth(tac_gia))
norig_sid = r.json()["id"]
r = client.post(f"/stories/{norig_sid}/chapters",
                json={"title": "Chương 1", "content": "Nội dung gõ tay."},
                headers=auth(tac_gia))
norig_ch = r.json()
r = client.post(f"/chapters/{norig_ch['id']}/retranslate", headers=auth(tac_gia))
check("retranslate chương không có bản gốc → 400 {message}",
      r.status_code == 400 and "bản gốc" in r.json()["message"], r.text)
check("dọn truyện không gốc",
      client.delete(f"/stories/{norig_sid}", headers=auth(tac_gia)).status_code == 200)

print("\n=== TÌM & THAY THẾ THEO TRUYỆN — /replace + /undo + /glossary ===")

r = client.post("/stories", json={"title": "Truyện Kiểm Thử Thay Thế B13"},
                headers=auth(tac_gia))
check("tạo truyện kiểm thử thay thế", r.status_code == 200, r.text)
rp_sid = r.json()["id"]

rp_seed = [
    ("Chương 1: Lý Minh luyện kiếm", "Lý Minh ngồi thiền. Lý Minh mở mắt."),
    ("Chương 2: Trở về", "lý minh đi về. Có Lý Minh ở đây. Minh Minhsson đến."),
    ("Chương 3: Không tên", "Một chương không có tên riêng."),
]
rp_chs = []
for title, content in rp_seed:
    r = client.post(f"/stories/{rp_sid}/chapters",
                    json={"title": title, "content": content}, headers=auth(tac_gia))
    check(f"tạo chương: {title}", r.status_code == 200, r.text)
    rp_chs.append(r.json())

# Bản gốc của MỘT TRUYỆN KHÁC (truyện seed) — kiểm chứng không bị ảnh hưởng
seed_ch0 = client.get(f"/stories/{seed['id']}/chapters").json()[0]
seed_before = client.get(f"/chapters/{seed_ch0['id']}").json()["content"]

# --- Quyền + validate ---
check("replace chưa đăng nhập → 401",
      client.post(f"/stories/{rp_sid}/replace",
                  json={"find": "a", "replace": "b"}).status_code == 401)
r = client.post(f"/stories/{rp_sid}/replace", json={"find": "a", "replace": "b"},
                headers=auth(doc_gia))
check("replace người khác → 403 {message}",
      r.status_code == 403 and "message" in r.json(), r.text)
r = client.post("/stories/999999/replace", json={"find": "a", "replace": "b"},
                headers=auth(tac_gia))
check("replace truyện không tồn tại → 404 {message}",
      r.status_code == 404 and "message" in r.json(), r.text)
r = client.post(f"/stories/{rp_sid}/replace", json={"find": "  ", "replace": "b"},
                headers=auth(tac_gia))
check("find rỗng → 400", r.status_code == 400 and "message" in r.json(), r.text)
r = client.post(f"/stories/{rp_sid}/replace",
                json={"find": "a" * 201, "replace": "b"}, headers=auth(tac_gia))
check("find dài quá 200 ký tự → 400", r.status_code == 400, r.text)
r = client.post(f"/stories/{rp_sid}/replace",
                json={"find": "Lý Minh", "replace": "Lý Minh"},
                headers=auth(tac_gia))
check("find trùng replace → 400", r.status_code == 400 and "message" in r.json(), r.text)

# --- dryRun: đếm chỗ + đếm chương, không ghi gì ---
r = client.post(f"/stories/{rp_sid}/replace",
                json={"find": "Lý Minh", "replace": "Trần Lễ", "dryRun": True},
                headers=auth(tac_gia))
data = r.json()
check("dryRun trả đúng {dryRun, totalMatches, chapters}",
      r.status_code == 200 and set(data) == {"dryRun", "totalMatches", "chapters"},
      str(data))
check("dryRun: matchCase=false → 4 chỗ / 2 chương",
      data["totalMatches"] == 4 and len(data["chapters"]) == 2
      and [c["matches"] for c in data["chapters"]] == [2, 2], str(data))
check("dryRun: chương 3 không khớp không đưa vào",
      all(c["chapterNo"] in (1, 2) for c in data["chapters"]), str(data))
check("dryRun không ghi gì",
      client.get(f"/chapters/{rp_chs[0]['id']}", headers=auth(tac_gia))
      .json()["content"] == rp_seed[0][1])

r = client.post(f"/stories/{rp_sid}/replace",
                json={"find": "Lý Minh", "replace": "Trần Lễ", "dryRun": True,
                      "includeTitles": True}, headers=auth(tac_gia))
check("dryRun includeTitles: 5 chỗ (chương 1 + 3)",
      r.json()["totalMatches"] == 5
      and [c["matches"] for c in r.json()["chapters"]] == [3, 2], r.text)

# wholeWord: "Minh" không khớp đầu "Minhsson" (chương 1: 2, chương 2: 2)
r = client.post(f"/stories/{rp_sid}/replace",
                json={"find": "Minh", "replace": "X", "dryRun": True,
                      "matchCase": True, "wholeWord": True}, headers=auth(tac_gia))
check("dryRun wholeWord=true → 4 chỗ (không khớp đầu 'Minhsson')",
      r.json()["totalMatches"] == 4, r.text)
r = client.post(f"/stories/{rp_sid}/replace",
                json={"find": "Minh", "replace": "X", "dryRun": True,
                      "matchCase": True, "wholeWord": False}, headers=auth(tac_gia))
check("dryRun wholeWord=false → 5 chỗ (kể cả đầu 'Minhsson')",
      r.json()["totalMatches"] == 5, r.text)

# --- Thay thật (một transaction) ---
r = client.post(f"/stories/{rp_sid}/replace",
                json={"find": "Lý Minh", "replace": "Trần Lễ", "matchCase": True,
                      "includeTitles": True, "applyToFuture": True},
                headers=auth(tac_gia))
data = r.json()
check("thay thật = 200 có batchId + chaptersChanged",
      r.status_code == 200 and data.get("batchId")
      and data["chaptersChanged"] == 2 and data["totalMatches"] == 4, str(data))
batch1 = data["batchId"]

r = client.get(f"/stories/{rp_sid}/chapters", headers=auth(tac_gia))
after = {c["index"]: client.get(f"/chapters/{c['id']}", headers=auth(tac_gia)).json()
         for c in r.json()}
check("chương 1: nội dung + tên chương đều được thay",
      after[1]["content"] == "Trần Lễ ngồi thiền. Trần Lễ mở mắt."
      and after[1]["title"] == "Chương 1: Trần Lễ luyện kiếm", str(after[1]))
check("chương 2: matchCase=true giữ nguyên 'lý minh' thường",
      after[2]["content"] == "lý minh đi về. Có Trần Lễ ở đây. Minh Minhsson đến.",
      str(after[2]["content"]))
check("chương 3: không có chỗ nào khớp thì giữ nguyên",
      after[3]["content"] == rp_seed[2][1], str(after[3]["content"]))
check("truyện khác không bị ảnh hưởng",
      client.get(f"/chapters/{seed_ch0['id']}").json()["content"] == seed_before)

# --- Quy tắc ApplyToFuture ---
r = client.get(f"/stories/{rp_sid}/glossary", headers=auth(tac_gia))
check("GET /glossary = 200 có 1 quy tắc",
      r.status_code == 200 and len(r.json()) == 1, r.text)
rule = r.json()[0]
check("quy tắc đúng A → B + cờ",
      rule["findText"] == "Lý Minh" and rule["replaceText"] == "Trần Lễ"
      and rule["matchCase"] is True and rule["applyToFuture"] is True, str(rule))
check("GET /glossary người khác → 403",
      client.get(f"/stories/{rp_sid}/glossary", headers=auth(doc_gia)).status_code == 403)

r = client.post(f"/stories/{rp_sid}/chapters",
                json={"title": "Chương 4", "content": "Lý Minh xuất hiện lần nữa."},
                headers=auth(tac_gia))
check("chương mới trong truyện bị áp quy tắc ApplyToFuture",
      r.status_code == 200 and r.json()["content"] == "Trần Lễ xuất hiện lần nữa.",
      r.text)

r = client.post(f"/stories/{mk_sid}/chapters",
                json={"title": "Chương khác", "content": "Lý Minh không thuộc truyện này."},
                headers=auth(tac_gia))
check("truyện KHÁC không bị áp quy tắc",
      r.status_code == 200 and r.json()["content"] == "Lý Minh không thuộc truyện này.",
      r.text)

# --- Hoàn tác ---
r = client.post(f"/stories/{rp_sid}/replace/undo")
check("undo chưa đăng nhập → 401", r.status_code == 401, r.text)
r = client.post(f"/stories/{rp_sid}/replace/undo", headers=auth(doc_gia))
check("undo người khác → 403", r.status_code == 403, r.text)
r = client.post(f"/stories/{rp_sid}/replace/undo", headers=auth(tac_gia))
check("undo = 200 {message, restored, skipped}",
      r.status_code == 200 and {"message", "restored", "skipped"} <= set(r.json()),
      r.text)
check("undo khôi phục 2 chương, bỏ qua 0",
      r.json()["restored"] == 2 and r.json()["skipped"] == 0, r.text)
restored = {c["index"]: client.get(f"/chapters/{c['id']}", headers=auth(tac_gia)).json()
            for c in client.get(f"/stories/{rp_sid}/chapters",
                                headers=auth(tac_gia)).json()}
check("nội dung + tên chương sau undo đúng bản cũ",
      restored[1]["content"] == rp_seed[0][1]
      and restored[1]["title"] == rp_seed[0][0]
      and restored[2]["content"] == rp_seed[1][1], str(restored[1]))
check("chương 4 (thêm sau khi có quy tắc) không bị undo đụng tới",
      restored[4]["content"] == "Trần Lễ xuất hiện lần nữa.", str(restored[4]))
r = client.post(f"/stories/{rp_sid}/replace/undo", headers=auth(tac_gia))
check("undo lần nữa → 400 (đã tiêu thụ batch)",
      r.status_code == 400 and "message" in r.json(), r.text)

# --- Chương bị sửa sau batch → bỏ qua khi undo ---
r = client.post(f"/stories/{rp_sid}/replace",
                json={"find": "Lý Minh", "replace": "Trần Lễ", "matchCase": True},
                headers=auth(tac_gia))
check("thay lần 2 = 200 có batchId mới",
      r.status_code == 200 and r.json()["batchId"] and r.json()["batchId"] != batch1,
      r.text)
r = client.put(f"/chapters/{rp_chs[0]['id']}",
               json={"content": "Người dùng sửa tay sau khi thay."},
               headers=auth(tac_gia))
check("sửa tay chương 1 sau batch", r.status_code == 200, r.text)
r = client.post(f"/stories/{rp_sid}/replace/undo", headers=auth(tac_gia))
check("undo: chương đã sửa tiếp bị bỏ qua (restored=1, skipped=1)",
      r.status_code == 200 and r.json()["restored"] == 1
      and r.json()["skipped"] == 1, r.text)
check("chương sửa tay giữ nguyên nội dung người dùng",
      client.get(f"/chapters/{rp_chs[0]['id']}", headers=auth(tac_gia))
      .json()["content"] == "Người dùng sửa tay sau khi thay.")
check("chương 2 được hoàn tác về bản gốc",
      client.get(f"/chapters/{rp_chs[1]['id']}", headers=auth(tac_gia))
      .json()["content"] == rp_seed[1][1])

# --- Quy tắc: xoá ---
rule_id = client.get(f"/stories/{rp_sid}/glossary", headers=auth(tac_gia)).json()[0]["id"]
r = client.delete(f"/stories/{mk_sid}/glossary/{rule_id}", headers=auth(tac_gia))
check("xoá quy tắc của truyện khác → 404", r.status_code == 404, r.text)
r = client.delete(f"/stories/{rp_sid}/glossary/{rule_id}", headers=auth(doc_gia))
check("xoá quy tắc người khác → 403", r.status_code == 403, r.text)
r = client.delete(f"/stories/{rp_sid}/glossary/{rule_id}", headers=auth(tac_gia))
check("DELETE /glossary/{id} = 200", r.status_code == 200 and "message" in r.json(), r.text)
check("quy tắc đã xoá không còn trong danh sách",
      client.get(f"/stories/{rp_sid}/glossary", headers=auth(tac_gia)).json() == [])
check("xoá lại → 404",
      client.delete(f"/stories/{rp_sid}/glossary/{rule_id}",
                    headers=auth(tac_gia)).status_code == 404)
r = client.post(f"/stories/{rp_sid}/chapters",
                json={"title": "Chương 5", "content": "Lý Minh sau khi xoá quy tắc."},
                headers=auth(tac_gia))
check("chương mới sau khi xoá quy tắc không bị thay",
      r.status_code == 200 and r.json()["content"] == "Lý Minh sau khi xoá quy tắc.",
      r.text)

# --- Thay cả bên trong marker + không đụng OriginalContent ---
raw_before = client.get(f"/chapters/{mk_ch['id']}", params={"raw": "1"},
                        headers=auth(tac_gia)).json()["content"]
rt_before = client.post(f"/chapters/{mk_ch['id']}/retranslate",
                        headers=auth(tac_gia)).json()["content"]
marker = re.search(r"\{([^{}]+)\}", raw_before)
inner = [p.strip() for p in marker.group(1).split("|") if p.strip()] if marker else []
check("bản thô có marker ≥2 nghĩa để thay bên trong", len(inner) >= 2, str(inner))
if len(inner) >= 2:
    r = client.post(f"/stories/{mk_sid}/replace",
                    json={"find": inner[1], "replace": "NGHĨA_THAY"},
                    headers=auth(tac_gia))
    check("thay được cả bên trong marker (trên bản thô)",
          r.status_code == 200 and r.json()["totalMatches"] >= 1, r.text)
    raw_after = client.get(f"/chapters/{mk_ch['id']}", params={"raw": "1"},
                           headers=auth(tac_gia)).json()["content"]
    check("vẫn giữ dấu {} sau thay và có nghĩa mới",
          "{" in raw_after and "NGHĨA_THAY" in raw_after, raw_after[:120])
    rt_after = client.post(f"/chapters/{mk_ch['id']}/retranslate",
                           headers=auth(tac_gia)).json()["content"]
    check("OriginalContent không bị thay thế đụng tới", rt_after == rt_before)
    r = client.post(f"/stories/{mk_sid}/replace/undo", headers=auth(tac_gia))
    check("undo trả lại bản thô cũ",
          r.status_code == 200 and r.json()["restored"] >= 1, r.text)
    check("bản thô sau undo == trước thay",
          client.get(f"/chapters/{mk_ch['id']}", params={"raw": "1"},
                     headers=auth(tac_gia)).json()["content"] == raw_before)

check("dọn truyện marker",
      client.delete(f"/stories/{mk_sid}", headers=auth(tac_gia)).status_code == 200)
check("dọn truyện thay thế",
      client.delete(f"/stories/{rp_sid}", headers=auth(tac_gia)).status_code == 200)

print("\n=== TỪ ĐIỂN CÁ NHÂN — /dictionary/names ===")

# Chạy lại nhiều lần vẫn pass: dọn sạch từ điển của 2 tài khoản kiểm thử
# trước (dòng thừa của lần chạy trước chỉ xoá được khi chạy lại).
def _purge_words(user):
    r = client.get("/dictionary/names", headers=auth(user))
    for w in (r.json() if r.status_code == 200 else []):
        client.delete(f"/dictionary/names/{w['id']}", headers=auth(user))

_purge_words(tac_gia)
_purge_words(doc_gia)

r = client.post("/dictionary/names", json={"zh": "李明", "vi": "Lý Minh"})
check("POST /dictionary/names chưa đăng nhập → 401 {message}",
      r.status_code == 401 and "message" in r.json(), r.text)
check("GET /dictionary/names chưa đăng nhập → 401",
      client.get("/dictionary/names").status_code == 401)

r = client.post("/dictionary/names",
                json={"zh": "测试词", "vi": "từ kiểm thử",
                      "tags": "kiểm thử, mượn từ"}, headers=auth(tac_gia))
check("POST /dictionary/names = 200 {ok, zh, vi, tags, names}",
      r.status_code == 200 and r.json()["ok"] is True
      and r.json()["zh"] == "测试词" and r.json()["vi"] == "từ kiểm thử"
      and r.json()["tags"] == "kiểm thử,mượn từ" and r.json()["names"] > 0, r.text)
word = r.json()["word"]
check("phản hồi có {id, zh, vi, tags, createdAt}",
      {"id", "zh", "vi", "tags", "createdAt"} <= set(word), str(word))

r = client.post("/dictionary/names", json={"zh": "李明", "vi": "nghĩa khác"},
                headers=auth(doc_gia))
check("thêm từ lần đầu của tài khoản → 200",
      r.status_code == 200 and r.json()["zh"] == "李明", r.text)
r = client.post("/dictionary/names", json={"zh": "李明", "vi": "nghĩa khác"},
                headers=auth(doc_gia))
check("thêm trùng từ trong cùng tài khoản → 400",
      r.status_code == 400 and "message" in r.json(), r.text)

# Từ mới được dùng để dịch chương nhập sau đó (không cần restart)
r = client.post("/stories", json={"title": "Truyện Kiểm Thử Từ Điển B14"},
                headers=auth(tac_gia))
dict_sid = r.json()["id"]
r = client.post(f"/stories/{dict_sid}/chapters/import-text",
                json={"text": "这是测试词。", "sourceLang": "zh"},
                headers=auth(tac_gia))
check("chương mới dịch dùng ngay từ vừa thêm",
      r.status_code == 200
      and "từ kiểm thử" in r.json()["content"].lower(),
      r.json().get("content", r.text)[:120])

r = client.get("/dictionary/names", headers=auth(tac_gia))
check("GET /dictionary/names = 200 có từ vừa thêm",
      r.status_code == 200 and any(w["zh"] == "测试词" for w in r.json()),
      r.text[:200])
check("từ điển của tài khoản khác không thấy từ này",
      all(w["zh"] != "测试词"
          for w in client.get("/dictionary/names", headers=auth(doc_gia)).json()))
check("xoá từ của người khác → 404",
      client.delete(f"/dictionary/names/{word['id']}",
                    headers=auth(doc_gia)).status_code == 404)

r = client.delete(f"/dictionary/names/{word['id']}", headers=auth(tac_gia))
check("DELETE /dictionary/names/{id} = 200 {message}",
      r.status_code == 200 and "message" in r.json(), r.text)
check("từ đã xoá không còn trong danh sách",
      all(w["zh"] != "测试词"
          for w in client.get("/dictionary/names", headers=auth(tac_gia)).json()))
r = client.post(f"/stories/{dict_sid}/chapters/import-text",
                json={"text": "这是测试词。", "sourceLang": "zh"},
                headers=auth(tac_gia))
check("sau khi xoá, chương mới không còn dùng nghĩa cũ",
      r.status_code == 200
      and "từ kiểm thử" not in r.json()["content"].lower(),
      r.json().get("content", r.text)[:120])
check("xoá lại từ đã xoá → 404",
      client.delete(f"/dictionary/names/{word['id']}",
                    headers=auth(tac_gia)).status_code == 404)
check("dọn truyện kiểm thử từ điển",
      client.delete(f"/stories/{dict_sid}", headers=auth(tac_gia)).status_code == 200)

print("\n=== GỢI Ý NGHĨA: MỨC, NGHĨA ĐÃ CHỌN, KHÔNG HỎI LẠI ===")


def mk_markers(text: str) -> list[str]:
    """Mọi marker `{...}` trong văn bản (dữ liệu cũ có thể còn khóa chữ Hán)."""
    return re.findall(r"\{[^{}]+\}", text)


ZH1 = "他见过她三次，似乎很有钱。"  # 见过了 nghĩa (khóa đa chữ) + 似乎 (synonyms.txt)
ZH2 = "她又见到他。"

r = client.post("/stories", json={"title": "Truyện Kiểm Thử Gợi Ý Nghĩa"},
                headers=auth(tac_gia))
check("tạo truyện kiểm thử gợi ý = 200", r.status_code == 200, r.text)
mk_sid = r.json()["id"]

r = client.post(f"/stories/{mk_sid}/chapters/import-text",
                json={"text": ZH1, "sourceLang": "zh", "chapterNo": 1},
                headers=auth(tac_gia))
check("nhập chương 1 (zh) = 200", r.status_code == 200, r.text)
mk_ch1 = r.json()["id"]
r = client.post(f"/stories/{mk_sid}/chapters/import-text",
                json={"text": ZH2, "sourceLang": "zh", "chapterNo": 2},
                headers=auth(tac_gia))
check("nhập chương 2 (zh) = 200", r.status_code == 200, r.text)
mk_ch2 = r.json()["id"]

r = client.get(f"/chapters/{mk_ch1}?raw=1", headers=auth(tac_gia))
raw1 = r.json()["content"]
_mk_raw1 = alternatives.parse(raw1)
check("raw=1: marker chỉ chứa nghĩa Việt — không còn {见過| khóa Trung",
      len(_mk_raw1) >= 1
      and not any(alternatives.has_cjk(m.text) for m in _mk_raw1)
      and not any(alternatives.has_cjk(x)
                  for m in _mk_raw1 for x in m.meanings),
      raw1[:200])
# Tra ngược từ danh sách nghĩa → khóa 见过 (client mới không gửi khóa chữ Hán)
_jg = [m for m in _mk_raw1
       if "见过" in vietphrase.keys_for_meanings(list(m.meanings))]
check("tra ngược danh sách nghĩa → khóa 见过 (marker nguyên bản)", bool(_jg),
      str([(m.text, vietphrase.keys_for_meanings(list(m.meanings)))
           for m in _mk_raw1]))
JG = _jg[0].text  # marker chuẩn của 见过 — dạng mới, dùng so ở các kiểm tra sau
check("người đọc không thấy dấu {} (bản resolve)",
      "{" not in client.get(f"/chapters/{mk_ch1}").json()["content"])
check("似乎 trong synonyms.txt → không marker ở mức nhập mặc định (low)",
      not any("似乎" in vietphrase.keys_for_meanings(list(m.meanings))
              for m in _mk_raw1), raw1[:200])

# --- markLevel: hợp lệ / sai / không gửi body (client cũ) ---
r = client.post(f"/chapters/{mk_ch1}/retranslate", headers=auth(tac_gia))
check("retranslate KHÔNG body = 200 (mặc định MARK_LEVEL)",
      r.status_code == 200 and "content" in r.json(), r.text)
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "bogus"},
                headers=auth(tac_gia))
check("markLevel sai → 400 có message",
      r.status_code == 400 and "markLevel" in r.json()["message"], r.text)
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
n_low = len(mk_markers(r.json()["content"]))
check(f"mức Ít ≤ 15 marker/chương (thực tế {n_low})",
      1 <= n_low <= 15, str(n_low))
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "high"},
                headers=auth(tac_gia))
rt_high_ref = r.json()["content"]  # bản dịch lại mức Nhiều — so mức Ít/Nhiều
n_high = len(mk_markers(rt_high_ref))
check(f"mức Nhiều ≥ mức Ít ({n_high} ≥ {n_low})", n_high >= n_low)
check("retranslate KHÔNG tự lưu",
      len(mk_markers(client.get(f"/chapters/{mk_ch1}?raw=1",
                                headers=auth(tac_gia)).json()["content"]))
      == len(mk_markers(raw1)))
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(doc_gia))
check("retranslate người khác → 403", r.status_code == 403, r.text)

# --- markLevel khi import ---
r = client.post(f"/stories/{mk_sid}/chapters/import-text",
                json={"text": ZH2, "sourceLang": "zh", "chapterNo": 3,
                      "markLevel": "high"},
                headers=auth(tac_gia))
check("import-text nhận markLevel=high = 200", r.status_code == 200, r.text)
check("xoá lại chương kiểm thử số 3",
      client.delete(f"/chapters/{r.json()['id']}",
                    headers=auth(tac_gia)).status_code == 200)
r = client.post(f"/stories/{mk_sid}/chapters/import-text",
                json={"text": ZH2, "sourceLang": "zh", "chapterNo": 3,
                      "markLevel": "sai"},
                headers=auth(tac_gia))
check("import-text markLevel sai → 400",
      r.status_code == 400 and "markLevel" in r.json()["message"], r.text)

# --- “Luôn dùng nghĩa này cho truyện này” (StoryWordChoices) ---
r = client.post(f"/stories/{mk_sid}/word-choices",
                json={"sourceKey": "见过", "chosenText": "đã từng gặp"},
                headers=auth(tac_gia))
wc = r.json()
check("POST word-choice = 200 {id, sourceKey, chosenText, createdAt}",
      r.status_code == 200
      and {"id", "sourceKey", "chosenText", "createdAt"} <= set(wc), r.text)
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
c = r.json()["content"]
check("dịch lại truyện này tự dùng nghĩa đã chọn, không marker",
      "đã từng gặp" in c and JG not in c, c[:200])
# Truyện KHÁC dùng cùng văn bản → không bị ảnh hưởng
r = client.post("/stories", json={"title": "Truyện Kiểm Thử Gợi Ý Khác"},
                headers=auth(tac_gia))
mk_sid2 = r.json()["id"]
r = client.post(f"/stories/{mk_sid2}/chapters/import-text",
                json={"text": ZH1, "sourceLang": "zh", "chapterNo": 1},
                headers=auth(tac_gia))
mk2_body = r.json()
mk2_ch1 = mk2_body.get("id")
check("truyện khác vẫn marker見過 (word-choice không lan)",
      r.status_code == 200 and JG in mk2_body.get("content", ""),
      str(mk2_body)[:200])
r = client.post(f"/stories/{mk_sid}/word-choices",
                json={"sourceKey": "见过", "chosenText": "đã gặp lại"},
                headers=auth(tac_gia))
check("POST trùng khóa → cập nhật nghĩa mới",
      r.status_code == 200 and r.json()["chosenText"] == "đã gặp lại", r.text)
r = client.get(f"/stories/{mk_sid}/word-choices", headers=auth(tac_gia))
check("GET word-choices đúng 1 dòng (không nhân đôi)",
      r.status_code == 200 and len(r.json()) == 1, r.text)
r = client.post(f"/stories/{mk_sid}/word-choices",
                json={"sourceKey": "见过", "chosenText": "a{b}"},
                headers=auth(tac_gia))
check("chosenText chứa dấu {} → 400", r.status_code == 400, r.text)
r = client.post(f"/stories/{mk_sid}/word-choices",
                json={"sourceKey": "", "chosenText": "x"},
                headers=auth(tac_gia))
check("sourceKey rỗng → 400", r.status_code == 400, r.text)
r = client.get(f"/stories/{mk_sid}/word-choices", headers=auth(doc_gia))
check("GET word-choices người khác → 403", r.status_code == 403, r.text)
r = client.post(f"/stories/{mk_sid}/word-choices",
                json={"sourceKey": "见过", "chosenText": "x"},
                headers=auth(doc_gia))
check("POST word-choice người khác → 403", r.status_code == 403, r.text)
r = client.delete(f"/stories/{mk_sid}/word-choices/{wc['id'] + 999999}",
                  headers=auth(tac_gia))
check("DELETE word-choice không tồn tại → 404", r.status_code == 404, r.text)
r = client.delete(f"/stories/{mk_sid}/word-choices/{wc['id']}",
                  headers=auth(tac_gia))
check("DELETE word-choice = 200", r.status_code == 200, r.text)
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
check("xoá choice → dịch lại marker trở lại",
      JG in r.json()["content"], r.json()["content"][:200])

# --- “Không hỏi lại từ này” (StoryIgnoredWords — riêng truyện) ---
r = client.post(f"/stories/{mk_sid}/ignored-words",
                json={"sourceKey": "见过"}, headers=auth(tac_gia))
iw = r.json()
check("POST ignored-word = 200 {id, sourceKey, createdAt}",
      r.status_code == 200
      and {"id", "sourceKey", "createdAt"} <= set(iw), r.text)
r = client.post(f"/stories/{mk_sid}/ignored-words",
                json={"sourceKey": "见过"}, headers=auth(tac_gia))
check("POST ignored-word trùng khóa → idempotent (cùng id)",
      r.status_code == 200 and r.json()["id"] == iw["id"], r.text)
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
c = r.json()["content"]
check("dịch lại: khóa bỏ hỏi không marker, lấy nghĩa đầu",
      JG not in c and "bái kiến" in c, c[:200])
r = client.get(f"/chapters/{mk2_ch1}?raw=1", headers=auth(tac_gia))
check("truyện khác vẫn marker (ignore không lan)",
      r.status_code == 200 and JG in r.json()["content"], r.text)
r = client.get(f"/stories/{mk_sid}/ignored-words", headers=auth(tac_gia))
check("GET ignored-words = 200 danh sách", r.status_code == 200, r.text)
r = client.post(f"/stories/{mk_sid}/ignored-words",
                json={"sourceKey": "见过"}, headers=auth(doc_gia))
check("POST ignored-word người khác → 403", r.status_code == 403, r.text)
r = client.delete(f"/stories/{mk_sid}/ignored-words/{iw['id'] + 999999}",
                  headers=auth(tac_gia))
check("DELETE ignored-word không tồn tại → 404", r.status_code == 404, r.text)
r = client.delete(f"/stories/{mk_sid}/ignored-words/{iw['id']}",
                  headers=auth(tac_gia))
check("DELETE ignored-word = 200", r.status_code == 200, r.text)
r = client.delete(f"/stories/{mk_sid}/ignored-words/{iw['id']}",
                  headers=auth(tac_gia))
check("DELETE lần nữa → 404", r.status_code == 404, r.text)

# --- Học hành vi: bỏ hỏi đủ lượt → QUY TẮC → hết marker MỌI truyện → xoá → trở lại ---
# Thống kê UserWordStats tích luỹ mọi lượt ignore ở trên (bảng theo NGƯỜI, không
# theo truyện) — đoạn này xoá quy tắc 见過 sót trước, rồi bỏ hỏi 5 lượt nữa
# (đủ LEARN_SKIP_THRESHOLD=5 kể cả khi thống kê đã tích từ lần chạy trước).
r = client.get("/me/mark-rules", headers=auth(tac_gia))
check("GET /me/mark-rules = 200 mảng {id, sourceKey, skipCount, createdAt}",
      r.status_code == 200
      and all({"id", "sourceKey", "skipCount", "createdAt"} <= set(x)
              for x in r.json()), r.text)
check("GET /me/mark-rules chưa đăng nhập → 401",
      client.get("/me/mark-rules").status_code == 401)
for stale in [x for x in r.json() if x["sourceKey"] == "见过"]:
    client.delete(f"/me/mark-rules/{stale['id']}", headers=auth(tac_gia))
r = client.get("/me/mark-rules", headers=auth(tac_gia))
check("dọn quy tắc 见過 sót — chưa học lại",
      not any(x["sourceKey"] == "见过" for x in r.json()), r.text)

# Truyện B CHƯA từng "không hỏi lại" 见過 → phải còn marker trước khi học
r = client.post(f"/chapters/{mk2_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
check("trước khi học: truyện B vẫn marker見過",
      r.status_code == 200 and JG in r.json()["content"], r.text)

# Bỏ hỏi 5 lượt (mỗi lượt +1 thống kê — tích luỹ mọi truyện)
for _ in range(5):
    r = client.post(f"/stories/{mk_sid}/ignored-words",
                    json={"sourceKey": "见过"}, headers=auth(tac_gia))
    check("bỏ hỏi lượt học = 200", r.status_code == 200, r.text)
r = client.get("/me/mark-rules", headers=auth(tac_gia))
learned = [x for x in r.json() if x["sourceKey"] == "见过"]
check("đủ lượt bỏ qua → sinh ĐÚNG 1 quy tắc 见過 (không nhân đôi)",
      r.status_code == 200 and len(learned) == 1, r.text)
check("quy tắc mang skipCount ≥ 5", learned[0]["skipCount"] >= 5,
      str(learned))
r = client.delete(f"/me/mark-rules/{learned[0]['id']}", headers=auth(doc_gia))
check("xoá quy tắc người khác → 404", r.status_code == 404, r.text)

# Quy tắc áp MỌI truyện: dịch lại truyện B (chưa từng ignore) → hết marker
r = client.post(f"/chapters/{mk2_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
check("đã học: truyện B hết marker見過",
      r.status_code == 200 and JG not in r.json()["content"],
      r.json().get("content", "")[:200])

# Xoá quy tắc → marker trở lại
r = client.delete(f"/me/mark-rules/{learned[0]['id']}", headers=auth(tac_gia))
check("xoá quy tắc (chủ) = 200", r.status_code == 200 and "message" in r.json(),
      r.text)
r = client.post(f"/chapters/{mk2_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
check("xong: truyện B có lại marker見過",
      JG in r.json()["content"], r.json().get("content", "")[:200])
r = client.get("/me/mark-rules", headers=auth(tac_gia))
check("xoá thật sự biến mất khỏi danh sách",
      not any(x["id"] == learned[0]["id"] for x in r.json()), r.text)

# Bỏ hỏi thêm 1 lượt → thống kê đã đủ → quy tắc sinh lại (học lại được)
r = client.post(f"/stories/{mk_sid}/ignored-words",
                json={"sourceKey": "见过"}, headers=auth(tac_gia))
check("bỏ hỏi sau xoá = 200", r.status_code == 200, r.text)
r = client.get("/me/mark-rules", headers=auth(tac_gia))
learned2 = [x for x in r.json() if x["sourceKey"] == "见过"]
check("bỏ hỏi thêm → quy tắc 见過 sinh lại",
      len(learned2) == 1, r.text)
r = client.delete(f"/me/mark-rules/{learned2[0]['id']}", headers=auth(tac_gia))
check("dọn quy tắc học (test chạy lại được)", r.status_code == 200, r.text)
r = client.delete("/me/mark-rules/999999", headers=auth(tac_gia))
check("DELETE quy tắc không tồn tại → 404", r.status_code == 404, r.text)

# --- Gửi DANH SÁCH NGHĨA thay vì khóa chữ Hán (client mới, backend tra ngược) ---
r = client.get(f"/chapters/{mk_ch1}?raw=1", headers=auth(tac_gia))
mk_now = alternatives.parse(r.json()["content"])
check("bản thô hiện tại: mọi marker chỉ nghĩa Việt",
      bool(mk_now) and not any(alternatives.has_cjk(m.text) for m in mk_now),
      str(mk_now))
meanings = list(mk_now[0].meanings)

r = client.post(f"/stories/{mk_sid}/word-choices",
                json={"meanings": meanings, "chosenText": "nghĩa chọn theo nghĩa"},
                headers=auth(tac_gia))
wc2 = r.json()
check("POST word-choices CHỈ gửi meanings = 200 + affectedIds",
      r.status_code == 200 and wc2.get("affectedIds"), r.text)
check("affectedIds chứa id phản hồi", wc2["id"] in wc2["affectedIds"], str(wc2))
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
c = r.json()["content"]
check("dịch lại dùng nghĩa đã chọn (không cần sourceKey), hết marker",
      "nghĩa chọn theo nghĩa" in c and JG not in c, c[:200])
r = client.post(f"/stories/{mk_sid}/word-choices", json={"chosenText": "x"},
                headers=auth(tac_gia))
check("word-choices thiếu cả sourceKey lẫn meanings → 400 có message",
      r.status_code == 400 and "message" in r.json(), r.text)
# Xoá ngay nghĩa đã chọn (MỌI khóa tra ngược được) — để bước bỏ hỏi sau thấy marker
for wid in wc2.get("affectedIds", [wc2["id"]]):
    client.delete(f"/stories/{mk_sid}/word-choices/{wid}", headers=auth(tac_gia))

r = client.post(f"/stories/{mk_sid}/ignored-words", json={"meanings": meanings},
                headers=auth(tac_gia))
iw2 = r.json()
check("POST ignored-words CHỈ gửi meanings = 200 + affectedIds",
      r.status_code == 200 and iw2.get("affectedIds"), r.text)
r = client.post(f"/chapters/{mk_ch1}/retranslate", json={"markLevel": "low"},
                headers=auth(tac_gia))
c = r.json()["content"]
check("bỏ hỏi theo nghĩa → hết marker, lấy nghĩa đầu",
      JG not in c and "bái kiến" in c, c[:200])
r = client.post(f"/stories/{mk_sid}/ignored-words", json={},
                headers=auth(tac_gia))
check("ignored-words thiếu cả hai → 400 có message",
      r.status_code == 400 and "message" in r.json(), r.text)
# Dọn để không ảnh hưởng các bước sau (xoá MỌI khóa đã tra ngược được)
for wid in iw2.get("affectedIds", [iw2["id"]]):
    client.delete(f"/stories/{mk_sid}/ignored-words/{wid}", headers=auth(tac_gia))

# --- markers/clean: dọn chữ Hán dữ liệu CŨ trong DB (có snapshot hoàn tác) ---
from app.database import SessionLocal
from app.models import Chapter as ChapterRow

db = SessionLocal()
_row = db.get(ChapterRow, mk_ch1)
_orig_content = _row.content
_row.content = "Còn {为|vì|là|vi} rút đi kiều mị, {少年|nghĩa một} là marker."
db.commit()
db.close()

r = client.get(f"/chapters/{mk_ch1}?raw=1", headers=auth(tac_gia))
raw_clean = r.json()["content"]
check("raw=1 làm sạch dữ liệu cũ khi đọc: {为|…} → {vì|là|vi}",
      "{vì|là|vi}" in raw_clean and "为" not in raw_clean, raw_clean[:200])
check("raw=1: marker còn 1 nghĩa sau khi loại chữ Hán → bỏ {}",
      "nghĩa một" in raw_clean and "{少年" not in raw_clean, raw_clean[:200])
r = client.get(f"/chapters/{mk_ch1}")
reader = r.json()["content"]
check("bản đọc: không {}, không chữ Hán của marker",
      "{" not in reader and "为" not in reader and "少年" not in reader,
      reader[:200])
check("markers/clean chưa đăng nhập → 401",
      client.post(f"/stories/{mk_sid}/markers/clean").status_code == 401)
r = client.post(f"/stories/{mk_sid}/markers/clean", json={},
                headers=auth(doc_gia))
check("markers/clean người khác → 403", r.status_code == 403, r.text)

r = client.post(f"/stories/{mk_sid}/markers/clean", json={},
                headers=auth(tac_gia))
cl = r.json()
check("markers/clean = 200 {message, batchId, chaptersChanged, markersResolved}",
      r.status_code == 200
      and {"message", "batchId", "chaptersChanged", "markersResolved"} <= set(cl),
      r.text)
check("clean đếm đúng 2 chỗ cần dọn",
      cl["markersResolved"] == 2 and cl["chaptersChanged"] >= 1, str(cl))
db = SessionLocal()
_stored = db.get(ChapterRow, mk_ch1).content
db.close()
check("DB đã ghi dạng sạch sau clean",
      "为" not in _stored and "{vì|là|vi}" in _stored, _stored[:200])
r = client.post(f"/stories/{mk_sid}/markers/clean", json={},
                headers=auth(tac_gia))
check("clean lần nữa → 400 (không còn chữ Hán)",
      r.status_code == 400 and "message" in r.json(), r.text)
r = client.post(f"/stories/{mk_sid}/replace/undo", headers=auth(tac_gia))
check("undo clean = 200 (có snapshot hoàn tác)",
      r.status_code == 200 and r.json().get("restored", 0) >= 1, r.text)
db = SessionLocal()
_restored = db.get(ChapterRow, mk_ch1).content
db.close()
check("undo trả lại bản cũ (chữ Hán trở lại trong DB)",
      "{为|" in _restored, _restored[:200])
r = client.get(f"/chapters/{mk_ch1}?raw=1", headers=auth(tac_gia))
check("nhưng bản thô ĐỌC VẪN sạch (normalize khi đọc)",
      "为" not in r.json()["content"], r.json()["content"][:200])
# Trả lại nội dung gốc (PUT tự normalize — bản gốc đã sạch) để test chạy lại được
r = client.put(f"/chapters/{mk_ch1}", json={"content": _orig_content},
               headers=auth(tac_gia))
check("trả lại nội dung chương gốc = 200", r.status_code == 200, r.text)

# --- Nạp lại danh sách file (không cần restart) ---
r = client.post("/dictionary/mark-lists/reload", headers=auth(tac_gia))
check("POST /dictionary/mark-lists/reload = 200 {ok, noMark, ambiguous, synonyms}",
      r.status_code == 200
      and {"ok", "noMark", "ambiguous", "synonyms"} <= set(r.json()), r.text)
check("no_mark.txt nạp được (≥ 50 khóa)", r.json()["noMark"] >= 50,
      str(r.json()))
r = client.post("/dictionary/mark-lists/reload")
check("mark-lists/reload chưa đăng nhập → 401",
      r.status_code == 401 and "message" in r.json(), r.text)

check("dọn truyện kiểm thử gợi ý 1",
      client.delete(f"/stories/{mk_sid}", headers=auth(tac_gia)).status_code == 200)
check("dọn truyện kiểm thử gợi ý 2",
      client.delete(f"/stories/{mk_sid2}", headers=auth(tac_gia)).status_code == 200)

print("\n=== DỌN DẸP ===")
_purge_words(doc_gia)  # không để sót từ của doc_gia (test chạy lại được)
# Dọn mọi quy tắc học còn sót — bỏ hỏi theo nghĩa ở trên có thể đã sinh lại
# quy tắc 见过 SAO khi phần học hành vi đã dọn (test chạy lại được).
r = client.get("/me/mark-rules", headers=auth(tac_gia))
for x in r.json():
    client.delete(f"/me/mark-rules/{x['id']}", headers=auth(tac_gia))
r = client.delete(f"/stories/{draft_id}", headers=auth(tac_gia))
check("xoá truyện nháp", r.status_code == 200, r.text)
r = client.delete(f"/stories/{sid}", headers=auth(tac_gia))
check("DELETE /stories/{id} = 200", r.status_code == 200 and "message" in r.json(), r.text)
check("truyện đã xoá → 404", client.get(f"/stories/{sid}").status_code == 404)
check("chương của truyện đã xoá → 404",
      client.get(f"/stories/{sid}/chapters").status_code == 404)

print(f"\nTẤT CẢ {PASSED} KIỂM TRA ĐỀU PASS ✔")
