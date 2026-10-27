# -*- coding: utf-8 -*-
"""Golden test dịch offline — so khớp TỪNG BYTE đầu ra convert() 3 mức.

Đầu vào: `tests_golden/translate_cases.json` (3 chương qidian thật, sinh bằng
`_make_golden.py`). Đầu ra chuẩn: `tests_golden/translate_golden.json`.
Chạy hoàn toàn offline (không DB, không mạng) — mọi thay đổi trong
`vietphrase.convert_lines` / bộ lọc marker khiến test fail ngay.

Chạy:  PYTHONUTF8=1 .venv/Scripts/python.exe test_golden_translate.py
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.getcwd())

from app import vietphrase  # noqa: E402

BASE = os.path.dirname(os.path.abspath(__file__))
GOLDEN_DIR = os.path.join(BASE, "tests_golden")
LEVELS = ("low", "medium", "high")
PASSED = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global PASSED
    if not ok:
        raise AssertionError(f"FAILED — {label} {detail[:400]}")
    PASSED += 1
    print(f"  OK  {label}")


def main() -> None:
    with open(os.path.join(GOLDEN_DIR, "translate_cases.json"), encoding="utf-8") as f:
        cases = json.load(f)
    with open(os.path.join(GOLDEN_DIR, "translate_golden.json"), encoding="utf-8") as f:
        golden = json.load(f)

    check("có đủ 3 chương mẫu", len(cases) == 3, str(len(cases)))

    for case in cases:
        idx = str(case["index"])
        lines = case["source"].splitlines() or [case["source"]]
        for level in LEVELS:
            out = "\n".join(
                vietphrase.convert_lines(
                    lines, mark_alternatives=True, mark_level=level
                )
            )
            expected = golden[idx][level]
            check(
                f"chương {idx} mức {level}: khớp từng byte",
                out == expected,
                f"len {len(out)} vs {len(expected)}",
            )


if __name__ == "__main__":
    main()
    print(f"\nTẤT CẢ {PASSED} KIỂM TRA GOLDEN ĐỀU PASS ✔")
