"""Chứng minh chế độ dịch TỪ ĐIỂN (TRANSLATE_MODE=dict) HOÀN TOÀN OFFLINE.

Chạy (không cần server đang chạy — TestClient chạy in-process):
    cd backend && PYTHONUTF8=1 .venv/Scripts/python.exe test_offline.py

Hai lớp chứng minh:
1) TĨNH — quét module trên đường dịch từ điển (`vietphrase.py`, `marking.py`,
   `alternatives.py`): không import thư viện mạng nào (requests/httpx/urllib/
   aiohttp/socket...). Từ điển + luật offline là đủ.
2) ĐỘNG — mock socket: chặn MỌI kết nối TCP không phải loopback trong lúc chạy
   toàn bộ các bước dịch/đánh dấu qua API in-process:
     - POST /stories/{id}/chapters/import-text (zh) — bước dịch khi import
     - POST /chapters/{id}/retranslate              — dịch lại
     - translate_text(...) trực tiếp                 — lõi dịch
   Mọi bước phải chạy xong (không lỗi, không lời gọi mạng bị chặn). Vòng lặp
   chỉ cho phép loopback (SQL Server local qua ODBC/shared memory) — mọi kết
   nối ra internet sẽ bị chặn và làm test fail ngay.

Yêu cầu: backend/.env trỏ SQL Server đang chạy + tài khoản seed
tacgia@vietread.vn (cùng tài khoản test_api.py dùng).
"""

from __future__ import annotations

import ipaddress
import os
import socket
import sys

# Chế độ từ điển — phải set TRƯỚC khi chạy các bước dịch (translator đọc mỗi lần gọi).
os.environ["TRANSLATE_MODE"] = "dict"

PASSED = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global PASSED
    if not ok:
        raise AssertionError(f"FAILED — {label} {detail}")
    PASSED += 1
    print(f"  OK  {label}")


# ---------------------------------------------------------------------------
# 1) Tĩnh: module đường dịch từ điển không import thư viện mạng
# ---------------------------------------------------------------------------

NETWORK_MODULES = ("requests", "httpx", "urllib", "aiohttp", "socket", "http.client")

print("\n=== 1) TĨNH — quét import mạng trong module dịch từ điển ===")
for rel in ("app/vietphrase.py", "app/marking.py", "app/alternatives.py"):
    src = open(rel, encoding="utf-8").read()
    hits = []
    for line in src.splitlines():
        stripped = line.strip()
        if stripped.startswith(("import ", "from ")) and any(
            net in stripped for net in NETWORK_MODULES
        ):
            hits.append(stripped)
    check(f"{rel} không import thư viện mạng", not hits, str(hits))

# ---------------------------------------------------------------------------
# 2) Động: chặn socket ngoại luồng, chạy các bước dịch qua API in-process
# ---------------------------------------------------------------------------

print("\n=== 2) ĐỘNG — mock socket chặn mạng + gọi API in-process ===")

_seen: list[str] = []
_blocked: list[str] = []


def _is_loopback(host: str) -> bool:
    if host in ("localhost", "::1", "127.0.0.1") or host.startswith("127."):
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False  # hostname lạ (không phải localhost) = coi như ngoài


def _guard_address(addr) -> None:
    host = addr[0] if isinstance(addr, (tuple, list)) else str(addr)
    _seen.append(str(host))
    if not _is_loopback(str(host)):
        _blocked.append(str(addr))
        raise OSError(f"OFFLINE-TEST: chặn kết nối ra ngoài {addr!r}")


_real_connect = socket.socket.connect
_real_create_connection = socket.create_connection


def _guarded_connect(self, addr):  # noqa: ANN001
    _guard_address(addr)
    return _real_connect(self, addr)


def _guarded_create_connection(address, *args, **kwargs):  # noqa: ANN001
    _guard_address(address)
    return _real_create_connection(address, *args, **kwargs)


socket.socket.connect = _guarded_connect  # type: ignore[method-assign]
socket.create_connection = _guarded_create_connection  # type: ignore[assignment]

ok_all = False
try:
    from fastapi.testclient import TestClient  # sau khi chặn socket sẵn

    from app import alternatives, vietphrase
    from app.main import app

    with TestClient(app) as c:
        # Đăng nhập seed (in-process, không qua mạng)
        r = c.post("/auth/login",
                   json={"email": "tacgia@vietread.vn", "password": "VietRead@123"})
        check("login seed tacgia (in-process)", r.status_code == 200, r.text[:300])
        h = {"Authorization": f"Bearer {r.json()['token']}"}

        r = c.post("/stories", json={"title": "Kiểm thử OFFLINE dict"}, headers=h)
        check("tạo truyện test = 200", r.status_code == 200, r.text)
        sid = r.json()["id"]

        # (a) Import chương zh — bước dịch khi import, dưới socket bị chặn
        r = c.post(f"/stories/{sid}/chapters/import-text",
                   json={"text": "他见过她三次，天气似乎很好。", "sourceLang": "zh",
                         "chapterNo": 1, "title": "Chương offline"},
                   headers=h)
        check("import-text dịch offline = 200", r.status_code == 200, r.text[:300])
        ch = r.json()["id"]
        raw = c.get(f"/chapters/{ch}?raw=1", headers=h).json()["content"]
        _mk = alternatives.parse(raw)
        check("bản dịch có marker nhiều nghĩa (chỉ từ điển, không AI)",
              len(_mk) >= 1, raw[:200])
        check("mọi marker không chứa ký tự CJK",
              not any(alternatives.has_cjk(m.text) for m in _mk), raw[:200])

        # (b) Dịch lại chương — mặt trận retranslate
        r = c.post(f"/chapters/{ch}/retranslate",
                   json={"markLevel": "medium"}, headers=h)
        _mk2 = alternatives.parse(r.json().get("content", "")) if r.status_code == 200 else []
        check("retranslate offline = 200, có marker không chữ Hán",
              r.status_code == 200 and len(_mk2) >= 1
              and not any(alternatives.has_cjk(m.text) for m in _mk2),
              r.text[:300])

        check("dọn truyện test = 200",
              c.delete(f"/stories/{sid}", headers=h).status_code == 200)

    # (c) Lõi dịch trực tiếp dưới socket bị chặn
    out = vietphrase.convert("他见过她。", mark_alternatives=True, mark_level="low")
    check("translate_text (vietphrase.convert) chạy offline", "{" in out, out)

    check(f"không có kết nối RA INTERNET nào bị thử ({len(_seen)} lần kết nối"
          f" toàn cục — chỉ loopback/pipe)",
          not _blocked, str(_blocked))
    ok_all = True
finally:
    socket.socket.connect = _real_connect  # type: ignore[method-assign]
    socket.create_connection = _real_create_connection  # type: ignore[assignment]

print(f"\nTẤT CẢ {PASSED} KIỂM TRA OFFLINE ĐỀU PASS ✔")
print("=> Dịch/đánh dấu ở chế độ dict không dựa vào mạng: "
      "0 lời gọi mạng ngoài, chặn tại tầng socket.")
sys.exit(0 if ok_all else 1)