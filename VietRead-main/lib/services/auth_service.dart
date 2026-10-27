import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'api_service.dart';

/// Phiên đăng nhập: token JWT + thông tin người dùng (A3.1).
class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final User user;
}

/// Quản lý **đăng nhập / đăng ký / đăng xuất** và giữ đăng nhập bằng token
/// lưu trong `shared_preferences` (Bước 6).
///
/// Mở app gọi [restore] một lần để tự đăng nhập lại bằng token đã lưu;
/// giao diện nghe qua [instance] (ChangeNotifier) để tự dựng lại khi đổi phiên.
class AuthService extends ChangeNotifier {
  AuthService._({ApiService? api}) : _api = api ?? ApiService() {
    // Request thật trả 401 (token hết hạn / sai khoá ký) → tự đăng xuất để
    // UI chuyển về màn đăng nhập, không kẹt phiên chết giữa phiên chạy.
    HttpApiService.onUnauthorized = _handleUnauthorized;
  }

  /// Phiên duy nhất của app (cùng kiểu với `PrefsService.instance`).
  static AuthService instance = AuthService._();

  /// Dùng trong test: tạo lại phiên với nguồn dữ liệu giả lập, xoá trạng thái cũ.
  @visibleForTesting
  static AuthService resetForTest({ApiService? api}) {
    instance = AuthService._(api: api);
    return instance;
  }

  /// Key lưu trong `shared_preferences`.
  static const String tokenKey = 'auth_token';
  static const String userKey = 'auth_user';

  final ApiService _api;
  AuthSession? _session;
  bool _restored = false;

  /// Phiên hiện tại (`null` = chưa đăng nhập).
  AuthSession? get session => _session;

  bool get isLoggedIn => _session != null;

  /// Người dùng đang đăng nhập (tiện cho header chào, màn Tài khoản).
  User? get user => _session?.user;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Nạp token đã lưu khi mở app (giữ đăng nhập).
  ///
  /// Token hết hạn (401/403) → xoá và coi như đăng xuất;
  /// lỗi mạng → giữ token, chưa đăng nhập được (thử lại ở lần mở sau).
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;

    final SharedPreferences sp = await _prefs;
    final String? token = sp.getString(tokenKey);
    if (token == null || token.isEmpty) return;

    _api.setToken(token);
    try {
      final User me = await _api.fetchMe();
      _session = AuthSession(token: token, user: me);
      notifyListeners();
    } on ApiException catch (e) {
      _api.setToken(null);
      if (e.statusCode == 401 || e.statusCode == 403) await _clear();
    } catch (_) {
      _api.setToken(null); // lỗi mạng giữ nguyên token đã lưu
    }
  }

  /// POST /auth/login rồi lưu token + user.
  Future<User> login(String email, String password) async {
    final AuthResult result = await _api.login(email, password);
    await _save(result);
    return result.user;
  }

  /// POST /auth/register rồi lưu token + user.
  Future<User> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final AuthResult result = await _api.register(
      name: name,
      email: email,
      password: password,
    );
    await _save(result);
    return result.user;
  }

  /// Đăng xuất: gỡ token khỏi request và khỏi bộ nhớ.
  Future<void> logout() async {
    _api.setToken(null);
    await _clear();
  }

  /// Backend từ chối token (401) trong lúc đang đăng nhập → xoá phiên ngay.
  ///
  /// Gọi bởi `HttpApiService.onUnauthorized`: request tới `/auth/login`/
  /// `/auth/register` không kích hoạt (401 ở đó là sai mật khẩu), và khi
  /// chưa đăng nhập thì làm gì cũng vô hại.
  void _handleUnauthorized() {
    if (_session == null) return;
    _api.setToken(null);
    unawaited(_clear());
  }

  /// Lưu phiên vào bộ nhớ rồi báo UI dựng lại.
  Future<void> _save(AuthResult result) async {
    _api.setToken(result.token);
    _session = AuthSession(token: result.token, user: result.user);
    final SharedPreferences sp = await _prefs;
    await sp.setString(tokenKey, result.token);
    await sp.setString(userKey, jsonEncode(result.user.toJson()));
    notifyListeners();
  }

  /// Xoá phiên khỏi bộ nhớ (dùng cho đăng xuất / token hết hạn).
  Future<void> _clear() async {
    _session = null;
    final SharedPreferences sp = await _prefs;
    await sp.remove(tokenKey);
    await sp.remove(userKey);
    notifyListeners();
  }
}
