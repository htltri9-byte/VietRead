/// Marker nhiều nghĩa `{nghĩa1|nghĩa2|nghĩa3}` trong bản dịch thô.
///
/// Khớp **1-1** với `backend/app/alternatives.py`: khi dịch bằng từ điển, cụm
/// có nhiều nghĩa được lưu kèm marker để người đăng truyện *chọn nghĩa* trên
/// màn Sửa chương. Ký tự phân cách là `|`; dạng cũ `{nghĩa1:nghĩa2}` (từng
/// xuất hiện trong dữ liệu) vẫn đọc được.
///
/// **Marker KHÔNG BAO GIỜ chứa chữ Trung** — chỉ nghĩa tiếng Việt:
///
/// - Định dạng chuẩn: `{nghĩa1|nghĩa2}`. Mọi phần tử chứa ký tự CJK (chữ Hán +
///   dấu câu CJK) bị LOẠI khỏi danh sách nghĩa khi parse/build — không bao
///   giờ hiện cho người đăng hay người đọc.
/// - Dữ liệu cũ `{中文|nghĩa1|nghĩa2}` vẫn đọc được: phần chữ Hán tách ra làm
///   **khóa cũ** ([Marker.key], chỉ dùng nội bộ để gửi kèm khi "luôn dùng" /
///   "không hỏi lại" — không hiển thị); phần Việt giữ làm danh sách nghĩa.
/// - Sau khi loại chữ Hán còn < 2 nghĩa → không còn là marker (parse bỏ qua,
///   [resolveMarkers] lấy nghĩa đầu còn lại và bỏ `{}`).
///
/// Người đọc không bao giờ thấy dấu `{}` — backend resolve trước khi trả;
/// chỉ màn Sửa chương (owner, `raw=1`) mới thấy marker để chọn.
library;

/// Một chỗ nhiều nghĩa trong văn bản — `[start, end)` là vùng `{...}`.
class Marker {
  const Marker({
    required this.start,
    required this.end,
    required this.meanings,
    this.key,
  });

  /// Vị trí bắt đầu trong văn bản gốc.
  final int start;

  /// Vị trí kết thúc (exclusive).
  final int end;

  /// Danh sách NGHĨA VIỆT — phần tử đầu tiên là nghĩa mặc định (≥ 2).
  final List<String> meanings;

  /// Khóa cũ (segment chữ Hán) — chỉ DỮ LIỆU CŨ mới có, không hiển thị.
  /// Marker sinh ra từ bản dịch mới luôn `null`.
  final String? key;

  /// Chuỗi `{...}` gốc tại vị trí này (dữ liệu cũ có thể còn khóa).
  String rawOf(String source) => source.substring(start, end);

  String get first => meanings.first;
}

final RegExp _markerPattern = RegExp(r'\{([^{}]+)\}');

// Ký tự CJK — chữ Hán BMP + mở rộng + dấu câu/ký tự CJK.
// GIỐNG HỆT backend/app/alternatives.py để hai phía parse khớp nhau.
final RegExp _cjkPattern = RegExp(
  '[㐀-䶿一-鿿豈-﫿'
  '　-〿！-｠︰-﹏]',
);

/// True nếu chuỗi chứa ký tự CJK (chữ Hán hoặc dấu câu CJK).
bool hasCjk(String value) => _cjkPattern.hasMatch(value);

/// Tên cũ — cùng ngữ nghĩa với [hasCjk] (giữ chỗ tham chiếu ngoài).
bool hasHan(String value) => hasCjk(value);

/// Tách nội dung marker thành (khóa cũ, danh sách nghĩa Việt) — hỗ trợ cả
/// `a|b` (chuẩn), khóa `中文|a|b` (dữ liệu cũ) và dạng cũ `a:b`. Loại mọi
/// phần tử CJK, nghĩa trống và nghĩa trùng.
(String?, List<String>) splitParts(String inner) {
  final List<String> raw = inner.contains('|')
      ? inner.split('|')
      : inner.contains(':')
      ? inner.split(':')
      : <String>[inner];
  final List<String> parts = <String>[];
  final List<String> cjkParts = <String>[];
  for (final String part in raw) {
    final String value = part.trim();
    if (value.isEmpty) continue;
    if (hasCjk(value)) {
      if (!cjkParts.contains(value)) cjkParts.add(value);
    } else if (!parts.contains(value)) {
      parts.add(value);
    }
  }
  final String? key = cjkParts.isEmpty ? null : cjkParts.first;
  return (key, parts);
}

/// Danh sách NGHĨA VIỆT của marker (đã bỏ mọi phần tử chữ Hán/CJK).
List<String> splitMeanings(String inner) => splitParts(inner).$2;

/// Khóa cũ của marker — chỉ dữ liệu cũ có; không hiển thị cho người dùng.
String? splitKey(String inner) => splitParts(inner).$1;

/// Liệt kê mọi marker hợp lệ trong [text] — chỉ marker có **≥ 2 nghĩa Việt**
/// (sau khi loại chữ Hán còn < 2 thì không còn là chỗ chọn nghĩa).
List<Marker> parseMarkers(String text) {
  if (text.isEmpty || !text.contains('{')) return const <Marker>[];
  final List<Marker> markers = <Marker>[];
  for (final Match m in _markerPattern.allMatches(text)) {
    final (String? key, List<String> meanings) = splitParts(m.group(1)!);
    if (meanings.length < 2) continue;
    markers.add(
      Marker(
        start: m.start,
        end: m.end,
        meanings: List<String>.unmodifiable(meanings),
        key: key,
      ),
    );
  }
  return markers;
}

/// Số chỗ chưa chọn nghĩa (= số marker hợp lệ còn trong văn bản).
int countMarkers(String text) => parseMarkers(text).length;

/// Marker chứa vị trí [offset] trong [text] (`null` nếu không trúng chỗ nào).
Marker? markerAt(String text, int offset) {
  for (final Marker marker in parseMarkers(text)) {
    if (offset >= marker.start && offset <= marker.end) return marker;
  }
  return null;
}

/// Loại phần tử rỗng / trùng / chứa ký tự CJK — mọi nghĩa phải là tiếng Việt.
List<String> cleanMeanings(Iterable<String> values) {
  final List<String> out = <String>[];
  for (final String value in values) {
    final String item = value.trim();
    if (item.isNotEmpty && !hasCjk(item) && !out.contains(item)) out.add(item);
  }
  return out;
}

/// Bỏ toàn bộ marker (kể cả khóa cũ), thay mỗi marker bằng **nghĩa đầu**
/// Việt còn lại. Văn bản không có marker được trả về nguyên vẹn.
String resolveMarkers(String text) {
  if (text.isEmpty || !text.contains('{')) return text;
  return text.replaceAllMapped(_markerPattern, (Match m) {
    final List<String> meanings = splitParts(m.group(1)!).$2;
    if (meanings.isEmpty) return '';
    return meanings.first;
  });
}

/// Ghép danh sách nghĩa thành marker `{a|b}` — trả `''` nếu không hợp lệ
/// (cần ≥ 2 nghĩa Việt khác nhau sau khi loại trống/trùng/CJK). KHÔNG kèm
/// khóa Trung.
String buildMarker(List<String> meanings) {
  final List<String> clean = cleanMeanings(meanings);
  if (clean.length < 2) return '';
  return '{${clean.take(6).join('|')}}';
}
