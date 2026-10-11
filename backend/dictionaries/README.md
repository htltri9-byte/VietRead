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
