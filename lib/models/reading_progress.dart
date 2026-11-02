import 'story.dart';

/// Tiến độ đọc của một truyện — lưu bằng `shared_preferences`
/// (A1: *"tự lưu tiến độ đọc"* — A3.5).
class ReadingProgress {
  const ReadingProgress({
    required this.story,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.progress,
    required this.updatedAt,
  });

  factory ReadingProgress.fromJson(Map<String, dynamic> json) =>
      ReadingProgress(
        story: Story.fromJson(
          (json['story'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
        ),
        chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 1,
        chapterTitle: json['chapterTitle'] as String? ?? '',
        progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final Story story;

  /// Chương đang đọc (bắt đầu từ 1).
  final int chapterIndex;
  final String chapterTitle;

  /// Vị trí đọc trong chương, 0.0–1.0.
  final double progress;

  /// Thời điểm lưu gần nhất (để sắp xếp lịch sử đọc ở Bước 7).
  final DateTime updatedAt;

  /// Ví dụ `Chương 12 — Kiếm Ngưng Tường`.
  String get chapterLabel => 'Chương $chapterIndex — $chapterTitle';

  /// Phần trăm hiển thị, ví dụ `62%`.
  String get percentLabel => '${(progress.clamp(0.0, 1.0) * 100).round()}%';

  ReadingProgress copyWith({
    int? chapterIndex,
    String? chapterTitle,
    double? progress,
    DateTime? updatedAt,
  }) => ReadingProgress(
    story: story,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    progress: progress ?? this.progress,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'story': story.toJson(),
    'chapterIndex': chapterIndex,
    'chapterTitle': chapterTitle,
    'progress': progress,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
