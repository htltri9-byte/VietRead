/// Model phản hồi gợi ý nhiều nghĩa theo truyện — khớp backend
/// (`POST/GET/DELETE /stories/{id}/word-choices`, `/ignored-words`).
library;

/// "Luôn dùng nghĩa này cho truyện này" — bảng `StoryWordChoices`:
/// khóa Trung → nghĩa đã chọn; dịch/dịch lại chương CỦA TRUYỆN NÀY tự dùng
/// nghĩa đó, không tạo marker nữa.
class WordChoice {
  const WordChoice({
    required this.id,
    required this.sourceKey,
    required this.chosenText,
    required this.createdAt,
    this.affectedIds = const <int>[],
  });

  final int id;

  /// Khóa từ điển đã lưu — CHỈ dùng nội bộ (bọc Kakfa); không hiển thị vì
  /// chứa chữ Trung. Client gửi danh sách nghĩa, backend tự tra khóa.
  final String sourceKey;

  final String chosenText;
  final DateTime createdAt;

  /// Mọi id đã ghi ở lượt POST (nhiều khóa trùng danh sách nghĩa → lưu tất;
  /// dùng để Hoàn tác). GET không có trường này → rỗng.
  final List<int> affectedIds;

  factory WordChoice.fromJson(Map<String, dynamic> json) => WordChoice(
    id: (json['id'] as num?)?.toInt() ?? 0,
    sourceKey: json['sourceKey'] as String? ?? '',
    chosenText: json['chosenText'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    affectedIds:
        (json['affectedIds'] as List?)
            ?.map((dynamic e) => (e as num).toInt())
            .toList() ??
        const <int>[],
  );
}

/// "Không hỏi lại từ này" — bảng `StoryIgnoredWords` (riêng truyện, không sửa
/// file chung `no_mark.txt`): khóa này không bao giờ tạo marker trong truyện.
class IgnoredWord {
  const IgnoredWord({
    required this.id,
    required this.sourceKey,
    required this.createdAt,
    this.affectedIds = const <int>[],
  });

  final int id;

  /// Khóa đã bỏ hỏi — chỉ nội bộ (chữ Trung), không hiển thị.
  final String sourceKey;

  final DateTime createdAt;

  /// Mọi id đã ghi ở lượt POST (xem [WordChoice.affectedIds]).
  final List<int> affectedIds;

  factory IgnoredWord.fromJson(Map<String, dynamic> json) => IgnoredWord(
    id: (json['id'] as num?)?.toInt() ?? 0,
    sourceKey: json['sourceKey'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    affectedIds:
        (json['affectedIds'] as List?)
            ?.map((dynamic e) => (e as num).toInt())
            .toList() ??
        const <int>[],
  );
}
