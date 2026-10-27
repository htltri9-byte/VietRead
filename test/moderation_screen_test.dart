import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/moderation.dart';
import 'package:vietread/screens/moderation_chapter_screen.dart';
import 'package:vietread/screens/moderation_detail_screen.dart';
import 'package:vietread/screens/moderation_screen.dart';
import 'package:vietread/screens/profile_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/empty_state.dart';
import 'package:vietread/widgets/error_state.dart';
import 'package:vietread/widgets/skeleton.dart';
import 'package:vietread/widgets/tab_pill.dart';

/// Test chức năng **kiểm duyệt truyện** phía Flutter:
/// - mục menu chỉ hiện khi `role = admin`,
/// - màn Kiểm duyệt: lọc theo tab, duyệt, từ chối bắt buộc lý do,
/// - người thường gọi `/admin/*` → lỗi 403 hiện trên màn hình lỗi.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MockApiService.resetStoriesForTest();
    MockApiService.resetFollowsForTest();
    MockApiService.resetCommentsForTest();
  });

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  Future<void> pumpAt(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: home),
    );
    await tester.pumpAndSettle();
  }

  // ------------------------- Mục menu ở màn Tài khoản -------------------------

  testWidgets('màn Tài khoản: admin thấy mục "Kiểm duyệt truyện" + badge', (
    WidgetTester tester,
  ) async {
    MockApiService.setModerationForTest(1, 'pending'); // 1 truyện chờ duyệt
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('admin@vietread.vn', 'VietRead@123');

    await pumpAt(tester, ProfileScreen(api: mock));

    expect(find.text('Kiểm duyệt truyện'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // badge số truyện chờ duyệt
    expect(tester.takeException(), isNull);
  });

  testWidgets('màn Tài khoản: người thường KHÔNG thấy mục kiểm duyệt', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');

    await pumpAt(tester, ProfileScreen(api: mock));

    expect(find.text('Kiểm duyệt truyện'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ------------------------- Danh sách kiểm duyệt -------------------------

  testWidgets('màn Kiểm duyệt: 4 tab lọc + tab Chờ duyệt rỗng khi chưa ai gửi', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('admin@vietread.vn', 'VietRead@123');

    // Màn rộng để đủ chỗ cho cả 4 chip lọc (không phải cuộn ngang).
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: ModerationScreen(api: mock)),
    );
    await tester.pumpAndSettle();

    for (final ModerationTab tab in ModerationTab.values) {
      expect(
        find.descendant(
          of: find.byType(TabPill),
          matching: find.text(tab.label),
        ),
        findsOneWidget,
      );
    }
    // Seed đều đã duyệt → tab Chờ duyệt rỗng.
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Không có truyện chờ duyệt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('màn Kiểm duyệt: chuyển tab "Đã duyệt" → hiện danh sách thẻ', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('admin@vietread.vn', 'VietRead@123');

    await pumpAt(tester, ModerationScreen(api: mock));
    expect(find.text('Kiếm Sư Vọng Tường'), findsNothing); // tab chờ duyệt rỗng

    await tester.tap(
      find.descendant(
        of: find.byType(TabPill),
        matching: find.text('Đã duyệt'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('người thường mở màn Kiểm duyệt → lỗi 403 có nút Thử lại', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');

    await pumpAt(tester, ModerationScreen(api: mock));

    expect(find.byType(ErrorState), findsOneWidget);
    expect(
      find.text('Chỉ admin mới dùng được chức năng này'),
      findsOneWidget,
    );
    expect(find.byType(ListSkeleton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('truyện chờ duyệt hiện trong tab Chờ duyệt (skeleton → thẻ)', (
    WidgetTester tester,
  ) async {
    MockApiService.setModerationForTest(1, 'pending');
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('admin@vietread.vn', 'VietRead@123');

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ModerationScreen(api: mock),
      ),
    );
    // Frame đầu đang tải → skeleton.
    expect(find.byType(ListSkeleton), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(find.text('Chờ duyệt'), findsWidgets); // chip trạng thái
    expect(find.textContaining('chương'), findsWidgets); // số chương
    expect(tester.takeException(), isNull);
  });

  // ------------------------- Chi tiết: đọc chương, duyệt, từ chối -------------------------

  testWidgets('chi tiết kiểm duyệt: đọc được chương, khối quét ẩn, Duyệt có xác nhận', (
    WidgetTester tester,
  ) async {
    MockApiService.setModerationForTest(1, 'pending');
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('admin@vietread.vn', 'VietRead@123');

    await pumpAt(tester, ModerationScreen(api: mock));
    await tester.tap(find.text('Kiếm Sư Vọng Tường'));
    await tester.pumpAndSettle();

    expect(find.byType(ModerationDetailScreen), findsOneWidget);
    // Mock chưa chạy quét → khối "Kết quả quét tự động" phải ẩn.
    expect(find.text('Kết quả quét tự động'), findsNothing);
    // Danh sách chương → bấm đọc (màn đọc đơn giản của Admin).
    expect(find.textContaining('Chương ('), findsOneWidget);

    await tester.ensureVisible(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(ModerationChapterScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Duyệt → hộp thoại xác nhận → OK.
    await tester.tap(find.widgetWithText(FilledButton, 'Duyệt'));
    await tester.pumpAndSettle();
    expect(find.text('Duyệt truyện?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Duyệt'),
      ),
    );
    await tester.pumpAndSettle();

    // Quay về danh sách + nạp lại → tab Chờ duyệt không còn truyện nào.
    expect(find.byType(ModerationDetailScreen), findsNothing);
    expect(find.textContaining('Đã duyệt'), findsWidgets); // snackbar + chip?
    expect(find.text('Không có truyện chờ duyệt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Từ chối: lý do < 5 ký tự bị chặn, đạt thì truyện rời tab chờ duyệt', (
    WidgetTester tester,
  ) async {
    MockApiService.setModerationForTest(1, 'pending');
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('admin@vietread.vn', 'VietRead@123');

    await pumpAt(tester, ModerationScreen(api: mock));
    await tester.tap(find.text('Kiếm Sư Vọng Tường'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Từ chối'));
    await tester.pumpAndSettle();
    expect(find.text('Từ chối / Gỡ truyện'), findsOneWidget);

    // Lý do quá ngắn (3 ký tự) → báo lỗi, hộp thoại vẫn mở.
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Từ chối'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Lý do phải có ít nhất 5 ký tự.'),
      findsOneWidget,
    );
    expect(find.text('Từ chối / Gỡ truyện'), findsOneWidget);

    // Đủ 5 ký tự → từ chối thành công, quay về danh sách và nạp lại.
    await tester.enterText(
      find.byType(TextField),
      'Nội dung vi phạm bản quyền.',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Từ chối'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ModerationDetailScreen), findsNothing);
    expect(find.text('Không có truyện chờ duyệt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ------------------------- Cần xem lại: chỉ chương thay đổi -------------------------

  testWidgets(
    'cần xem lại: chi tiết chỉ hiện chương thêm/sửa sau lần duyệt trước',
    (WidgetTester tester) async {
      // Truyện 1 chờ duyệt → Admin duyệt (đặt mốc ReviewedAt).
      MockApiService.setModerationForTest(1, 'pending');
      final MockApiService mock = api();
      final AuthService adminSession = AuthService.resetForTest(api: mock);
      await adminSession.login('admin@vietread.vn', 'VietRead@123');
      await mock.approveAdminStory(1);

      // Tác giả thêm 1 chương vào truyện đã duyệt → NeedsRecheck + chương đổi.
      final AuthService authorSession = AuthService.resetForTest(api: mock);
      await authorSession.login('tacgia@vietread.vn', 'VietRead@123');
      await mock.createChapter(
        1,
        title: 'Chương thêm sau duyệt',
        content: 'Nội dung viết sau khi truyện được duyệt.',
      );

      // Admin mở chi tiết kiểm duyệt.
      final AuthService admin = AuthService.resetForTest(api: mock);
      await admin.login('admin@vietread.vn', 'VietRead@123');
      await pumpAt(tester, ModerationDetailScreen(api: mock, storyId: 1));

      // Chỉ 1 chương thay đổi được liệt kê (1/129) — chương đã duyệt ẩn.
      expect(find.text('Chương thay đổi (1/129)'), findsOneWidget);
      expect(
        find.text('Chỉ hiển thị chương thay đổi sau lần duyệt trước.'),
        findsOneWidget,
      );
      expect(find.text('Chương thêm sau duyệt'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.textContaining('Chương 1:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
