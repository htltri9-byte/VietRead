import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/screens/auth_screen.dart';
import 'package:vietread/screens/import_screen.dart';
import 'package:vietread/screens/upload_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/empty_state.dart';

/// Test màn **Nhập truyện từ link** — A3.10 (Bước 10).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // State static của mock → reset về seed trước mỗi test.
    MockApiService.resetStoriesForTest();
    MockApiService.resetFollowsForTest();
    MockApiService.resetCommentsForTest();
    MockApiService.resetImportsForTest();
  });

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  Future<void> pumpImport(WidgetTester tester, MockApiService mock) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ImportScreen(api: mock),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Đánh đồng hồ ảo qua các lượt poll (mỗi lượt cách nhau 1.5s).
  Future<void> pumpPolls(WidgetTester tester, {int times = 6}) async {
    for (int i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('chưa đăng nhập → lời mời đăng nhập mở AuthScreen', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    AuthService.resetForTest(api: mock); // guest
    await pumpImport(tester, mock);

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Đăng nhập để nhập truyện'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
    expect(find.text('Bắt đầu nhập'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('link rỗng hoặc sai → lỗi ngay trên ô nhập', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpImport(tester, mock);

    await tester.tap(find.widgetWithText(FilledButton, 'Bắt đầu nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng dán link truyện'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'khong-phai-link');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Bắt đầu nhập'));
    await tester.pumpAndSettle();
    expect(
      find.text('Link không hợp lệ — cần http(s) đầy đủ'),
      findsOneWidget,
    );
    // Vẫn ở form, chưa chuyển sang màn theo dõi trạng thái
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nhập nguồn hợp lệ → poll tới Done → về Truyện của tôi thấy nháp', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');

    // Vào từ tab Đăng truyện (icon AppBar).
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: UploadScreen(api: mock),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Nhập truyện từ link'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'https://m.qidian.com/book/123/',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Bắt đầu nhập'));
    await tester.pumpAndSettle();

    // Job bắt đầu chạy: Pending → Running + %
    expect(find.text('Đang chạy'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await pumpPolls(tester);
    expect(find.text('Hoàn tất'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Về Truyện của tôi'));
    await tester.pumpAndSettle();

    // Truyện nhập hiện trong "Truyện của tôi" dạng nháp.
    expect(find.byType(ImportScreen), findsNothing);
    expect(find.text('Đường Qingyun'), findsOneWidget);
    expect(find.text('Nháp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nguồn không hỗ trợ → Failed kèm thông báo lỗi + nút Thử lại', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpImport(tester, mock);

    await tester.enterText(find.byType(TextField), 'https://example.com/book/1');
    await tester.tap(find.widgetWithText(FilledButton, 'Bắt đầu nhập'));
    await tester.pumpAndSettle();

    await pumpPolls(tester);

    expect(find.text('Thất bại'), findsOneWidget);
    expect(find.textContaining('chưa được hỗ trợ'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Thử lại'), findsOneWidget);
    expect(find.text('Hoàn tất'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bấm Thử lại (Failed) → quay lại form nhập link', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpImport(tester, mock);

    await tester.enterText(find.byType(TextField), 'https://example.com/book/1');
    await tester.tap(find.widgetWithText(FilledButton, 'Bắt đầu nhập'));
    await tester.pumpAndSettle();
    await pumpPolls(tester);
    expect(find.text('Thất bại'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Thử lại'));
    await tester.pumpAndSettle();

    expect(find.text('Bắt đầu nhập'), findsOneWidget);
    expect(find.text('Thất bại'), findsNothing);
    // Link cũ vẫn còn để người dùng sửa
    expect(find.widgetWithText(TextField, 'https://example.com/book/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
