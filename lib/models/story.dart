/// Model `Story` — khớp JSON của `GET /stories`, `GET /stories/{id}` (Phần B).
class Story {
  const Story({
    required this.id,
    required this.title,
    required this.author,
    required this.authorId,
    this.coverUrl,
    this.description,
    this.genres = const [],
    this.status = 'ongoing',
    this.rating = 0,
    this.chapterCount = 0,
    this.isDraft = false,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String author;
  final int authorId;
  final String? coverUrl;
  final String? description;

  /// Danh sách **tên** thể loại, ví dụ `['Kiếm Hiệp', 'Tiên Hiệp']`.
  final List<String> genres;

  /// `ongoing` = đang ra, `completed` = hoàn thành.
  final String status;
  final double rating;
  final int chapterCount;
  final bool isDraft;
  final DateTime updatedAt;

  /// Đang ra hay hoàn thành (để vẽ chip trạng thái).
  bool get isCompleted => status == 'completed';

  /// Nhãn tiếng Việt của trạng thái.
  String get statusLabel => isCompleted ? 'Hoàn thành' : 'Đang ra';

  /// Điểm hiển thị, ví dụ `4.8`.
  String get ratingLabel => rating.toStringAsFixed(1);

  /// Số chương hiển thị, ví dụ `3 chương`.
  String get chapterLabel => '$chapterCount chương';

  /// Thời gian cập nhật tương đối (tiếng Việt) cho mục "Mới cập nhật".
  String get updatedLabel {
    final DateTime now = DateTime.now();
    final Duration diff = now.difference(updatedAt);
    if (diff.isNegative || diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    final String dd = updatedAt.day.toString().padLeft(2, '0');
    final String mm = updatedAt.month.toString().padLeft(2, '0');
    return '$dd/$mm/${updatedAt.year}';
  }

  factory Story.fromJson(Map<String, dynamic> json) => Story(
    id: (json['id'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    author: json['author'] as String? ?? '',
    authorId: (json['authorId'] as num?)?.toInt() ?? 0,
    coverUrl: json['coverUrl'] as String?,
    description: json['description'] as String?,
    genres: List<String>.from((json['genres'] as List?) ?? const <dynamic>[]),
    status: json['status'] as String? ?? 'ongoing',
    rating: (json['rating'] as num?)?.toDouble() ?? 0,
    chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    isDraft: json['isDraft'] as bool? ?? false,
    // Chuỗi ISO từ backend (ví dụ 2026-10-06T10:47:48.657115)
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'author': author,
    'authorId': authorId,
    'coverUrl': coverUrl,
    'description': description,
    'genres': genres,
    'status': status,
    'rating': rating,
    'chapterCount': chapterCount,
    'isDraft': isDraft,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
