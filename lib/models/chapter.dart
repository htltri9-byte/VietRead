/// Model `ChapterSummary` — khớp `GET /stories/{id}/chapters`
/// `{ id, storyId, index, title, updatedAt }` (không kèm nội dung).
class ChapterSummary {
  const ChapterSummary({
    required this.id,
    required this.storyId,
    required this.index,
    required this.title,
    required this.updatedAt,
  });

  final int id;
  final int storyId;

  /// Số thứ tự chương (bắt đầu từ 1).
  final int index;
  final String title;
  final DateTime updatedAt;

  factory ChapterSummary.fromJson(Map<String, dynamic> json) => ChapterSummary(
    id: (json['id'] as num?)?.toInt() ?? 0,
    storyId: (json['storyId'] as num?)?.toInt() ?? 0,
    index: (json['index'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'storyId': storyId,
    'index': index,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// Model `Chapter` — khớp `GET /chapters/{id}` (kèm `content`),
/// dùng cho màn hình đọc ở Bước 5.
class Chapter {
  const Chapter({
    required this.id,
    required this.storyId,
    required this.index,
    required this.title,
    required this.content,
  });

  final int id;
  final int storyId;
  final int index;
  final String title;
  final String content;

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    id: (json['id'] as num?)?.toInt() ?? 0,
    storyId: (json['storyId'] as num?)?.toInt() ?? 0,
    index: (json['index'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'storyId': storyId,
    'index': index,
    'title': title,
    'content': content,
  };
}
