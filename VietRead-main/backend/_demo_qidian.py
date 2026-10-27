# Demo tay: import 1 chương Qidian thật → dịch có marker gợi ý nghĩa,
# rồi "Tìm & thay thế" + hoàn tác trên chính chương đó.
# Chạy: cd backend && PYTHONUTF8=1 .venv/Scripts/python.exe _demo_qidian.py
import re
import sys

import httpx

BASE = "http://127.0.0.1:8000"
QIDIAN = "https://m.qidian.com/chapter/1040765595/806596284/"  # 第1章 永夜 (miễn phí)

c = httpx.Client(base_url=BASE, timeout=120)

r = c.post("/auth/login", json={"email": "tacgia@vietread.vn", "password": "VietRead@123"})
r.raise_for_status()
h = {"Authorization": f"Bearer {r.json()['token']}"}
print("1) Đăng nhập tacgia@vietread.vn OK")

r = c.post("/stories", json={"title": "Demo Gợi Ý Nghĩa Qidian"}, headers=h)
r.raise_for_status()
sid = r.json()["id"]
print(f"2) Tạo truyện demo id={sid}")

r = c.post(f"/stories/{sid}/chapters/import",
           json={"chapterUrl": QIDIAN}, headers=h)
if r.status_code != 200:
    print("   Import lỗi:", r.status_code, r.text[:300])
    c.delete(f"/stories/{sid}", headers=h)
    sys.exit(1)
ch = r.json()
print(f"3) Import + dịch chương {ch['index']} — {ch['title'][:60]}")

raw = c.get(f"/chapters/{ch['id']}", params={"raw": 1}, headers=h).json()["content"]
markers = re.findall(r"\{([^{}]+)\}", raw)
print(f"4) Số marker gợi ý nghĩa: {len(markers)} chỗ")
print("   10 ví dụ marker:")
for m in markers[:10]:
    print("   -", m)

# Dịch lại có gợi ý (không tự lưu)
r = c.post(f"/chapters/{ch['id']}/retranslate", headers=h)
r.raise_for_status()
markers2 = re.findall(r"\{([^{}]+)\}", r.json()["content"])
print(f"5) /retranslate → {len(markers2)} marker (nội dung trả về để nạp màn Sửa chương, KHÔNG tự lưu)")

# Tìm & thay thế trên chính chương này
words = re.findall(r"[^\s.,!?…\"':;\-—()\[\]{}|]+", re.sub(r"\{[^{}]+\}", " ", raw))
common = max(set(words), key=words.count) if words else ""
print(f"6) Thay tên hàng loạt — chuỗi hay nhất trong bản dịch: '{common}'")
dry = c.post(f"/stories/{sid}/replace", json={"find": common, "replace": common + " Test", "dryRun": True}, headers=h)
dry.raise_for_status()
d = dry.json()
print(f"   dryRun: {d['totalMatches']} chỗ trong {len(d['chapters'])} chương")
run = c.post(f"/stories/{sid}/replace", json={"find": common, "replace": common + " Test"}, headers=h)
run.raise_for_status()
u = run.json()
print(f"   thay thật: {u['totalMatches']} chỗ, {u['chaptersChanged']} chương, batchId={u['batchId']}")
raw2 = c.get(f"/chapters/{ch['id']}", params={"raw": 1}, headers=h).json()["content"]
print(f"   kiểm tra nội dung chứa '{common} Test': {'Test' in raw2}")

undo = c.post(f"/stories/{sid}/replace/undo", headers=h)
undo.raise_for_status()
print(f"7) undo: {undo.json()['message']}")
raw3 = c.get(f"/chapters/{ch['id']}", params={"raw": 1}, headers=h).json()["content"]
print(f"   nội dung khớp bản trước thay thế: {raw3 == raw}")

c.delete(f"/stories/{sid}", headers=h)
print("8) Đã xoá truyện demo")
