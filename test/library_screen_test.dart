import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/screens/auth_screen.dart';
import 'package:vietread/screens/library_screen.dart';
import 'package:vietread/services/api_service.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/db_helper.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/empty_state.dart';
import 'package:vietread/widgets/error_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Follow là state static của mock → trả về trạng thái sạch trước mỗi test.
    MockApiService.resetFollowsForTest();
  });

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  HistoryEntry entry(int storyId, {int index = 3, String? title}) =>
      HistoryEntry(
        storyId: storyId,
        chapterIndex: index,
        chapterTitle: title ?? 'Tên chương $index',
        progress: 0.42,
        updatedAt: DateTime(2026, 10, 7, 9, 30),
      );

  Future<void> pumpLibrary(
    WidgetTester tester, {
    ApiService? apiService,
    List<HistoryEntry>? initialHistory,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LibraryScreen(
          api: apiService ?? api(),
          initialHistory: initialHistory,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Tủ sách có đủ 3 tab: Theo dõi | Lịch sử | Đã tải', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);
    expect(find.text('Theo dõi'), findsOneWidget);
    expect(find.text('Lịch sử'), findsOneWidget);
    expect(find.text('Đã tải'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab Lịch sử: dòng "Chương N – Tên chương" kèm nút … và ×', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(
      tester,
      initialHistory: <HistoryEntry>[
        entry(7, index: 3, title: 'Đêm Trăng Cuối Cùng'),
        entry(8, index: 1),
      ],
    );

    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();

    // Dòng theo đúng mẫu A3.7
    expect(find.text('Chương 3 – Đêm Trăng Cuối Cùng'), findsOneWidget);
    expect(find.text('Chương 1 – Tên chương 1'), findsOneWidget);

    // Nút "…" (menu) và "×" (xoá nhanh) của dòng đầu
    expect(find.byTooltip('Tuỳ chọn'), findsNWidgets(2));
    expect(find.byTooltip('Xoá khỏi lịch sử'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nút "×" xoá dòng lịch sử khỏi danh sách', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(
      tester,
      initialHistory: <HistoryEntry>[entry(7), entry(8, index: 1)],
    );
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();

    // Bấm "×" của dòng đầu (Chương 3 truyện 7)
    await tester.tap(
      find.descendant(
        of: find.byType(ListTile).first,
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chương 3 – Tên chương 3'), findsNothing);
    expect(find.text('Chương 1 – Tên chương 1'), findsOneWidget);
    expect(find.text('Đã xoá khỏi lịch sử đọc.'), findsOneWidget);
  });

  testWidgets('menu "…" có Đọc tiếp và Xoá khỏi lịch sử', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester, initialHistory: <HistoryEntry>[entry(7)]);
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tuỳ chọn'));
    await tester.pumpAndSettle();

    expect(find.text('Đọc tiếp'), findsOneWidget);
    expect(find.text('Xoá khỏi lịch sử'), findsOneWidget);
  });

  testWidgets('tab Lịch sử rỗng → trạng thái rỗng', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester); // SQLite ngoài máy không sẵn sàng → []
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Chưa có lịch sử đọc'), findsOneWidget);
  });

  testWidgets('tab Đã tải: SQLite không sẵn sàng → trạng thái lỗi có Thử lại', (
    WidgetTester tester,
  ) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('Đã tải'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('tab Theo dõi chưa đăng nhập → nút Đăng nhập', (
    WidgetTester tester,
  ) async {
    AuthService.resetForTest(api: api());
    await pumpLibrary(tester);

    expect(find.text('Theo dõi truyện yêu thích'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget); // mở màn đăng nhập
  });

  testWidgets('tab Theo dõi đã đăng nhập → hiện danh sách truyện', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('docgia@vietread.vn', 'VietRead@123');
    await mock.followStory(1); // theo dõi "Kiếm Sư Vọng Tường"
    await mock.followStory(3); // và "Phố Đèn Neon"

    await pumpLibrary(tester, apiService: mock);

    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(find.text('Phố Đèn Neon'), findsOneWidget);
    expect(find.text('Chưa theo dõi truyện nào'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('đăng xuất thì tab Theo dõi về lời mời đăng nhập', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('docgia@vietread.vn', 'VietRead@123');
    await mock.followStory(1);

    await pumpLibrary(tester, apiService: mock);
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);

    await auth.logout();
    await tester.pumpAndSettle();

    expect(find.text('Theo dõi truyện yêu thích'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
  });

  testWidgets('quay lại tab Tủ sách → tải lại danh sách theo dõi mới (A3.7)', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('docgia@vietread.vn', 'VietRead@123');

    final ValueNotifier<int> shellTab = ValueNotifier<int>(0);
    addTearDown(shellTab.dispose);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LibraryScreen(api: mock, shellTab: shellTab),
      ),
    );
    await tester.pumpAndSettle();

    // Mới mở tab → chưa theo dõi gì
    expect(find.text('Chưa theo dõi truyện nào'), findsOneWidget);

    // "Ở màn khác" người dùng bấm Theo dõi (IndexedStack không tự biết)
    await mock.followStory(1);
    await mock.followStory(2);

    // Shell chọn lại tab Tủ sách → listener phải nạp lại
    shellTab.value = 1;
    await tester.pumpAndSettle();

    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(find.text('Hoàng Đạo Chi Tâm'), findsOneWidget);
    expect(find.text('Chưa theo dõi truyện nào'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shellTab không phải tab Tủ sách → không nạp lại', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('docgia@vietread.vn', 'VietRead@123');

    final ValueNotifier<int> shellTab = ValueNotifier<int>(1); // đang ở Tủ sách
    addTearDown(shellTab.dispose);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LibraryScreen(api: mock, shellTab: shellTab),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa theo dõi truyện nào'), findsOneWidget);

    await mock.followStory(1);
    shellTab.value = 0; // sang tab Khám phá → không refresh
    await tester.pumpAndSettle();
    expect(find.text('Chưa theo dõi truyện nào'), findsOneWidget);

    shellTab.value = 1; // về Tủ sách → mới refresh
    await tester.pumpAndSettle();
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
  });
}
