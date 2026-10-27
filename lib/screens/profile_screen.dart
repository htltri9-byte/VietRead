import 'package:flutter/material.dart';

import '../models/moderation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'moderation_screen.dart';

/// Tab "Tài khoản" (A3.11): đăng nhập / đăng ký, thông tin người dùng,
/// mục "Truyện của tôi" và đăng xuất.
///
/// Trạng thái lấy từ [AuthService.instance] — nghe thay đổi qua
/// [AnimatedBuilder] nên tự dựng lại khi đăng nhập / đăng xuất.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onOpenMyStories, this.api});

  /// Chuyển sang tab "Đăng truyện" khi bấm mục "Truyện của tôi"
  /// (MainShell truyền vào — tab đã có sẵn danh sách của tác giả, Bước 9).
  final VoidCallback? onOpenMyStories;

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP) — dùng cho
  /// mục "Kiểm duyệt truyện" (nạp badge số truyện chờ duyệt).
  final ApiService? api;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loggingOut = false;

  /// Mở màn đăng nhập / đăng ký.
  Future<void> _openAuth({bool register = false}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AuthScreen(startWithRegister: register),
      ),
    );
  }

  /// Thông báo thân thiện khi chạm tính năng chưa làm tới (A6).
  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('$feature sẽ có ở bước tiếp theo của lộ trình.'),
        ),
      );
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    await AuthService.instance.logout();
    if (!mounted) return;
    setState(() => _loggingOut = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Đã đăng xuất.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: AnimatedBuilder(
        animation: AuthService.instance,
        builder: (BuildContext context, _) {
          final AuthService auth = AuthService.instance;
          return auth.isLoggedIn
              ? _LoggedInBody(
                  auth: auth,
                  api: widget.api,
                  loggingOut: _loggingOut,
                  onLogout: _logout,
                  onComingSoon: _comingSoon,
                  onOpenMyStories: widget.onOpenMyStories,
                )
              : _LoggedOutBody(
                  onLogin: () => _openAuth(),
                  onRegister: () => _openAuth(register: true),
                );
        },
      ),
    );
  }
}

/// Chưa đăng nhập: lời mời + 2 nút Đăng nhập / Đăng ký.
class _LoggedOutBody extends StatelessWidget {
  const _LoggedOutBody({required this.onLogin, required this.onRegister});

  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_outline_rounded,
                size: 36,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text('Chưa đăng nhập', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Đăng nhập để theo dõi truyện, bình luận và đăng tác phẩm của bạn.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Đăng nhập'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRegister,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Đăng ký'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Đã đăng nhập: avatar + tên + email, mục phụ và đăng xuất.
class _LoggedInBody extends StatelessWidget {
  const _LoggedInBody({
    required this.auth,
    required this.loggingOut,
    required this.onLogout,
    required this.onComingSoon,
    this.onOpenMyStories,
    this.api,
  });

  final AuthService auth;
  final ApiService? api;
  final bool loggingOut;
  final VoidCallback onLogout;
  final void Function(String) onComingSoon;
  final VoidCallback? onOpenMyStories;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ---------- Thẻ thông tin người dùng ----------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primary,
                  child: Text(
                    auth.user?.initial ?? '?',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.user?.name ?? '',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        auth.user?.email ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------- Mục phụ ----------
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.menu_book_outlined, color: scheme.primary),
                title: const Text('Truyện của tôi'),
                trailing: const Icon(Icons.chevron_right_rounded),
                // Có callback (Bước 9) → mở tab Đăng truyện; không thì báo chưa làm.
                onTap: onOpenMyStories ?? () => onComingSoon('Truyện của tôi'),
              ),
              // Chỉ admin thấy mục này (người thường không có badge).
              if (auth.user?.isAdmin == true) ...<Widget>[
                const Divider(height: 1),
                _ModerationMenuTile(api: api),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ---------- Đăng xuất ----------
        OutlinedButton.icon(
          onPressed: loggingOut ? null : onLogout,
          icon: loggingOut
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout_rounded),
          label: const Text('Đăng xuất'),
        ),
      ],
    );
  }
}

/// Mục menu **"Kiểm duyệt truyện"** (chỉ admin thấy) kèm badge số truyện
/// chờ duyệt — nạp `GET /admin/stats`, quay về màn Kiểm duyệt thì đếm lại.
class _ModerationMenuTile extends StatefulWidget {
  const _ModerationMenuTile({this.api});

  final ApiService? api;

  @override
  State<_ModerationMenuTile> createState() => _ModerationMenuTileState();
}

class _ModerationMenuTileState extends State<_ModerationMenuTile> {
  late final ApiService _api = widget.api ?? ApiService();

  int? _pending; // null = đang nạp / không tải được (ẩn badge)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _api.setToken(AuthService.instance.session?.token);
      final AdminStats stats = await _api.fetchAdminStats();
      if (mounted) setState(() => _pending = stats.pending);
    } catch (_) {
      // Không tải được badge thì mục menu vẫn mở được.
      if (mounted) setState(() => _pending = 0);
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => ModerationScreen(api: _api)),
    );
    if (mounted) _load(); // duyệt/từ chối xong → badge cập nhật
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int count = _pending ?? 0;

    return ListTile(
      leading: Icon(Icons.fact_check_outlined, color: scheme.primary),
      title: const Text('Kiểm duyệt truyện'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
      onTap: _open,
    );
  }
}
