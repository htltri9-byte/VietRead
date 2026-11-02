import 'story.dart';

/// Truyện đã tải offline — khớp bảng `downloaded_stories` (A4):
/// `downloaded_stories(id, title, author, coverPath, description)`.
class DownloadedStory {
  const DownloadedStory({
    required this.id,
    required this.title,
    required this.author,
    this.originalAuthor,
    this.uploaderName,
    this.coverPath,
    this.description,
    this.chapterCount = 0,
  });

  final int id;
  final String title;

  /// Cột cũ `author` (tên hiển thị bản trước) — giữ để đọc db cũ.
  final String author;

  /// Tác giả nguyên tác (cột mới, db cũ → `null` = chưa rõ).
  final String? originalAuthor;

  /// Người đăng (tên tài khoản VietRead — cột mới, db cũ → `null`).
  final String? uploaderName;

  /// Đường dẫn file ảnh bìa đã tải về máy (`null` = không tải được ảnh).
  final String? coverPath;
  final String? description;

  /// Số chương đã nằm trong SQLite — lấy từ `downloaded_chapters` (không lưu trong bảng).
  final int chapterCount;

  factory DownloadedStory.fromJson(Map<String, dynamic> json) =>
      DownloadedStory(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        originalAuthor: json['originalAuthor'] as String?,
        uploaderName: json['uploaderName'] as String?,
        coverPath: json['coverPath'] as String?,
        description: json['description'] as String?,
        chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'author': author,
    'originalAuthor': originalAuthor,
    'uploaderName': uploaderName,
    'coverPath': coverPath,
    'description': description,
    'chapterCount': chapterCount,
  };

  /// Chuyển sang [Story] để mở màn đọc offline (thông tin ít hơn bản server).
  Story toStory() => Story(
    id: id,
    title: title,
    author: author,
    authorId: 0,
    originalAuthor: originalAuthor,
    uploaderName: uploaderName,
    description: description,
    chapterCount: chapterCount,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
