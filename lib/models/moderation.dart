/// Model cho chức năng **kiểm duyệt truyện** (Admin) — khớp JSON của
/// `GET /admin/stories`, `GET /admin/stories/{id}`, `GET /admin/chapters/{id}`,
/// `GET /admin/stats` (xem `backend/app/routers/admin.py`).
library;

import 'chapter.dart';

/// Nhãn tiếng Việt cho trạng thái kiểm duyệt (dùng chung với `Story.moderationLabel`).
String moderationStatusLabel(String status) => switch (status) {
  'approved' => 'Đã duyệt',
  'pending' => 'Chờ duyệt',
  'rejected' => 'Bị từ chối',
  _ => 'Nháp',
};

/// Tab lọc của màn Kiểm duyệt — `status` khớp tham số `?status=` của backend.
enum ModerationTab {
  pending('pending', 'Chờ duyệt'),
  approved('approved', 'Đã duyệt'),
  rejected('rejected', 'Từ chối'),
  recheck('recheck', 'Cần xem lại');

  const ModerationTab(this.status, this.label);

  final String status;
  final String label;
}

/// Một thẻ trong danh sách kiểm duyệt — `AdminStoryOut` của backend.
class AdminStory {
  const AdminStory({
    required this.id,
    required this.title,
    required this.author,
    required this.chapterCount,
    required this.moderationStatus,
    this.coverUrl,
    this.rejectReason,
    this.needsRecheck = false,
    this.submittedAt,
    this.reviewedAt,
    this.scanStatus,
  });

  final int id;
  final String title;
  final String? coverUrl;
  final String author; // tên người đăng
  final int chapterCount;
  final String moderationStatus;
  final String? rejectReason;
  final bool needsRecheck;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? scanStatus;

  /// Nhãn trạng thái (Nháp / Chờ duyệt / Đã duyệt / Bị từ chối).
  String get statusLabel => moderationStatusLabel(moderationStatus);

  /// Số chương hiển thị, ví dụ `3 chương`.
  String get chapterLabel => '$chapterCount chương';

  factory AdminStory.fromJson(Map<String, dynamic> json) => AdminStory(
    id: (json['id'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    coverUrl: json['coverUrl'] as String?,
    author: json['author'] as String? ?? '',
    chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    moderationStatus: json['moderationStatus'] as String? ?? 'draft',
    rejectReason: _clean(json['rejectReason'] as String?),
    needsRecheck: json['needsRecheck'] as bool? ?? false,
    submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? ''),
    reviewedAt: DateTime.tryParse(json['reviewedAt'] as String? ?? ''),
    scanStatus: _clean(json['scanStatus'] as String?),
  );

  static String? _clean(String? value) {
    final String t = (value ?? '').trim();
    return t.isEmpty ? null : t;
  }
}

/// Chi tiết truyện để Admin xem trước (kể cả khi chưa công khai) —
/// `AdminStoryDetailOut`: `{ story, description, genres, originalAuthor,
/// uploaderName, chapters }`.
class AdminStoryDetail {
  const AdminStoryDetail({
    required this.story,
    this.description,
    this.genres = const <String>[],
    this.originalAuthor,
    this.uploaderName = '',
    this.chapters = const <ChapterSummary>[],
  });

  final AdminStory story;
  final String? description;
  final List<String> genres;
  final String? originalAuthor;
  final String uploaderName;
  final List<ChapterSummary> chapters;

  /// Có kết quả quét tự động để hiển thị không (ẩn khối quét khi rỗng).
  bool get hasScanResult =>
      (story.scanStatus ?? '').trim().isNotEmpty &&
      story.scanStatus!.trim() != 'none';

  factory AdminStoryDetail.fromJson(Map<String, dynamic> json) =>
      AdminStoryDetail(
        story: AdminStory.fromJson(
          json['story'] as Map<String, dynamic>? ?? <String, dynamic>{},
        ),
        description: json['description'] as String?,
        genres: List<String>.from((json['genres'] as List?) ?? const <dynamic>[]),
        originalAuthor: json['originalAuthor'] as String?,
        uploaderName: json['uploaderName'] as String? ?? '',
        chapters: (json['chapters'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ChapterSummary.fromJson)
                .toList(growable: false) ??
            const <ChapterSummary>[],
      );
}

/// Nội dung chương cho Admin đọc — `AdminChapterOut`:
/// bản **đã resolve marker** (không dấu `{}`) + `OriginalContent` nếu có.
class AdminChapter {
  const AdminChapter({
    required this.id,
    required this.storyId,
    required this.index,
    required this.title,
    required this.content,
    this.originalContent,
  });

  final int id;
  final int storyId;
  final int index;
  final String title;
  final String content;
  final String? originalContent;

  factory AdminChapter.fromJson(Map<String, dynamic> json) => AdminChapter(
    id: (json['id'] as num?)?.toInt() ?? 0,
    storyId: (json['storyId'] as num?)?.toInt() ?? 0,
    index: (json['index'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    originalContent: json['originalContent'] as String?,
  );
}

/// Thống kê cho badge "Chờ duyệt (N)" — `GET /admin/stats`.
class AdminStats {
  const AdminStats({
    this.draft = 0,
    this.pending = 0,
    this.approved = 0,
    this.rejected = 0,
    this.needsRecheck = 0,
  });

  final int draft;
  final int pending;
  final int approved;
  final int rejected;
  final int needsRecheck;

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
    draft: (json['draft'] as num?)?.toInt() ?? 0,
    pending: (json['pending'] as num?)?.toInt() ?? 0,
    approved: (json['approved'] as num?)?.toInt() ?? 0,
    rejected: (json['rejected'] as num?)?.toInt() ?? 0,
    needsRecheck: (json['needsRecheck'] as num?)?.toInt() ?? 0,
  );
}
