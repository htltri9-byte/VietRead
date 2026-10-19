# Từ điển dịch offline (chế độ `TRANSLATE_MODE=dict`)

App dịch Trung → Việt **không cần mạng, không cần API key** bằng thuật toán
longest-match (so khớp cụm dài nhất trước), thứ tự tra:

**Names (`names.txt`) → Luật Nhân (`luatnhan.txt`) → VietPhrase (`vietphrase.txt`) → Surnames (`surnames.txt`) → Hán-Việt từng chữ (`hanviet.txt`)**

| File | Vai trò | Định dạng |
|---|---|---|
| `hanviet.txt` | Âm Hán-Việt từng chữ — sinh từ Unihan `kVietnamese` (unicode.org) + lan âm cho chữ phổ biến qua `kTraditionalVariant`/`kSimplifiedVariant` | `字=âm1/âm2` |
| `vietphrase.txt` | Cụm từ → nghĩa tiếng Việt — **kèm sẵn bộ 679.308 cụm** (bộ VietPhrase đầy đủ); thay file mới rồi xoá `_cache.pkl` là tự nạp | `中文=nghĩa1/nghĩa2` (UTF-8 hoặc UTF-16, tự nhận theo BOM) |
| `names.txt` | Tên riêng nhiều chữ (nhân vật / địa danh / tông môn) — **ưu tiên cao nhất**, viết hoa từng từ | `中文=Việt Nam` |
| `surnames.txt` | Họ Trung Quốc — ký tự **đơn lẻ**, kèm sẵn 400 họ (Bách Tánh); chỉ tra khi **không** trúng cụm nào ở các tầng trên nên không ghi đè nghĩa phổ thông | `字=âm` |
| `luatnhan.txt` | Mẫu Luật Nhân — cụm có ô thay thế `{0}` (mẫu Việt cũng có `{0}`); đoạn trong ô được dịch bằng chính bộ máy từ điển — **kèm sẵn 7.024 mẫu** | `中文{0}中文=mẫu Việt {0}` |
| `_cache.pkl` | Cache pickle tự sinh cho nhanh khởi động — **không sửa tay** | — |

Quy tắc chung:

- Chỉ lấy **nghĩa/âm đầu tiên** (cắt theo `/` hoặc `;`); dòng bắt đầu bằng `#` là comment.
- Dòng "nhiều từ" kiểu `太一,正一=thái nhất,chính nhất` (2 vế song song, cụm ≤ 4 chữ)
  được tách thành từng cặp; cụm có phẩy bên trong thì giữ nguyên một khoá.
- Họ (`surnames.txt`) được tra **sau VietPhrase, trước Hán-Việt** — cụm từ dài luôn thắng họ.
- Tiêu đề chương nhập từ nguồn bị bỏ tiền tố `第N章` (app tự hiển thị "Chương N: ").
- Mẫu Luật Nhân được thử **sau Names, trước VietPhrase** (prefix dài nhất trước);
  đoạn chèn vào `{0}` dài tối đa 12 ký tự, không được chứa dấu kết câu, và mẫu
  lồng nhau tối đa 3 lớp.
- Ký tự không có trong từ điển nào thì **giữ nguyên**.
- Thêm tên riêng nhanh: gọi `POST /dictionary/names` body `{"zh": "李明", "vi": "Lý Minh"}`
  — ghi vào `names.txt` và nạp lại ngay, **không cần restart**. Muốn thêm cả
  `vietphrase.txt`/`hanviet.txt` bằng tay thì sửa file rồi restart (hoặc xoá `_cache.pkl`).
- Dấu câu full-width (，。！？：；“”「」（）……) được đổi sang dạng Việt/ASCII;
  chữ đầu câu/đoạn và tên riêng được viết hoa.

---

## Danh sách marker nhiều nghĩa (`marking.py`)

Ba file người dùng + hai file seed **đóng gói kèm repo** quyết định một mục
đa nghĩa có thành marker `{nghĩa1|nghĩa2}` hay tự lấy nghĩa đầu. **Toàn bộ
phân loại là luật offline — không AI, không gọi mạng** (khóa phân loại do
người viết chắt lọc, không có công cụ sinh file gợi ý tự động).

| File | Vai trò | Người dùng hay seed thắng? |
|---|---|---|
| `no_mark.txt` | Đen tuyệt đối: trợ từ, lượng từ, liên từ — không bao giờ marker | Người dùng (không có seed) |
| `ambiguous.txt` | Trắng: khóa đa nghĩa thật sự — luôn marker ở mức Ít/Vừa | **Người dùng thắng** |
| `ambiguous.seed.txt` | Trắng đóng gói (~240 khóa viết tay: 打 行 开 过 意思 东西 方便 厉害…) | Nạp tiếp khi `ambiguous.txt` không có khóa |
| `synonyms.txt` | Đen: khóa các nghĩa chỉ là đồng nghĩa — không marker | **Người dùng thắng** |
| `synonyms.seed.txt` | Đen đóng gói (~120 khóa viết tay, lấy cả từ chương Qidian thật) | Nạp tiếp khi `synonyms.txt` không có khóa |

Quy tắc gộp trong `reload_lists()` (người dùng thắng khi mâu thuẫn):

```
ambiguous = ambiguous.txt  ∪  (ambiguous.seed.txt − synonyms.txt − no_mark.txt)
synonyms  = synonyms.txt   ∪  (synonyms.seed.txt  − ambiguous.txt − no_mark.txt)
```

- **Format chung cho cả 5 file**: mỗi dòng MỘT khóa chữ Trung, UTF-8 (hoặc
  UTF-16 theo BOM), dòng bắt đầu bằng `#` là chú thích, dòng trống bị bỏ qua.
- **Sửa file không cần restart**: `marking.get_lists()` tự nạp khi mtime đổi,
  hoặc bấm `POST /dictionary/mark-lists/reload` (cache phân loại theo khóa
  cũng xoá khi nạp lại).
- File thiếu hoặc rỗng → coi như danh sách rỗng, **không lỗi** (mức Ít khi
  cả seed lẫn file người dùng trống sẽ dùng bộ lọc nghiêm ngặt thay vì whitelist).
- Khóa có luật cũ `{a:b}` viết tay trong `vietphrase.txt` (一顿 不为 为 定为 当等)
  luôn được coi như nằm trong `ambiguous.txt`.
- Tạo lại seed (kiểm chứng against từ điển cục bộ, không mạng):
  `PYTHONUTF8=1 .venv/Scripts/python.exe _gen_seeds.py` — chỉ chạy khi muốn
  regenerate; file đã commit, không cần chạy lại khi khởi động.
