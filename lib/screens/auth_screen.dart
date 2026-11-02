import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Màn **đăng nhập / đăng ký** (A3.1) — email + mật khẩu, giữ đăng nhập
/// bằng token (lưu trong `shared_preferences` qua [AuthService]).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.startWithRegister = false});

  /// Mở thẳng tab đăng ký (dùng cho nút "Đăng ký" ở màn Tài khoản).
  final bool startWithRegister;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { login, register }

class _AuthScreenState extends State<AuthScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.startWithRegister) _mode = _AuthMode.register;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isRegister => _mode == _AuthMode.register;

  /// Chuyển qua lại giữa 2 tab — giữ dữ liệu đã nhập.
  void _switchMode(_AuthMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  /// Kiểm tra form trước khi gửi (thông báo tiếng Việt thân thiện).
  String? _validateEmail(String? value) {
    final String email = (value ?? '').trim();
    if (email.isEmpty) return 'Vui lòng nhập email.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Email chưa đúng định dạng (ví dụ: ban@vietread.vn).';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Vui lòng nhập mật khẩu.';
    if (_isRegister && password.length < 6) {
      return 'Mật khẩu phải có ít nhất 6 ký tự.';
    }
    return null;
  }

  /// Gửi đăng nhập / đăng ký lên backend rồi đóng màn hình.
  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final AuthService auth = AuthService.instance;
    try {
      if (_isRegister) {
        await auth.register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await auth.login(_emailController.text, _passwordController.text);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRegister
                ? 'Đăng ký thành công. Chúc bạn đọc vui vẻ!'
                : 'Đăng nhập thành công.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // Lỗi từ backend (sai mật khẩu, email trùng...) — hiện nguyên văn.
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      // Lỗi không xác định → thông báo chung (A6).
      if (!mounted) return;
      setState(() {
        _error = 'Đã có lỗi xảy ra. Vui lòng thử lại.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? 'Đăng ký' : 'Đăng nhập')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------- Logo + lời chào ----------
                  Icon(
                    Icons.menu_book_rounded,
                    size: 52,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'VietRead',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isRegister
                        ? 'Tạo tài khoản để theo dõi, bình luận và đăng truyện.'
                        : 'Đăng nhập để theo dõi, bình luận và đăng truyện.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ---------- Chuyển tab Đăng nhập / Đăng ký ----------
                  SegmentedButton<_AuthMode>(
                    segments: const <ButtonSegment<_AuthMode>>[
                      ButtonSegment<_AuthMode>(
                        value: _AuthMode.login,
                        label: Text('Đăng nhập'),
                      ),
                      ButtonSegment<_AuthMode>(
                        value: _AuthMode.register,
                        label: Text('Đăng ký'),
                      ),
                    ],
                    selected: <_AuthMode>{_mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<_AuthMode> values) =>
                        _switchMode(values.first),
                  ),
                  const SizedBox(height: 20),

                  // ---------- Tên (chỉ khi đăng ký) ----------
                  if (_isRegister) ...[
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Tên hiển thị',
                        hintText: 'Nguyễn Văn A',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (String? value) => (value ?? '').trim().isEmpty
                          ? 'Vui lòng nhập tên hiển thị.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ---------- Email ----------
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'ban@vietread.vn',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 14),

                  // ---------- Mật khẩu ----------
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      hintText: _isRegister ? 'Tối thiểu 6 ký tự' : '••••••••',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: _validatePassword,
                  ),

                  // ---------- Lỗi từ backend ----------
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ---------- Nút gửi ----------
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(_isRegister ? 'Tạo tài khoản' : 'Đăng nhập'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
