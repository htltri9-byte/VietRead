"""Test luồng KIỂM DUYỆT TRUYỆN — chạy in-process (không cần server đang chạy).

    .venv/Scripts/python.exe test_moderation.py

Bao phủ:
- Quyền: /admin/* 401 khi chưa đăng nhập, 403 với user thường (mọi endpoint).
- submit: thiếu confirmRights / thiếu chương / thiếu mô tả-thể loại → 400;
  hợp lệ → pending; submit lần 2 → 409; rejected → submit lại được.
- Truyện chưa duyệt KHÔNG lên app: không có ở Khám phá/tìm kiếm, khách xem
  chi tiết/chương/bình luận/theo dõi → 404; chủ truyện và admin vẫn xem được.
- Duyệt → hiện công khai; từ chối kèm lý do → ẩn; gỡ xuống (unpublish) → 404.
- NeedsRecheck khi sửa chương truyện approved; duyệt lại tắt cờ.
- Hai admin thao tác cùng lúc → request sau 409 (không ghi đè lẫn nhau).
- GET /me trả role; /admin/stats đếm đủ 4 trạng thái + needsRecheck.
- Dữ liệu cũ sau migration: mọi truyện công khai vẫn moderationStatus=approved.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import select  # noqa: E402

from app.database import SessionLocal  # noqa: E402
from app.main import app  # noqa: E402
from app.models import User  # noqa: E402

PASSED = 0

# Console Windows (cp1252) không in được tiếng Việt → buộc UTF-8
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def check(label: str, ok: bool, detail: str = "") -> None:
    global PASSED
    if not ok:
        raise AssertionError(f"FAILED — {label} {detail}")
    PASSED += 1
    print(f"  OK  {label}")


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def register(client: TestClient, name: str, email: str, password: str) -> dict:
    r = client.post(
        "/auth/register", json={"name": name, "email": email, "password": password}
    )
    check(f"register {email} = 200", r.status_code == 200, r.text)
    return r.json()


def promote_admin(email: str) -> None:
    """Đặt Role='admin' trực tiếp trong DB (test tự tạo tài khoản, không hardcode
    tài khoản admin thật; token vẫn dùng được vì role đọc từ DB mỗi request)."""
    db = SessionLocal()
    try:
        user = db.execute(select(User).where(User.email == email)).scalar_one()
        user.role = "admin"
        db.commit()
    finally:
        db.close()


def make_story(
    client: TestClient,
    token: str,
    title: str,
    description: str | None = None,
    genres: list[str] | None = None,
) -> dict:
    body: dict = {"title": title}
    if description is not None:
        body["description"] = description
    if genres is not None:
        body["genres"] = genres
    r = client.post("/stories", json=body, headers=auth(token))
    check("tạo truyện = 200", r.status_code == 200, r.text)
    return r.json()


def add_chapter(client: TestClient, token: str, story_id: int) -> dict:
    r = client.post(
        f"/stories/{story_id}/chapters",
        json={"title": "Chương 1", "content": "Nội dung chương thử."},
        headers=auth(token),
    )
    check("tạo chương = 200", r.status_code == 200, r.text)
    return r.json()


def submit(client: TestClient, token: str, story_id: int, confirm: bool = True):
    return client.post(
        f"/stories/{story_id}/submit",
        json={"confirmRights": confirm},
        headers=auth(token),
    )


def main() -> None:
    stamp = int(time.time() * 1000)
    pw = "MatKhauTest@123"  # mật khẩu của TÀI KHOẢN TEST tự tạo trong test này
    with TestClient(app) as client:
        # --- Đăng ký 3 tài khoản: tác giả / độc giả / admin (tự tạo) --------
        author = register(client, "Tác Giả Test", f"tg{stamp}@vietread.vn", pw)
        reader = register(client, "Độc Giả Test", f"dg{stamp}@vietread.vn", pw)
        adm = register(client, "Admin Test", f"ad{stamp}@vietread.vn", pw)
        atok, rtok, adtok = author["token"], reader["token"], adm["token"]

        print("\n=== ROLE ===")
        check(
            "register trả user.role='user'",
            author["user"].get("role") == "user",
            str(author["user"]),
        )
        r = client.get("/auth/me", headers=auth(atok))
        check(
            "GET /auth/me có role",
            r.status_code == 200 and r.json().get("role") == "user",
            r.text,
        )
        promote_admin(f"ad{stamp}@vietread.vn")
        r = client.get("/auth/me", headers=auth(adtok))
        check(
            "GET /auth/me admin → role='admin'",
            r.status_code == 200 and r.json().get("role") == "admin",
            r.text,
        )

        print("\n=== QUYỀN /admin/* ===")
        check(
            "/admin chưa đăng nhập → 401",
            client.get("/admin/stats").status_code == 401,
        )
        for path in (
            "/admin/stories",
            "/admin/stories/1",
            "/admin/chapters/1",
            "/admin/stats",
        ):
            r = client.get(path, headers=auth(atok))
            check(f"GET {path} user thường → 403", r.status_code == 403, r.text)
        r = client.post("/admin/stories/1/approve", headers=auth(atok))
        check("POST approve user thường → 403", r.status_code == 403, r.text)
        r = client.post(
            "/admin/stories/1/reject",
            json={"reason": "lý do kiểm thử"},
            headers=auth(atok),
        )
        check("POST reject user thường → 403", r.status_code == 403, r.text)

        # --- Tạo truyện + submit ------------------------------------------
        title = f"Truyện Kiểm Duyệt {stamp}"
        story = make_story(client, atok, title)  # thiếu mô tả/thể loại/chương
        sid = story["id"]
        check(
            "truyện mới = draft, isDraft=true (nhất quán)",
            story["moderationStatus"] == "draft" and story["isDraft"] is True,
            str(story),
        )

        print("\n=== SUBMIT — VALIDATE ===")
        r = submit(client, atok, sid)
        check(
            "submit thiếu mô tả/thể loại/chương → 400 nêu lý do",
            r.status_code == 400 and "chương" in r.json()["message"],
            r.text,
        )
        ch1 = add_chapter(client, atok, sid)
        r = submit(client, atok, sid)
        check(
            "đã có chương nhưng thiếu mô tả/thể loại → 400",
            r.status_code == 400 and "thể loại" in r.json()["message"],
            r.text,
        )
        r = client.put(
            f"/stories/{sid}",
            json={"description": "Mô tả đầy đủ cho kiểm thử.", "genres": ["Huyền Huyễn"]},
            headers=auth(atok),
        )
        check("PUT mô tả + thể loại = 200", r.status_code == 200, r.text)
        r = submit(client, atok, sid, confirm=False)
        check(
            "submit confirmRights=false → 400 (cần xác nhận quyền)",
            r.status_code == 400 and "confirmRights" in r.json()["message"],
            r.text,
        )
        r = client.post(
            f"/stories/{sid}/submit", json={}, headers=auth(atok)
        )
        check(
            "submit thiếu confirmRights → 400",
            r.status_code == 400 and "confirmRights" in r.json()["message"],
            r.text,
        )
        r = submit(client, atok, sid)
        check(
            "submit hợp lệ → pending + submittedAt",
            r.status_code == 200
            and r.json()["moderationStatus"] == "pending"
            and r.json()["isDraft"] is True
            and r.json().get("submittedAt") is not None,
            r.text,
        )
        r = submit(client, atok, sid)
        check("submit lần 2 (đang pending) → 409", r.status_code == 409, r.text)

        print("\n=== TRUYỆN CHƯA DUYỆT KHÔNG LÊN APP ===")
        r = client.get("/stories", params={"query": title})
        check(
            "pending: không có ở Khám phá/tìm kiếm",
            r.status_code == 200 and all(s["id"] != sid for s in r.json()),
            r.text,
        )
        check("pending: khách xem chi tiết → 404", client.get(f"/stories/{sid}").status_code == 404)
        check(
            "pending: khách xem danh sách chương → 404",
            client.get(f"/stories/{sid}/chapters").status_code == 404,
        )
        check(
            "pending: khách xem nội dung chương → 404",
            client.get(f"/chapters/{ch1['id']}").status_code == 404,
        )
        check(
            "pending: khách xem bình luận → 404",
            client.get(f"/stories/{sid}/comments").status_code == 404,
        )
        r = client.post(f"/follows/{sid}", headers=auth(rtok))
        check("pending: reader theo dõi → 404", r.status_code == 404, r.text)
        check(
            "pending: chủ truyện vẫn xem được",
            client.get(f"/stories/{sid}", headers=auth(atok)).status_code == 200,
        )
        check(
            "pending: admin vẫn xem được",
            client.get(f"/stories/{sid}", headers=auth(adtok)).status_code == 200,
        )
        check(
            "pending: reader (không phải chủ) → 404",
            client.get(f"/stories/{sid}", headers=auth(rtok)).status_code == 404,
        )
        check(
            "pending có trong /me/stories của chủ",
            any(s["id"] == sid for s in client.get("/me/stories", headers=auth(atok)).json()),
        )

        print("\n=== ADMIN LIST / DETAIL / STATS ===")
        r = client.get("/admin/stories", params={"status": "pending"}, headers=auth(adtok))
        check("GET /admin/stories?status=pending = 200", r.status_code == 200, r.text)
        row = next((s for s in r.json() if s["id"] == sid), None)
        check("truyện có trong danh sách chờ duyệt", row is not None, str(r.json())[:200])
        check(
            "đủ trường danh sách admin",
            row is not None
            and {"id", "title", "author", "chapterCount", "moderationStatus",
                 "needsRecheck", "submittedAt", "scanStatus"} <= set(row),
            str(row),
        )
        stamped = [s["submittedAt"] for s in r.json() if s.get("submittedAt")]
        check(
            "sắp xếp chờ duyệt: cũ nhất trước",
            all(a <= b for a, b in zip(stamped, stamped[1:])),
            str(stamped[:5]),
        )
        r2 = client.get(
            "/admin/stories", params={"status": "pending", "q": title}, headers=auth(adtok)
        )
        check(
            "tìm kiếm q= trong admin list",
            r2.status_code == 200 and any(s["id"] == sid for s in r2.json()),
            r2.text,
        )
        r = client.get("/admin/stories", params={"status": "sai"}, headers=auth(adtok))
        check("status sai → 400", r.status_code == 400, r.text)

        r = client.get(f"/admin/stories/{sid}", headers=auth(adtok))
        check(
            "GET /admin/stories/{id} = 200 (info + danh sách chương)",
            r.status_code == 200
            and r.json()["story"]["id"] == sid
            and len(r.json()["chapters"]) >= 1
            and r.json()["uploaderName"],
            r.text,
        )
        check(
            "admin detail kể cả truyện chưa công khai (khách → 404)",
            client.get(f"/admin/stories/{sid}").status_code == 401
            and client.get(f"/admin/stories/{sid}", headers=auth(rtok)).status_code == 403,
        )

        # Chương có marker → /admin/chapters trả bản đã resolve
        r = client.put(
            f"/chapters/{ch1['id']}",
            json={"content": "Hắn quay lại {vì|bởi vì} nơi cũ, {thấy|nhìn thấy} ánh sáng."},
            headers=auth(atok),
        )
        check("PUT chương có marker = 200", r.status_code == 200, r.text)
        r = client.get(f"/admin/chapters/{ch1['id']}", headers=auth(adtok))
        check("GET /admin/chapters = 200", r.status_code == 200, r.text)
        body = r.json()
        check(
            "admin chương đã resolve marker (không có {})",
            "{" not in body["content"] and "vì" in body["content"],
            body["content"],
        )
        check(
            "admin chương có trường originalContent",
            "originalContent" in body,
            str(body),
        )
        check(
            "user thường xem /admin/chapters → 403",
            client.get(f"/admin/chapters/{ch1['id']}", headers=auth(atok)).status_code == 403,
        )

        r = client.get("/admin/stats", headers=auth(adtok))
        check(
            "GET /admin/stats đủ 5 key + pending ≥ 1",
            r.status_code == 200
            and {"draft", "pending", "approved", "rejected", "needsRecheck"} <= set(r.json())
            and r.json()["pending"] >= 1,
            r.text,
        )

        print("\n=== DUYỆT ===")
        r = client.post(f"/admin/stories/{sid}/approve", headers=auth(adtok))
        check(
            "approve = 200 {message, moderationStatus: approved}",
            r.status_code == 200 and r.json()["moderationStatus"] == "approved",
            r.text,
        )
        r = client.post(f"/admin/stories/{sid}/approve", headers=auth(adtok))
        check("approve lần 2 (đã approved, không recheck) → 409", r.status_code == 409, r.text)
        check(
            "trạng thái cuối vẫn approved, isDraft=false (nhất quán)",
            client.get(f"/stories/{sid}", headers=auth(adtok)).json()["moderationStatus"] == "approved"
            and client.get(f"/stories/{sid}", headers=auth(adtok)).json()["isDraft"] is False,
        )
        r = client.get(f"/stories/{sid}")
        check(
            "approved: khách xem chi tiết được",
            r.status_code == 200 and r.json()["moderationStatus"] == "approved",
            r.text,
        )
        r = client.get("/stories", params={"query": title})
        check(
            "approved: có ở Khám phá/tìm kiếm",
            r.status_code == 200 and any(s["id"] == sid for s in r.json()),
            r.text,
        )
        r = client.post(f"/follows/{sid}", headers=auth(rtok))
        check("approved: reader theo dõi được", r.status_code == 200, r.text)
        client.delete(f"/follows/{sid}", headers=auth(rtok))

        print("\n=== NEEDSRECHECK KHI SỬA CHƯƠNG TRUYỆN APPROVED ===")
        r = client.put(
            f"/chapters/{ch1['id']}",
            json={"content": "Nội dung sửa sau khi đã duyệt."},
            headers=auth(atok),
        )
        check("sửa chương truyện approved = 200", r.status_code == 200, r.text)
        r = client.get("/admin/stories", params={"status": "recheck"}, headers=auth(adtok))
        check(
            "truyện nằm trong tab 'Cần xem lại'",
            r.status_code == 200 and any(s["id"] == sid for s in r.json()),
            r.text,
        )
        r = client.get("/admin/stats", headers=auth(adtok))
        check("stats.needsRecheck ≥ 1", r.json()["needsRecheck"] >= 1, r.text)
        r = client.post(f"/admin/stories/{sid}/approve", headers=auth(adtok))
        check(
            "duyệt lại truyện approved+có cờ = 200",
            r.status_code == 200 and r.json()["moderationStatus"] == "approved",
            r.text,
        )
        r = client.get("/admin/stories", params={"status": "recheck"}, headers=auth(adtok))
        check(
            "sau khi duyệt lại hết 'cần xem lại'",
            all(s["id"] != sid for s in r.json()),
            r.text,
        )

        print("\n=== TỪ CHỐI (kèm lý do bắt buộc) ===")
        r = client.post(f"/admin/stories/{sid}/reject", json={}, headers=auth(adtok))
        check("reject thiếu reason → 400", r.status_code == 400, r.text)
        r = client.post(
            f"/admin/stories/{sid}/reject", json={"reason": "ngắn"}, headers=auth(adtok)
        )
        check("reason < 5 ký tự → 400", r.status_code == 400, r.text)
        r = client.post(
            f"/admin/stories/{sid}/reject",
            json={"reason": "Nội dung vi phạm bản quyền — gỡ khỏi ứng dụng."},
            headers=auth(adtok),
        )
        check(
            "reject = 200 → rejected",
            r.status_code == 200 and r.json()["moderationStatus"] == "rejected",
            r.text,
        )
        detail = client.get(f"/stories/{sid}", headers=auth(adtok)).json()
        check(
            "lý do được lưu + isDraft=true (nhất quán)",
            "bản quyền" in (detail.get("rejectReason") or "") and detail["isDraft"] is True,
            str(detail.get("rejectReason")),
        )
        check("rejected: khách → 404", client.get(f"/stories/{sid}").status_code == 404)
        r = client.post(
            f"/admin/stories/{sid}/reject",
            json={"reason": "Từ chối lần hai nữa."},
            headers=auth(adtok),
        )
        check("reject truyện đã rejected → 409", r.status_code == 409, r.text)

        print("\n=== GỬI LẠI + GỠ XUỐNG + TƯƠNG THÍCH CLIENT CŨ ===")
        r = submit(client, atok, sid)
        check(
            "rejected → submit lại = pending, xóa lý do cũ",
            r.status_code == 200
            and r.json()["moderationStatus"] == "pending"
            and r.json()["rejectReason"] is None,
            r.text,
        )
        r = client.post(f"/stories/{sid}/unpublish", headers=auth(atok))
        check("unpublish khi pending → 409", r.status_code == 409, r.text)
        r = client.post(f"/admin/stories/{sid}/approve", headers=auth(adtok))
        check("admin approve lại = approved", r.status_code == 200, r.text)
        r = client.put(f"/stories/{sid}", json={"isDraft": True}, headers=auth(atok))
        check(
            "PUT isDraft=true (client cũ) trên approved = gỡ xuống → draft",
            r.status_code == 200 and r.json()["moderationStatus"] == "draft",
            r.text,
        )
        r = submit(client, atok, sid)
        check("submit lại sau gỡ = pending", r.status_code == 200, r.text)
        r = client.post(f"/admin/stories/{sid}/approve", headers=auth(adtok))
        check("approve lần 3 = approved", r.status_code == 200, r.text)
        r = client.put(f"/stories/{sid}", json={"isDraft": False}, headers=auth(atok))
        check(
            "PUT isDraft=false trên approved (client cũ) = 200 idempotent",
            r.status_code == 200 and r.json()["moderationStatus"] == "approved",
            r.text,
        )
        r = client.post(f"/stories/{sid}/unpublish", headers=auth(atok))
        check(
            "chủ truyện unpublish = draft",
            r.status_code == 200 and r.json()["moderationStatus"] == "draft",
            r.text,
        )
        check("draft: khách → 404", client.get(f"/stories/{sid}").status_code == 404)
        r = client.post(f"/stories/{sid}/unpublish", headers=auth(atok))
        check("unpublish lần 2 (đang draft) → 409", r.status_code == 409, r.text)
        check(
            "reader unpublish truyện khác → 403",
            client.post(f"/stories/{sid}/unpublish", headers=auth(rtok)).status_code == 403,
        )
        check(
            "reader submit truyện khác → 403",
            submit(client, rtok, sid).status_code == 403,
        )

        print("\n=== HAI ADMIN THAO TÁC SONG SONG ===")
        admin2 = register(client, "Admin Test 2", f"ad2{stamp}@vietread.vn", pw)
        promote_admin(f"ad2{stamp}@vietread.vn")
        ad2tok = admin2["token"]
        story2 = make_story(client, atok, f"Truyện Song Song {stamp}")
        sid2 = story2["id"]
        add_chapter(client, atok, sid2)
        client.put(
            f"/stories/{sid2}",
            json={"description": "Mô tả kiểm thử song song.", "genres": ["Đô Thị"]},
            headers=auth(atok),
        )
        submit(client, atok, sid2)
        r1 = client.post(f"/admin/stories/{sid2}/approve", headers=auth(adtok))
        r2 = client.post(f"/admin/stories/{sid2}/approve", headers=auth(ad2tok))
        check("admin 1 approve = 200", r1.status_code == 200, r1.text)
        check("admin 2 approve cùng trạng thái → 409", r2.status_code == 409, r2.text)
        check(
            "trạng thái cuối = approved (không bị ghi đè)",
            client.get(f"/stories/{sid2}", headers=auth(adtok)).json()["moderationStatus"] == "approved",
        )
        r3 = client.post(
            f"/admin/stories/{sid2}/reject",
            json={"reason": "Gỡ vì vi phạm kiểm thử."},
            headers=auth(ad2tok),
        )
        check(
            "admin 2 reject (approved → rejected) = 200",
            r3.status_code == 200 and r3.json()["moderationStatus"] == "rejected",
            r3.text,
        )
        r4 = client.post(
            f"/admin/stories/{sid2}/reject",
            json={"reason": "Từ chối thêm lần nữa."},
            headers=auth(adtok),
        )
        check("admin 1 reject sau đó → 409 (đã rejected)", r4.status_code == 409, r4.text)

        print("\n=== DỮ LIỆU CŨ SAU MIGRATION ===")
        r = client.get("/stories")
        check(
            "truyện công khai cũ (seed) vẫn hiển thị",
            r.status_code == 200 and len(r.json()) >= 1,
            r.text[:200],
        )
        check(
            "mọi truyện ở danh sách công khai đều moderationStatus=approved",
            all(s["moderationStatus"] == "approved" for s in r.json()),
            str([(s["title"], s["moderationStatus"]) for s in r.json()][:8]),
        )
        check(
            "mọi truyện công khai isDraft=false",
            all(s["isDraft"] is False for s in r.json()),
        )

        print("\n=== DỌN DẸP ===")
        check(
            "xoá truyện kiểm thử 1",
            client.delete(f"/stories/{sid}", headers=auth(atok)).status_code == 200,
        )
        check(
            "xoá truyện kiểm thử 2",
            client.delete(f"/stories/{sid2}", headers=auth(atok)).status_code == 200,
        )

    print(f"\nTẤT CẢ {PASSED} KIỂM TRA KIỂM DUYỆT ĐỀU PASS ✔")


if __name__ == "__main__":
    main()
