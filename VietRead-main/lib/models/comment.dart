/// Model `Comment` — khớp `GET/POST /stories/{id}/comments` (Phần B):
/// `{ id, storyId, chapterId?, userId, userName, avatarUrl?, content, createdAt }`.
class Comment {
  const Comment({
    required this.id,
    required this.storyId,
    this.chapterId,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    required this.content,
    required this.createdAt,
  });

  final int id;
  final int storyId;

  /// Không null nếu bình luận theo một chương cụ thể.
  final int? chapterId;
  final int userId;
  final String userName;
  final String? avatarUrl;
  final String content;
  final DateTime createdAt;

  /// Ký tự đầu của tên người bình luận (avatar mặc định).
  String get initial =>
      userName.trim().isEmpty ? '?' : userName.trim().substring(0, 1);

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: (json['id'] as num?)?.toInt() ?? 0,
    storyId: (json['storyId'] as num?)?.toInt() ?? 0,
    chapterId: (json['chapterId'] as num?)?.toInt(),
    userId: (json['userId'] as num?)?.toInt() ?? 0,
    userName: json['userName'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
    content: json['content'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'storyId': storyId,
    'chapterId': chapterId,
    'userId': userId,
    'userName': userName,
    'avatarUrl': avatarUrl,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
  };
}
