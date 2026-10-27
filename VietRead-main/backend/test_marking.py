"""Test bộ lọc marker nhiều nghĩa — bộ lọc bước 1-7 + 3 mức gợi ý (marking.py).

Chạy (không cần server, chỉ cần từ điển):
    PYTHONUTF8=1 .venv/Scripts/python.exe test_marking.py

Bao phủ đúng yêu cầu:
- `đường chủ|Đường chủ` (chỉ khác hoa/thường) → KHÔNG thành marker;
- `mặt khác|những khác|cái khác|khác` (chứa nhau) → KHÔNG thành marker;
- `lưu manh|vô lại|côn đồ` nếu nằm trong synonyms.txt → KHÔNG thành marker;
- khóa trong ambiguous.txt → THÀNH marker; khóa một chữ / no_mark.txt → không;
- tên riêng (names.txt) không đánh dấu ở mức Ít/Vừa;
- trần 15 (low) / 40 (medium) / không giới hạn (high) đúng;
- marker cũ {vì:là:vi} vẫn resolve; marker mới chỉ chứa NGHĨA VIỆT (không chữ Hán),
  dữ liệu cũ {中文|a|b} parse được nhưng tách khóa cũ ra, không hiển thị;
- key_choices / skip_keys (nghĩa đã chọn, không hỏi lại theo truyện).
"""

from __future__ import annotations

import sys

from app import alternatives, marking, vietphrase

PASSED = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global PASSED
    if not ok:
        raise AssertionError(f"FAILED — {label} {detail}")
    PASSED += 1
    print(f"  OK  {label}")


class _TempLists:
    """Đè 3 file danh sách trong lúc test rồi trả về trạng thái cũ."""

    def __init__(
        self,
        no_mark: set[str] | None = None,
        ambiguous: set[str] | None = None,
        synonyms: set[str] | None = None,
    ) -> None:
        self._new = marking.MarkLists(
            no_mark=frozenset(no_mark or set()),
            ambiguous=frozenset(ambiguous or set()),
            synonyms=frozenset(synonyms or set()),
            mtimes=marking._mtimes(),  # khớp mtime file thật → get_lists không tự nạp đè
        )
        self._old: marking.MarkLists | None = None

    def __enter__(self) -> marking.MarkLists:
        self._old = marking._lists
        marking._lists = self._new
        return self._new

    def __exit__(self, *exc) -> None:
        marking._lists = self._old


def evaluate(key, kind, meanings, level, lists, hinted=frozenset()):
    return marking.evaluate(key, kind, meanings, level, lists, hinted)


print("\n=== BƯỚC 1: chống trùng theo chuẩn hóa ===")
check(
    "đường chủ|Đường chủ gộp còn 1 nghĩa",
    marking.merge_similar(["Đường chủ", "đường chủ"]) == ["Đường chủ"],
)
with _TempLists() as lists:
    ok, merged = evaluate(
        "堂主", "phrase", ["Đường chủ", "đường chủ"], "medium", lists
    )
    check("堂主 chỉ khác hoa thường → không marker", not ok and len(merged) == 1)
    ok, merged = evaluate("堂主", "phrase", ["đường chủ "], "low", lists)
    check("thừa dấu cách + hoa thường vẫn gộp", not ok)

print("\n=== BƯỚC 2: gộp nghĩa gần giống (chứa nhau / ≥50% âm tiết) ===")
merged = marking.merge_similar(["mặt khác", "những khác", "cái khác", "khác"])
check(
    "mặt khác|những khác|cái khác|khác gộp còn 1 nghĩa (giữ nghĩa đầu)",
    len(merged) == 1 and merged[0] == "mặt khác",
    str(merged),
)
check(
    "dường như|hình như gộp (chia sẻ 'như' ≥50%), giữ nghĩa đầu",
    marking.merge_similar(["dường như", "hình như"]) == ["dường như"],
    str(marking.merge_similar(["dường như", "hình như"])),
)
check(
    "trận|tràng|cuộc KHÔNG bị gộp oan (không chứa nhau, 0% âm tiết trùng)",
    marking.merge_similar(["trận", "tràng", "cuộc"]) == ["trận", "tràng", "cuộc"],
)
check("nghĩa trống bị loại", marking.merge_similar(["  ", "a", ""]) == ["a"])

print("\n=== BƯỚC 3-5: no_mark / khóa một chữ / tên riêng ===")
with _TempLists(no_mark={"因为"}) as lists:
    ok, _ = evaluate("因为", "phrase", ["bởi vì", "vì"], "medium", lists)
    check("khóa trong no_mark.txt → không marker", not ok)
    ok, _ = evaluate("没有", "phrase", ["không có", "chưa có"], "low", lists)
    check("mức Ít (ambiguous trống) cũng loại no_mark", not ok)

with _TempLists() as lists:
    ok, _ = evaluate("有", "phrase", ["có", "hữu"], "medium", lists)
    check("khóa một chữ Hán → không marker", not ok)
    ok, _ = evaluate("三", "phrase", ["ba", "tam"], "low", lists)
    check("khóa một chữ ở mức Ít → không marker", not ok)

with _TempLists() as lists:
    ok, _ = evaluate("李明", "name", ["Lý Minh", "Lý Mẫn"], "medium", lists)
    check("tên riêng (kind=name) → không marker ở mức Vừa", not ok)

print("\n=== BƯỚC 6: ambiguous (trắng) / synonyms (đen) ===")
with _TempLists(ambiguous={"拜见"}, synonyms={"流氓"}) as lists:
    ok, _ = evaluate("拜见", "phrase", ["bái kiến", "chào"], "low", lists)
    check("khóa trong ambiguous.txt → marker ở mức Ít", ok)
    ok, _ = evaluate("流氓", "phrase", ["lưu manh", "vô lại"], "medium", lists)
    check("khóa trong synonyms.txt → không marker ở mức Vừa", not ok)
    ok, _ = evaluate("流氓", "phrase", ["lưu manh", "vô lại"], "high", lists)
    check("mức Nhiều: chỉ áp gộp trùng (vẫn marker)", ok)
    ok, _ = evaluate("李明", "name", ["Lý Minh", "Lý Mẫn"], "low", lists)
    check("mức Ít có whitelist → tên riêng không whitelist không marker", not ok)

with _TempLists() as lists:  # ambiguous TRỐNG → bộ lọc nghiêm ngặt (đúng yêu cầu)
    ok, _ = evaluate("见过", "phrase", ["bái kiến", "ra mắt", "gặp qua"], "low", lists)
    check("ambiguous.txt trống → mức Ít dùng bộ lọc nghiêm ngặt (được marker)", ok)

print("\n=== LUẬT CŨ {a:b} trong vietphrase.txt (mục 0) ===")
vietphrase.load(force=True)
check(
    "6 khóa có luật cũ được ghi nhận",
    {"一顿", "不为", "为", "定为", "当", "等"} <= vietphrase._hinted_keys,
    str(sorted(vietphrase._hinted_keys)),
)
with _TempLists() as lists:  # không có trong ambiguous.txt nhưng là luật cũ
    ok, _ = evaluate("为", "phrase", ["vì", "là", "làm", "vi"], "low", lists,
                     hinted=vietphrase._hinted_keys)
    check("luật cũ {vì:là} vẫn marker ở mức Ít", ok)

print("\n=== MARKER: chỉ nghĩa Việt + dữ liệu cũ {中文|…} đọc được ===")
built = alternatives.build(["vì", "là"])
check("build KHÔNG kèm khóa → {vì|là}", built == "{vì|là}", built)
marker = alternatives.parse(f"x {built} y")[0]
check("marker mới: key=None, không chữ Hán",
      marker.key is None and not alternatives.has_cjk(marker.text))
check("resolve lấy nghĩa đầu", alternatives.resolve(f"a {built} b") == "a vì b")
# Dữ liệu cũ trong DB (khóa nằm ở segment đầu) → đọc được, không hiển thị
legacy = "{为|vì|là}"
lm = alternatives.parse(f"x {legacy} y")[0]
check("dữ liệu cũ: tách khóa cũ + nghĩa Việt",
      lm.key == "为" and lm.meanings == ("vì", "là"), str(lm))
check("dữ liệu cũ: resolve bỏ chữ Hán, lấy nghĩa đầu",
      alternatives.resolve(f"a {legacy} b") == "a vì b",
      alternatives.resolve(f"a {legacy} b"))
check("normalize dữ liệu cũ → dạng sạch",
      alternatives.normalize(legacy) == "{vì|là}", alternatives.normalize(legacy))
check("sau khi loại còn 1 nghĩa → không còn marker, bỏ {}",
      alternatives.normalize("a {为|vì} b") == "a vì b"
      and alternatives.count("a {为|vì} b") == 0)
check("normalize marker sạch giữ nguyên (idempotent)",
      alternatives.normalize("a {vì|là} b") == "a {vì|là} b")
check(
    "dạng cũ {vì:là:vi} vẫn resolve lấy nghĩa đầu",
    alternatives.resolve("{vì:là:vi}") == "vì",
    alternatives.resolve("{vì:là:vi}"),
)
check(
    "dạng cũ không có chữ Trung → key=None",
    alternatives.parse("{vì:là:vi}")[0].key is None,
)
check(
    "count đếm cả marker dữ liệu cũ (đủ 2+ nghĩa Việt)",
    alternatives.count(f"{legacy} {{a|b}}") == 2,
)

print("\n=== convert: key_choices / skip_keys (nghĩa theo truyện) ===")
text = "为是好人。"
plain = vietphrase.convert(text)
# Marker của 为 ở mức cao — dạng MỚI chỉ gồm nghĩa Việt (dùng để so trong kết quả)
_ok_w, merged_w = evaluate(
    "为", "phrase", list(vietphrase._vp_alts["为"]), "high", marking.get_lists(),
    hinted=vietphrase._hinted_keys,
)
wei_marker = alternatives.build(merged_w)
check("marker của 为 không chứa chữ Hán",
      bool(wei_marker) and not alternatives.has_cjk(wei_marker), wei_marker)
with _TempLists() as _:
    marked = vietphrase.convert(text, mark_alternatives=True, mark_level="high")
    check("bật marker → có marker, mọi marker không chữ Hán",
          alternatives.count(marked) >= 1
          and not any(alternatives.has_cjk(m.text) for m in alternatives.parse(marked)),
          marked)
    chosen = vietphrase.convert(
        text,
        mark_alternatives=True,
        mark_level="high",
        key_choices={"为": "bởi"},
    )
    check("key_choices → dùng nghĩa đã chọn, không marker của 为",
          "bởi" in chosen.lower() and wei_marker not in chosen, chosen)
    skipped = vietphrase.convert(
        text,
        mark_alternatives=True,
        mark_level="high",
        skip_keys={"为"},
    )
    check("skip_keys → lấy nghĩa đầu, không marker của 为",
          wei_marker not in skipped and skipped.lower().startswith("vì"), skipped)

print("\n=== BƯỚC 7: trần 15 / 40 / không giới hạn (chương thật, từ điển thật) ===")
lists_real = marking.get_lists()
user_amb = marking._read_keys(marking.DICT_DIR / marking.AMBIGUOUS_FILE)
user_syn = marking._read_keys(marking.DICT_DIR / marking.SYNONYMS_FILE)
check("file người dùng ambiguous.txt đang trống (whitelist đến từ seed)",
      len(user_amb) == 0, f"amb={len(user_amb)}")
check(f"file người dùng synonyms.txt nạp được ({len(user_syn)} khóa người dùng)",
      len(user_syn) >= 15, f"syn={len(user_syn)}")
check(f"seed nạp vào whitelist (≥200 khóa, thực tế {len(lists_real.ambiguous)})",
      len(lists_real.ambiguous) >= 200)
check(f"seed nạp vào deny-list (≥100 khóa, thực tế {len(lists_real.synonyms)})",
      len(lists_real.synonyms) >= 100)

# Chương test trần: ghép từ khóa ĐA NGHĨA có trong whitelist (seed) —
# mức Ít/Vừa chỉ đánh dấu whitelisted nên cần ≥40 khóa whitelisted trong chương
whitelisted = [
    k for k in lists_real.ambiguous
    if len(k) >= 2 and k in vietphrase._vp_alts
    and len(vietphrase._vp_alts[k]) >= 2
]
check("whitelist có ≥60 khóa nhiều chữ nhiều nghĩa để test trần",
      len(whitelisted) >= 60, str(len(whitelisted)))
chapter = "".join(whitelisted[:150])
counts = {}
for level in ("low", "medium", "high"):
    out = "\n".join(
        vietphrase.convert_lines([chapter, chapter], mark_alternatives=True,
                                 mark_level=level)
    )
    counts[level] = alternatives.count(out)
check(f"mức Ít = đúng trần 15 (thực tế {counts['low']})", counts["low"] == 15)
check(f"mức Vừa = đúng trần 40 (thực tế {counts['medium']})", counts["medium"] == 40)
check(
    f"mức Nhiều ≈ hành vi cũ, nhiều hơn mức Vừa ({counts['high']} > {counts['medium']})",
    counts["high"] > counts["medium"],
)
# Marker chuẩn của 场 (dạng mới, chỉ nghĩa Việt) — so đúng chuỗi này trong kết quả
_ok_c, merged_c = evaluate(
    "场", "phrase", list(vietphrase._vp_alts.get("场") or ["trận"]),
    "medium", lists_real,
)
chang_marker = alternatives.build(merged_c)
check("marker của 场 không chứa chữ Hán",
      bool(chang_marker) and not alternatives.has_cjk(chang_marker), chang_marker)
med_out = vietphrase.convert("他来到场。", mark_alternatives=True, mark_level="medium")
high_out = vietphrase.convert("他来到场。", mark_alternatives=True, mark_level="high")
check(
    "trận|tràng|cuộc... (synonyms.txt) không marker ở mức Vừa",
    chang_marker not in med_out,
    med_out,
)
check(
    "…nhưng mức Nhiều vẫn giữ marker (dạng mới, không chữ Hán)",
    chang_marker in high_out
    and not any(alternatives.has_cjk(m.text) for m in alternatives.parse(high_out)),
    high_out,
)

print("\n=== Ví dụ BẮT BUỘC từ đề bài: không marker ở mức Ít/Vừa ===")
# Dùng danh sách THẬT (user + seed) — không sửa file trong test
real = marking.get_lists()
required_no_marker = [
    ("场", ["trận", "tràng", "cuộc", "cơn", "đợt", "màn"]),
    ("其他", ["mặt khác", "những khác", "cái khác", "khác"]),
    ("混混儿", ["lưu manh", "vô lại", "côn đồ"]),
    ("似乎", ["tựa hồ", "dường như", "hình như"]),
    ("堂主", ["Đường chủ", "đường chủ"]),
    ("有", ["có", "hữu"]),
    ("三", ["ba", "tam"]),
    ("阴沉", ["âm trầm", "u ám"]),
    ("镔铁", ["thép ròng", "thép tinh luyện"]),
]
for zkey, means in required_no_marker:
    for lvl in ("low", "medium"):
        ok, merged = evaluate(zkey, "phrase", means, lvl, real)
        check(f"{zkey} [{'|'.join(means)[:28]}…] KHÔNG marker ở {lvl}", not ok,
              f"merged={merged}")

print("\n=== Khóa đa nghĩa THẬT trong ambiguous.seed.txt → marker ở Ít/Vừa ===")
seed_keys = marking._read_keys(
    marking.DICT_DIR / marking.AMBIGUOUS_SEED_FILE
)
check("ambiguous.seed.txt có ≥200 khóa", len(seed_keys) >= 200, str(len(seed_keys)))
for zkey in ("见过", "意思", "东西"):
    check(f"{zkey} có trong ambiguous.seed", zkey in seed_keys)
    alts = list(vietphrase._vp_alts.get(zkey) or [])
    if not alts:
        continue
    for lvl in ("low", "medium"):
        ok, _ = evaluate(zkey, "phrase", alts, lvl, real)
        check(f"{zkey} THÀNH marker ở {lvl} (seed whitelist)", ok)

syn_seed = marking._read_keys(marking.DICT_DIR / marking.SYNONYMS_SEED_FILE)
check("synonyms.seed.txt có ≥100 khóa", len(syn_seed) >= 100, str(len(syn_seed)))

print("\n=== File seed thiếu/rỗng → không lỗi, không vượt trần ===")
import pathlib as _pl
import os as _os
_real_dir = marking.DICT_DIR
_empty = _real_dir / "_test_empty"
_empty.mkdir(exist_ok=True)
try:
    marking.DICT_DIR = _empty
    m = marking.reload_lists()
    check("thieu toan bo 5 file → 3 danh sach rong, không exception",
          len(m.no_mark) == 0 and len(m.ambiguous) == 0 and len(m.synonyms) == 0)
    # Dịch với danh sách rỗng vẫn tôn trọng trần 15/40
    cand = [k for k, v in vietphrase._vp_alts.items()
            if len(k) >= 2 and len(v) >= 2][:150]
    ch = "".join(cand)
    for lvl, cap in (("low", 15), ("medium", 40)):
        out = "\n".join(vietphrase.convert_lines(
            [ch, ch], mark_alternatives=True, mark_level=lvl))
        n = alternatives.count(out)
        check(f"danh sách rỗng: {lvl} ≤ trần {cap} (thực tế {n})", n <= cap,
              str(n))
finally:
    marking.DICT_DIR = _real_dir
    marking.reload_lists()
    _os.rmdir(_empty)

print("\n=== Cache phân loại theo khóa (hiệu năng) ===")
import time as _time
_cache = marking._eval_cache
check("cache bắt đầu trống hoặc có dữ liệu hash được",
      isinstance(_cache, dict))
probe_key = ("意思", "phrase", tuple(vietphrase._vp_alts["意思"]), "medium",
             real.no_mark, real.ambiguous, real.synonyms, frozenset())
marking.evaluate("意思", "phrase", list(vietphrase._vp_alts["意思"]),
                 "medium", real)
check("evaluate ghi kết quả vào cache", probe_key in _cache)

print("\n=== Level bất hợp lệ → dùng low (không sập dịch) ===")
out = vietphrase.convert("为是好人。", mark_alternatives=True, mark_level="sai")
check("mark_level sai vẫn dịch được", "là người tốt" in out, out)

print(f"\nTẤT CẢ {PASSED} KIỂM TRA marking ĐỀU PASS ✔")
