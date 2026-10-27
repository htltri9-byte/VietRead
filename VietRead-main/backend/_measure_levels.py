# Đo chương Qidian THẬT với từng mức gợi ý nghĩa (trước / sau):
#   trước  = dịch KHÔNG marker (hành vi trước khi có gợi ý nhiều nghĩa)
#   low / medium / high = dịch CÓ marker theo trần của mức (15 / 40 / không giới hạn)
#   thêm: số chỗ còn lại sau khi "lấy nghĩa đầu" (resolve) + ví dụ marker.
# Chạy: cd backend && PYTHONUTF8=1 .venv/Scripts/python.exe _measure_levels.py
import re
import time

from app import alternatives, marking
from app.services import translator
from app.services.scraper import get_adapter

URL = "https://m.qidian.com/chapter/1040765595/806596284/"  # 第1章 永夜 (miễn phí)


def main() -> None:
    adapter = get_adapter(URL)
    if adapter is None:
        raise SystemExit(f"Không có adapter cho {URL}")
    parsed = adapter.parse_chapter(URL)
    zh = parsed.content
    print(f"Chương thật : {parsed.title}")
    print(f"Nguồn       : {URL}")
    print(f"Độ dài gốc  : {len(zh)} ký tự Trung")
    print(f"Mặc định    : MARK_LEVEL={marking.default_level()!r}\n")

    # Warm-up nạp từ điển (lần đầu đọc cache) để thời gian các mức so sánh được
    translator.translate_text("你好。", "vi", mark_alternatives=False)

    rows: list[tuple[str, int | None, float, str]] = []
    t0 = time.perf_counter()
    plain = translator.translate_text(zh, "vi", mark_alternatives=False)
    rows.append(("trước — không gợi ý", alternatives.count(plain),
                 time.perf_counter() - t0, plain))

    outs: dict[str, str] = {}
    for level in marking.LEVELS:
        t0 = time.perf_counter()
        out = translator.translate_text(
            zh, "vi", mark_alternatives=True, mark_level=level,
        )
        outs[level] = out
        rows.append((f"sau — {level}", alternatives.count(out),
                     time.perf_counter() - t0, out))

    width = max(len(label) for label, _, _, _ in rows)
    print(f"{'Mức':<{width}}  {'Marker':>7}  {'Trần':>5}  {'Thời gian':>9}  Đúng trần")
    for i, (label, n, dt, _) in enumerate(rows):
        if i == 0:
            cap_s, ok = "—", "—"
        else:
            cap = marking.cap_for(marking.LEVELS[i - 1])
            cap_s = "∞" if cap is None else str(cap)
            ok = "✓" if cap is None or n <= cap else "✗ (vượt trần!)"
        print(f"{label:<{width}}  {n:>7}  {cap_s:>5}  {dt:>8.2f}s  {ok}")

    # Sau "lấy nghĩa đầu" — resolve về nghĩa đầu tiên
    resolved = alternatives.resolve(outs["high"])
    print(
        f"\nResolve (lấy nghĩa đầu) bản high : {alternatives.count(resolved)} marker"
        f" — khớp bản không-marker: {resolved == plain}"
    )

    samples = re.findall(r"\{[^{}]+\}", outs["medium"])
    print(f"\nVí dụ marker ở mức medium ({len(samples)} chỗ):")
    for s in samples[:8]:
        print("  -", s)


if __name__ == "__main__":
    main()
