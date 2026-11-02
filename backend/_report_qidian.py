# -*- coding: utf-8 -*-
"""Báo cáo chương qidian THẬT (offline, không gọi mạng):

1. TRƯỚC: số marker còn chữ Hán trong Content ĐÃ LƯU (dữ liệu cũ {中文|…}).
2. SAU: sau [alternatives.normalize] — đúng phép endpoint POST /markers/clean
   (đo trên bản sao, không ghi DB) — còn bao nhiêu marker / bao nhiêu chữ Hán.
3. Mỗi mức Ít/Vừa/Nhiều: số marker sinh ra từ OriginalContent của chương
   qidian thật — so với trần 15/40 — ở 2 chế độ: CÓ seed (hiện tại) và
   KHÔNG seed (bộ lọc cũ thuần).
4. 15 ví dụ marker còn lại ở mức Ít.

Chạy:  PYTHONUTF8=1 .venv/Scripts/python.exe _report_qidian.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.getcwd())

from app import alternatives, marking, vietphrase  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.models import Chapter  # noqa: E402

STORY_ID = 229  # “Từ bang phái lưu manh bắt đầu võ đạo thành thánh” (qidian thật)


def cjk_markers(text: str) -> list[str]:
    return [m.text for m in alternatives.parse(text) if alternatives.has_cjk(m.text)]


def main() -> None:
    db = SessionLocal()
    chapters = (
        db.query(Chapter)
        .filter(Chapter.story_id == STORY_ID)
        .order_by(Chapter.chapter_index)
        .all()
    )
    db.close()

    # ---------- 1/2. TRƯỚC vs SAU (dữ liệu Content đã lưu) ----------
    before_total = before_cjk = 0
    after_total = after_cjk = 0
    examples: list[str] = []
    for ch in chapters:
        before = ch.content
        after = alternatives.normalize(before)
        bm, am = alternatives.parse(before), alternatives.parse(after)
        before_total += len(bm)
        before_cjk += len(cjk_markers(before))
        after_total += len(am)
        after_cjk += len(cjk_markers(after))
        for m in am:
            if len(examples) < 10:
                examples.append(m.text)

    print(f"=== QIDIAN story {STORY_ID}: {len(chapters)} chương ===")
    print(f"TRƯỚC (Content lưu, dạng cũ): {before_total} marker, "
          f"{before_cjk} marker còn chữ Hán")
    print(f"SAU  (normalize = phép markers/clean): {after_total} marker, "
          f"{after_cjk} marker còn chữ Hán")
    print("10 ví dụ marker dạng mới (sau dọn):")
    for i, ex in enumerate(examples[:10], 1):
        print(f"  {i:2}. {ex}")

    # ---------- 3. Mỗi mức trên OriginalContent thật ----------
    target = next((c for c in chapters if c.original_content and
                   len(c.original_content) > 500), chapters[0])
    src = target.original_content
    lines = src.splitlines() or [src]
    print(f"\n=== MỨC GỢI Ý trên OriginalContent chương {target.chapter_index} "
          f"({len(src)} ký tự, {len(lines)} dòng) ===")

    def count_level(level: str) -> int:
        out = "\n".join(
            vietphrase.convert_lines(
                lines, mark_alternatives=True, mark_level=level
            )
        )
        return alternatives.count(out)

    # (a) HIỆN TẠI — có seed + luật offline
    real = marking.get_lists()
    print(f"(a) CÓ seed (hiện tại): ambiguous={len(real.ambiguous)} "
          f"synonyms={len(real.synonyms)} no_mark={len(real.no_mark)}")
    cur: dict[str, int] = {}
    for level in ("low", "medium", "high"):
        cur[level] = count_level(level)
        cap = marking.cap_for(level)
        print(f"    {level:6}: {cur[level]:3} marker"
              f"{'  (trần ' + str(cap) + ')' if cap is not None else '  (không giới hạn)'}"
              f" → {'ĐÚNG trần' if cap is None or cur[level] <= cap else 'VƯỢT TRẦN!'}")

    # (b) KHÔNG seed (bộ lọc cũ thuần) — so sánh trước/sau
    real_dir = marking.DICT_DIR
    empty = marking.DICT_DIR / "_report_empty"
    empty.mkdir(exist_ok=True)
    try:
        marking.DICT_DIR = empty
        marking.reload_lists()
        print("(b) KHÔNG seed (bộ lọc nghiêm ngặt thuần):")
        for level in ("low", "medium", "high"):
            n = count_level(level)
            print(f"    {level:6}: {n:3} marker")
    finally:
        marking.DICT_DIR = real_dir
        marking.reload_lists()
        try:
            os.rmdir(empty)
        except OSError:
            pass

    # ---------- 4. 15 ví dụ marker mức Ít ----------
    out_low = "\n".join(
        vietphrase.convert_lines(lines, mark_alternatives=True, mark_level="low")
    )
    low_markers = [m.text for m in alternatives.parse(out_low)]
    print(f"\n=== 15 ví dụ marker mức Ít (thực tế {len(low_markers)} chỗ) ===")
    for i, ex in enumerate(low_markers[:15], 1):
        flag = "  ← CHỮ HÁN!" if alternatives.has_cjk(ex) else ""
        print(f"  {i:2}. {ex}{flag}")
    assert not any(alternatives.has_cjk(m) for m in low_markers), \
        "Có marker mức Ít vẫn chứa chữ Hán!"


if __name__ == "__main__":
    main()
