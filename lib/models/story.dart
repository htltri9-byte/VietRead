/// Model `Story` — khớp JSON của `GET /stories`, `GET /stories/{id}` (Phần B).
class Story {
  const Story({
    required this.id,
    required this.title,
    required this.author,
    required this.authorId,
    this.originalAuthor,
    this.uploaderName,
    this.coverUrl,
    this.description,
    this.genres = const [],
    this.status = 'ongoing',
    this.rating = 0,
    this.chapterCount = 0,
    this.isDraft = false,
    this.moderationStatus = 'draft',
    this.rejectReason,
    this.needsRecheck = false,
    this.submittedAt,
    this.scanStatus,
    required this.updatedAt,
  });

  final int id;
  final String title;
  /// Tên hiển thị **tương thích** (bản cũ): nếu backend chưa trả
  /// `originalAuthor` thì đây là tên người đăng; bản Flutter mới dùng
  /// [originalAuthor] + [uploaderName] thay cho trường này.
  final String author;
  final int authorId;

  /// Tác giả nguyên tác — người sáng tác truyện gốc.
  /// `null` khi chưa rõ (ví dụ truyện nhập trước khi có cột này).
  final String? originalAuthor;

  /// Tên tài khoản VietRead đã đăng/nhập truyện lên app.
  final String? uploaderName;
  final String? coverUrl;
  final String? description;

  /// Danh sách **tên** thể loại, ví dụ `['Kiếm Hiệp', 'Tiên Hiệp']`.
  final List<String> genres;

  /// `ongoing` = đang ra, `completed` = hoàn thành.
  final String status;
  final double rating;
  final int chapterCount;
  final bool isDraft;

  // ---------------- Kiểm duyệt trước khi công khai (thêm mới) ----------------

  /// Trạng thái kiểm duyệt: `draft` | `pending` | `approved` | `rejected`.
  /// Truyện chỉ hiện công khai khi `approved`.
  final String moderationStatus;

  /// Lý do Admin từ chối (chỉ có khi `rejected`).
  final String? rejectReason;

  /// Truyện đã duyệt nhưng chủ truyện sửa/thêm chương → Admin nên xem lại.
  final bool needsRecheck;

  /// Lúc chủ truyện gửi duyệt (null khi chưa gửi lần nào).
  final DateTime? submittedAt;

  /// Kết quả quét tự động (`none`/`clean`/`flagged`/`error`) —
  /// giai đoạn này backend chưa chạy quét nên thường là `null` (ẩn khối quét).
  final String? scanStatus;

  final DateTime updatedAt;

  /// Truyện đã được duyệt (= đang hiển thị công khai).
  bool get isApproved => moderationStatus == 'approved';

  /// Nhãn tiếng Việt của trạng thái kiểm duyệt (chip trên thẻ).
  String get moderationLabel => switch (moderationStatus) {
    'approved' => 'Đã duyệt',
    'pending' => 'Chờ duyệt',
    'rejected' => 'Bị từ chối',
    _ => 'Nháp',
  };

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
    // JSON cũ chỉ có `author` — khi đó originalAuthor để null (chưa rõ).
    originalAuthor: _cleanNullable(json['originalAuthor'] as String?),
    uploaderName: _cleanNullable(
          json['uploaderName'] as String?,
        ) ??
        (json['author'] as String? ?? ''),
    coverUrl: json['coverUrl'] as String?,
    description: json['description'] as String?,
    genres: List<String>.from((json['genres'] as List?) ?? const <dynamic>[]),
    status: json['status'] as String? ?? 'ongoing',
    rating: (json['rating'] as num?)?.toDouble() ?? 0,
    chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    isDraft: json['isDraft'] as bool? ?? false,
    // Trạng thái kiểm duyệt — backend cũ chưa có thì suy ra từ isDraft.
    moderationStatus:
        json['moderationStatus'] as String? ??
        ((json['isDraft'] as bool? ?? false) ? 'draft' : 'approved'),
    rejectReason: _cleanNullable(json['rejectReason'] as String?),
    needsRecheck: json['needsRecheck'] as bool? ?? false,
    submittedAt:
        DateTime.tryParse(json['submittedAt'] as String? ?? ''),
    scanStatus: _cleanNullable(json['scanStatus'] as String?),
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
    'originalAuthor': originalAuthor,
    'uploaderName': uploaderName,
    'coverUrl': coverUrl,
    'description': description,
    'genres': genres,
    'status': status,
    'rating': rating,
    'chapterCount': chapterCount,
    'isDraft': isDraft,
    'moderationStatus': moderationStatus,
    'rejectReason': rejectReason,
    'needsRecheck': needsRecheck,
    'submittedAt': submittedAt?.toIso8601String(),
    'scanStatus': scanStatus,
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Chuỗi rỗng/khoảng trắng từ server → `null`.
  static String? _cleanNullable(String? value) {
    final String clean = (value ?? '').trim();
    return clean.isEmpty ? null : clean;
  }
}
