import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/screens/auth_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';

/// Nút gửi của form đăng nhập — tránh trùng AppBar/segment cùng chữ.
Finder submitLogin() => find.widgetWithText(FilledButton, 'Đăng nhập');

/// Kiểm tra màn đăng nhập / đăng ký (A3.1, Bước 6):
/// validate tiếng Việt, lỗi backend, thành công → giữ token.
void main() {
  MockApiService mock() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.resetForTest(api: mock());
  });

  Future<void> pumpAuth(WidgetTester tester, {bool register = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AuthScreen(startWithRegister: register),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Màn nền có nút để mở [AuthScreen] như người dùng thật (pop về được).
  Future<void> pumpLauncher(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (BuildContext context) => FilledButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder: (_) => const AuthScreen()),
                ),
                child: const Text('Mở màn đăng nhập'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAuth(WidgetTester tester) async {
    await tester.tap(find.text('Mở màn đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
  }

  /// Nhập email + mật khẩu ở form đăng nhập.
  Future<void> fillLogin(WidgetTester tester, String email, String pass) async {
    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), pass);
  }

  testWidgets('thiếu thông tin → hiện thông báo tiếng Việt, chưa đăng nhập', (
    WidgetTester tester,
  ) async {
    await pumpAuth(tester);

    await tester.tap(submitLogin());
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập email.'), findsOneWidget);
    expect(find.text('Vui lòng nhập mật khẩu.'), findsOneWidget);
    expect(AuthService.instance.isLoggedIn, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('email sai định dạng → hiện thông báo định dạng', (
    WidgetTester tester,
  ) async {
    await pumpAuth(tester);

    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'chua-dung-dinh-dang');
    await tester.enterText(fields.at(1), '123456');
    await tester.tap(submitLogin());
    await tester.pumpAndSettle();

    expect(find.textContaining('Email chưa đúng định dạng'), findsOneWidget);
    expect(AuthService.instance.isLoggedIn, isFalse);
  });

  testWidgets('sai mật khẩu → hiện lỗi 401 từ backend (A6)', (
    WidgetTester tester,
  ) async {
    await pumpAuth(tester);

    await fillLogin(tester, 'docgia@vietread.vn', 'sai-mat-khau');
    await tester.tap(submitLogin());
    await tester.pumpAndSettle();

    expect(find.text('Email hoặc mật khẩu không đúng'), findsOneWidget);
    expect(find.byType(AuthScreen), findsOneWidget); // vẫn ở lại form
    expect(AuthService.instance.isLoggedIn, isFalse);
  });

  testWidgets('đăng nhập thành công → hiện snackbar, giữ token, đóng màn', (
    WidgetTester tester,
  ) async {
    await pumpLauncher(tester);
    await openAuth(tester);

    await fillLogin(tester, 'docgia@vietread.vn', 'VietRead@123');
    await tester.tap(submitLogin());
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsNothing); // đã đóng màn
    expect(find.text('Đăng nhập thành công.'), findsOneWidget);
    expect(AuthService.instance.isLoggedIn, isTrue);
    expect(AuthService.instance.user?.email, 'docgia@vietread.vn');

    // Chờ SnackBar hết hạn để test không còn timer treo
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('chuyển tab Đăng ký → hiện ô tên, mật khẩu tối thiểu 6 ký tự', (
    WidgetTester tester,
  ) async {
    await pumpAuth(tester, register: true);
    expect(find.text('Tên hiển thị'), findsOneWidget);

    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Người Mới');
    await tester.enterText(fields.at(1), 'moi@vietread.vn');
    await tester.enterText(fields.at(2), '123');
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pumpAndSettle();

    expect(find.text('Mật khẩu phải có ít nhất 6 ký tự.'), findsOneWidget);
    expect(AuthService.instance.isLoggedIn, isFalse);
  });

  testWidgets('đăng ký hợp lệ → tạo tài khoản và tự đăng nhập', (
    WidgetTester tester,
  ) async {
    await pumpLauncher(tester);
    await openAuth(tester);

    // Chuyển sang tab Đăng ký
    await tester.tap(find.text('Đăng ký'));
    await tester.pumpAndSettle();

    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Người Mới');
    await tester.enterText(fields.at(1), 'moi@vietread.vn');
    await tester.enterText(fields.at(2), '123456');
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsNothing);
    expect(AuthService.instance.isLoggedIn, isTrue);
    expect(AuthService.instance.user?.name, 'Người Mới');

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
