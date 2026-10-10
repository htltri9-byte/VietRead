# Từ điển dịch offline (chế độ `TRANSLATE_MODE=dict`)

App dịch Trung → Việt **không cần mạng, không cần API key** bằng thuật toán
longest-match (so khớp cụm dài nhất trước), thứ tự tra:

**Names (`names.txt`) → VietPhrase (`vietphrase.txt`) → Hán-Việt từng chữ (`hanviet.txt`)**

| File | Vai trò | Định dạng |
|---|---|---|
| `hanviet.txt` | Âm Hán-Việt từng chữ — sinh từ Unihan `kVietnamese` (unicode.org) + lan âm cho chữ phổ biến qua `kTraditionalVariant`/`kSimplifiedVariant` | `字=âm1/âm2` |
| `vietphrase.txt` | Cụm từ → nghĩa tiếng Việt — **bạn tự cung cấp**, chưa có sẵn (thiếu file này thì vẫn chạy, chỉ ra âm từng chữ) | `中文=nghĩa1/nghĩa2` |
| `names.txt` | Tên nhân vật / địa danh — **ưu tiên cao nhất**, viết hoa từng từ | `中文=Việt Nam` |
| `_cache.pkl` | Cache pickle tự sinh cho nhanh khởi động — **không sửa tay** | — |

Quy tắc chung:

- Chỉ lấy **nghĩa/âm đầu tiên** (cắt theo `/` hoặc `;`); dòng bắt đầu bằng `#` là comment.
- Ký tự không có trong từ điển nào thì **giữ nguyên**.
- Thêm tên riêng nhanh: gọi `POST /dictionary/names` body `{"zh": "李明", "vi": "Lý Minh"}`
  — ghi vào `names.txt` và nạp lại ngay, **không cần restart**. Muốn thêm cả
  `vietphrase.txt`/`hanviet.txt` bằng tay thì sửa file rồi restart (hoặc xoá `_cache.pkl`).
- Dấu câu full-width (，。！？：；“”「」（）……) được đổi sang dạng Việt/ASCII;
  chữ đầu câu/đoạn và tên riêng được viết hoa.
