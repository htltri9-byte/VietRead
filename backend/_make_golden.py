# -*- coding: utf-8 -*-
"""Sinh golden test dịch — 3 chương qidian thật × 3 mức gợi ý (TRƯỚC refactor).

Chỉ chạy khi muốn TẠO LẠI golden (đổi dữ liệu từ điển có chủ đích):
  PYTHONUTF8=1 .venv/Scripts/python.exe _make_golden.py

Sinh `tests_golden/translate_cases.json` (đầu vào) +
`tests_golden/translate_golden.json` (đầu ra low/medium/high).
`test_golden_translate.py` so khớp từng byte — chạy offline, không cần DB/mạng.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.getcwd())

from app import vietphrase  # noqa: E402
from app.database import SessionLocal  # noqa: E402
from app.models import Chapter  # noqa: E402

STORY_ID = 229  # “Từ bang phái lưu manh bắt đầu võ đạo thành thánh” (qidian thật)
CHAPTERS = (1, 2, 3)
LEVELS = ("low", "medium", "high")
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests_golden")


def main() -> None:
    db = SessionLocal()
    cases: list[dict] = []
    for idx in CHAPTERS:
        row = (
            db.query(Chapter)
            .filter(Chapter.story_id == STORY_ID, Chapter.chapter_index == idx)
            .first()
        )
        if row is None or not row.original_content:
            raise SystemExit(f"Thiếu OriginalContent chương {idx} của truyện {STORY_ID}")
        cases.append({"index": idx, "source": row.original_content})
    db.close()

    golden: dict[str, dict[str, str]] = {}
    for case in cases:
        lines = case["source"].splitlines() or [case["source"]]
        per_level: dict[str, str] = {}
        for level in LEVELS:
            out = "\n".join(
                vietphrase.convert_lines(
                    lines, mark_alternatives=True, mark_level=level
                )
            )
            per_level[level] = out
        golden[str(case["index"])] = per_level
        counts = {lv: per_level[lv].count("{") for lv in LEVELS}
        print(f"chương {case['index']}: {len(case['source'])} ký tự, marker {counts}")

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(
        os.path.join(OUT_DIR, "translate_cases.json"), "w", encoding="utf-8"
    ) as f:
        json.dump(cases, f, ensure_ascii=False, indent=1)
    with open(
        os.path.join(OUT_DIR, "translate_golden.json"), "w", encoding="utf-8"
    ) as f:
        json.dump(golden, f, ensure_ascii=False, indent=1)
    print("Đã ghi:", OUT_DIR)


if __name__ == "__main__":
    main()
