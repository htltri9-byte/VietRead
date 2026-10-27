/// Model `User` — khớp JSON người dùng của `/auth/*`:
/// `{ id, name, email, avatarUrl, role }`.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.role = 'user',
  });

  final int id;
  final String name;
  final String email;
  final String? avatarUrl;

  /// Vai trò: `'user'` | `'admin'` (thêm trường mới — client cũ bỏ qua).
  /// Admin thấy mục "Kiểm duyệt truyện" ở màn Tài khoản.
  final String role;

  /// Có phải admin không (dùng để ẩn/hiện mục kiểm duyệt).
  bool get isAdmin => role == 'admin';

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
    // Backend cũ chưa trả role → mặc định 'user' (an toàn: không thấy menu admin).
    role: json['role'] as String? ?? 'user',
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'email': email,
    'avatarUrl': avatarUrl,
    'role': role,
  };
}
