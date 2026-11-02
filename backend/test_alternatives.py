"""Chạy test cho module marker nhiều nghĩa `app/alternatives.py` (không cần server).

Cách dùng (trong backend/):
    .venv/Scripts/python.exe test_alternatives.py
"""

from __future__ import annotations

from app import alternatives, vietphrase
from app.vietphrase import convert

PASSED = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global PASSED
    if not ok:
        raise AssertionError(f"FAILED — {label} {detail}")
    PASSED += 1
    print(f"  OK  {label}")


def main() -> None:
    print("=== PARSE / SPLIT ===")
    markers = alternatives.parse("Đầu {vì|là|làm} giữa {a:b} cuối")
    check("parse thấy 2 marker", len(markers) == 2, str(markers))
    check("vị trí marker đúng", markers[0].text == "{vì|là|làm}"
          and markers[0].meanings == ("vì", "là", "làm"), str(markers[0]))
    check("dạng cũ {a:b} cũng đọc được", markers[1].meanings == ("a", "b"), str(markers[1]))
    check("marker 1 nghĩa không còn là chỗ chọn nghĩa",
          alternatives.parse("thẻ {card siêu nhân}") == [])
    check("…nhưng resolve vẫn lấy nghĩa, bỏ {}",
          alternatives.resolve("thẻ {card siêu nhân}") == "thẻ card siêu nhân")
    check("văn bản không marker → []", alternatives.parse("Chương 1") == [])
    check("count = số marker", alternatives.count("x {a|b} y {c:d} z") == 2)

    print("=== CHỮ HÁN / DỮ LIỆU CŨ (marker không bao giờ chứa chữ Trung) ===")
    legacy = "còn {为|vì|là|vi} rút đi kiều mị"
    lm = alternatives.parse(legacy)[0]
    check("dữ liệu cũ {为|…} parse được: tách khóa cũ, 3 nghĩa Việt",
          lm.key == "为" and lm.meanings == ("vì", "là", "vi"), str(lm))
    check("resolve dữ liệu cũ → không chữ Hán, không {}",
          alternatives.resolve(legacy) == "còn vì rút đi kiều mị",
          alternatives.resolve(legacy))
    check("parse KHÔNG giữ lại phần tử chữ Hán trong meanings",
          not any(alternatives.has_cjk(m) for m in lm.meanings))
    check("build loại phần tử chữ Hán",
          alternatives.build(["为", "vì", "là"]) == "{vì|là}",
          alternatives.build(["为", "vì", "là"]))
    check("build toàn chữ Hán → không marker",
          alternatives.build(["为", "之"]) == "")
    check("normalize dữ liệu cũ → dạng sạch",
          alternatives.normalize(legacy) == "còn {vì|là|vi} rút đi kiều mị",
          alternatives.normalize(legacy))
    check("normalize: còn 1 nghĩa sau khi loại → bỏ {}",
          alternatives.normalize("a {为|vì} b") == "a vì b")
    check("normalize idempotent với marker sạch",
          alternatives.normalize("a {vì|là} b") == "a {vì|là} b")
    check("clean_count đếm chỗ cần dọn",
          alternatives.clean_count(f"{legacy} và {{x|y}}") == 1)
    check("dấu câu CJK cũng bị loại khỏi nghĩa",
          alternatives.build(["vì、là", "vi", "khác"]) == "{vi|khác}",
          alternatives.build(["vì、là", "vi", "khác"]))
    check("loại phần tử dấu câu CJK còn 1 nghĩa → không marker",
          alternatives.build(["vì、là", "vi"]) == "")

    print("=== TRA NGƯỢC: danh sách nghĩa → khóa từ điển ===")
    keys = vietphrase.keys_for_meanings(["vì", "là", "vi"])
    check("[vì|lành…] tra ngược được khóa 为 (dữ liệu cũ)", "为" in keys, str(keys))
    marked1 = convert("少年站在山巅。", mark_alternatives=True, mark_level="medium")
    m1 = alternatives.parse(marked1)[0]
    rev = vietphrase.keys_for_meanings(list(m1.meanings))
    check("marker sinh ra tra ngược đúng khóa gốc (少年)", rev == ["少年"],
          f"marker={m1.text} rev={rev}")
    check("danh sách rỗng → không tra được", vietphrase.keys_for_meanings([]) == [])

    print("=== RESOLVE ===")
    check("resolve first (mặc định)",
          alternatives.resolve("còn {vì:là} rút đi kiều mị") == "còn vì rút đi kiều mị")
    check("resolve first dạng mới",
          alternatives.resolve("Định {định vì|định là} chỗ") == "Định định vì chỗ")
    check("resolve last", alternatives.resolve("{vì|là}", mode="last") == "là")
    check("resolve theo chỉ số", alternatives.resolve("{vì|là|mà}", mode=1) == "là")
    check("resolve chỉ số ngoài danh sách → nghĩa đầu",
          alternatives.resolve("{vì|là}", mode=9) == "vì")
    check("resolve giữ nguyên văn bản không marker",
          alternatives.resolve("Chương 1: Tích đất thành núi")
          == "Chương 1: Tích đất thành núi")
    check("resolve rỗng", alternatives.resolve("") == "")
    check("không còn dấu {} sau resolve",
          "{" not in alternatives.resolve("a {x|y} b {c:d} c {một}"))

    print("=== BUILD ===")
    check("1 nghĩa → không tạo marker", alternatives.build(["chỉ một"]) == "")
    check("2 nghĩa → marker chuẩn", alternatives.build(["a", "b"]) == "{a|b}")
    check("bỏ trùng + bỏ trống", alternatives.build(["a", "a", " ", "b"]) == "{a|b}")
    check("tối đa 6 nghĩa",
          alternatives.build([f"n{i}" for i in range(9)])
          == "{" + "|".join(f"n{i}" for i in range(6)) + "}")
    check("resolve(build(x)) = nghĩa đầu",
          alternatives.resolve(alternatives.build(["nghĩa 1", "nghĩa 2"])) == "nghĩa 1")

    print("=== EXPAND (gỡ marker cũ trong từ điển) ===")
    check("định {vì:là} → 2 nghĩa", alternatives.expand("định {vì:là}") == ["định vì", "định là"])
    check("marker 1 nghĩa bị gỡ", alternatives.expand("{card siêu nhân}") == ["card siêu nhân"])
    check("văn bản thường giữ nguyên", alternatives.expand("thế giới") == ["thế giới"])

    print("=== CONVERT (từ điển thật) ===")
    plain = convert("少年站在山巅。")
    # mức Vừa: bộ lọc 1-5 — 少年 không cần whitelisted vẫn ra marker để test
    marked = convert("少年站在山巅。", mark_alternatives=True, mark_level="medium")
    check("convert() mặc định không marker", "{" not in plain, plain)
    check("convert(mark_alternatives=True) có marker", "{" in marked, marked)
    check("resolve(marked) == plain", alternatives.resolve(marked) == plain,
          f"{marked!r} vs {plain!r}")
    check("mọi marker ≥2 nghĩa và ≤6 nghĩa",
          all(2 <= len(m.meanings) <= 6 for m in alternatives.parse(marked)),
          str(alternatives.parse(marked)))
    check("MỌI marker sinh ra không chứa ký tự CJK (text lẫn nghĩa)",
          all(not alternatives.has_cjk(m.text)
              and not any(alternatives.has_cjk(x) for x in m.meanings)
              for m in alternatives.parse(marked)),
          str(alternatives.parse(marked)))

    samples = [
        "他为你而来。",
        "李明定为内门弟子，当作为此负责。",
        "那一天太阳落下再也没有升起。",
        "他一顿吃了三碗饭，等了半天。",
    ]
    for text in samples:
        p = convert(text)
        m = convert(text, mark_alternatives=True, mark_level="medium")
        check(f"resolve(marked)==plain — {text[:12]}", alternatives.resolve(m) == p,
              f"{m!r} vs {p!r}")
        check(f"plain không dấu {{}} — {text[:12]}", "{" not in p, p)
        check(f"marker không chứa chữ Hán — {text[:12]}",
              all(not alternatives.has_cjk(mk.text) for mk in alternatives.parse(m)),
              m)

    # Dạng cũ còn trong DB (đọc được cả 2 dạng)
    check("truyện cũ {a:b} vẫn resolve",
          alternatives.resolve("còn {vì:là} rút đi kiều mị").startswith("còn vì"))

    print(f"\nTẤT CẢ {PASSED} KIỂM TRA alternatives ĐỀU PASS ✔")


if __name__ == "__main__":
    main()
