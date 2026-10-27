import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/screens/auth_screen.dart';
import 'package:vietread/screens/profile_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';

/// Kiểm tra tab "Tài khoản" (Bước 6): chưa đăng nhập → vào form đăng nhập,
/// đăng nhập xong → hiện thông tin, đăng xuất → về trạng thái ban đầu.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.resetForTest(
      api: MockApiService(latency: Duration.zero, useCoverImages: false),
    );
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ProfileScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('chưa đăng nhập → thấy lời mời và 2 nút Đăng nhập / Đăng ký', (
    WidgetTester tester,
  ) async {
    await pumpProfile(tester);

    expect(find.text('Chưa đăng nhập'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.text('Đăng ký'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bấm Đăng nhập → form đăng nhập → xong hiện tên + email', (
    WidgetTester tester,
  ) async {
    await pumpProfile(tester);

    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);

    // Nhập thông tin demo (2 tài khoản của seed.sql)
    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'docgia@vietread.vn');
    await tester.enterText(fields.at(1), 'VietRead@123');
    // Nút gửi trong form (màn nền vẫn còn trong cây nên phải giới hạn scope)
    await tester.tap(
      find.descendant(
        of: find.byType(AuthScreen),
        matching: find.widgetWithText(FilledButton, 'Đăng nhập'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsNothing);
    expect(AuthService.instance.isLoggedIn, isTrue);
    expect(find.text('docgia'), findsOneWidget); // tên hiển thị từ email
    expect(find.text('docgia@vietread.vn'), findsOneWidget);
    expect(find.text('Truyện của tôi'), findsOneWidget);
    expect(find.text('Đăng xuất'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Chờ SnackBar "Đăng nhập thành công." hết hạn
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('đăng xuất → về trạng thái chưa đăng nhập', (
    WidgetTester tester,
  ) async {
    // Đăng nhập thẳng qua service (không qua UI) cho nhanh
    await AuthService.instance.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpProfile(tester);
    expect(find.text('tacgia@vietread.vn'), findsOneWidget);

    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();

    expect(AuthService.instance.isLoggedIn, isFalse);
    expect(find.text('Chưa đăng nhập'), findsOneWidget);
    expect(find.text('Đăng xuất'), findsNothing);

    // Chờ SnackBar "Đã đăng xuất." hết hạn
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('mục chưa làm tới hiện thông báo thân thiện (A6)', (
    WidgetTester tester,
  ) async {
    await AuthService.instance.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpProfile(tester);

    await tester.tap(find.text('Truyện của tôi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('sẽ có ở bước tiếp theo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
