import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'auth_screen.dart';

/// Tab "Tài khoản" (A3.11): đăng nhập / đăng ký, thông tin người dùng,
/// mục "Truyện của tôi", cài đặt và đăng xuất.
///
/// Trạng thái lấy từ [AuthService.instance] — nghe thay đổi qua
/// [AnimatedBuilder] nên tự dựng lại khi đăng nhập / đăng xuất.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onOpenMyStories});

  /// Chuyển sang tab "Đăng truyện" khi bấm mục "Truyện của tôi"
  /// (MainShell truyền vào — tab đã có sẵn danh sách của tác giả, Bước 9).
  final VoidCallback? onOpenMyStories;

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
  });

  final AuthService auth;
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
                onTap: onOpenMyStories ??
                    () => onComingSoon('Truyện của tôi'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.tune_rounded, color: scheme.primary),
                title: const Text('Cài đặt giao diện'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onComingSoon('Cài đặt giao diện'),
              ),
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
