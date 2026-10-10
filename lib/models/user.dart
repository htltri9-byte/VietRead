/// Model `User` — khớp JSON người dùng của `/auth/*`:
/// `{ id, name, email, avatarUrl }`.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
  });

  final int id;
  final String name;
  final String email;
  final String? avatarUrl;

  /// Ký tự đầu để vẽ avatar mặc định khi chưa có ảnh.
  String get initial {
    final String trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
  }

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'email': email,
    'avatarUrl': avatarUrl,
  };
}
