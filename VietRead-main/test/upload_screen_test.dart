import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/screens/auth_screen.dart';
import 'package:vietread/screens/chapter_manager_screen.dart';
import 'package:vietread/screens/upload_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/empty_state.dart';
import 'package:vietread/widgets/skeleton.dart';

/// Test tab **Đăng truyện** — CRUD truyện / chương (A3.9, Bước 9).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Truyện / chương là state static của mock → reset về seed trước mỗi test.
    MockApiService.resetStoriesForTest();
    MockApiService.resetFollowsForTest();
    MockApiService.resetCommentsForTest();
  });

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  Future<void> pumpUpload(WidgetTester tester, MockApiService mock) async {
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
  }

  /// Tạo truyện qua form: FAB "Truyện mới" → nhập tên → Lưu.
  Future<void> createStory(WidgetTester tester, String title) async {
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Truyện mới'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, title);
    await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
    await tester.pumpAndSettle();
  }

  /// Mở menu "Tuỳ chọn" của dòng truyện đầu tiên.
  Future<void> openFirstMenu(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ListTile).first,
        matching: find.byTooltip('Tuỳ chọn'),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Mở menu "Tuỳ chọn" của dòng truyện có tiêu đề [title]
  /// (dùng cho các test đổi trạng thái của một truyện cụ thể).
  Future<void> openMenuOf(WidgetTester tester, String title) async {
    final Finder tile = find
        .ancestor(of: find.text(title), matching: find.byType(ListTile))
        .first;
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip('Tuỳ chọn')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('chưa đăng nhập → lời mời đăng nhập mở AuthScreen', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    AuthService.resetForTest(api: mock); // guest
    await pumpUpload(tester, mock);

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Đăng nhập để đăng truyện'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing); // không có FAB

    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('đang nạp lần đầu → skeleton danh sách (A2, Bước 11)', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: UploadScreen(api: mock),
      ),
    );

    // Frame đầu vẫn đang tải → thấy khối skeleton, chưa thấy nội dung.
    expect(find.byType(ListSkeleton), findsOneWidget);
    expect(find.text('Kiếm Sư Vọng Tường'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(ListSkeleton), findsNothing);
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tác giả thấy 4 truyện của mình (kể cả nháp) từ /me/stories', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);

    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(find.text('Hoàng Đạo Chi Tâm'), findsOneWidget);
    expect(find.text('Phố Đèn Neon'), findsOneWidget);
    expect(find.text('Xuyên Không Làm Giàu Ở Tống Triều'), findsOneWidget);
    expect(find.text('Chưa có truyện nào'), findsNothing);
    // Seed đều là truyện đã đăng → không có chip "Nháp".
    expect(find.text('Nháp'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('độc giả chưa đăng tác phẩm nào → trạng thái rỗng', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('docgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Chưa có truyện nào'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Truyện mới'),
      findsOneWidget,
    );
  });

  testWidgets('tạo truyện mới → hiện trong danh sách kèm chip "Nháp"', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);
    expect(find.text('Truyện Kiếm Mới'), findsNothing);

    await createStory(tester, 'Truyện Kiếm Mới');

    expect(find.text('Truyện Kiếm Mới'), findsOneWidget);
    expect(find.text('Nháp'), findsOneWidget); // mặc định Lưu làm nháp
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu → "Quản lý chương" mở ChapterManagerScreen (trống)', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);
    await createStory(tester, 'Truyện Quản Lý');

    await openFirstMenu(tester);
    expect(find.text('Sửa thông tin'), findsOneWidget);
    expect(find.text('Quản lý chương'), findsOneWidget);
    expect(find.text('Gửi duyệt'), findsOneWidget);
    expect(find.text('Xoá truyện'), findsOneWidget);

    await tester.tap(find.text('Quản lý chương'));
    await tester.pumpAndSettle();

    expect(find.byType(ChapterManagerScreen), findsOneWidget);
    expect(find.text('Truyện Quản Lý'), findsOneWidget); // header
    expect(find.text('Chưa có chương nào'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Chương mới'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quản lý chương đang nạp → skeleton (Bước 11)', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);

    // Vào Quản lý chương → frame đầu của route mới đang tải
    // (route còn nằm trong transition nên finder phải kể cả widget ẩn).
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    expect(
      find.byType(ChapterManagerScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(ListSkeleton, skipOffstage: false), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(ListSkeleton), findsNothing);
    expect(find.byType(ChapterManagerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thêm chương đầu tiên → hiện trong danh sách chương', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);
    await createStory(tester, 'Truyện Có Chương');

    // Vào thẳng dòng đầu (onTap) → Quản lý chương.
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(ChapterManagerScreen), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Chương mới'));
    await tester.pumpAndSettle();
    // Thứ tự ô: Số chương (tự đánh số) | Tên chương * | Nội dung chương *
    await tester.enterText(find.byType(TextField).at(1), 'Lời mở đầu');
    await tester.enterText(
      find.byType(TextField).at(2),
      'Đây là nội dung chương đầu tiên.',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Chương 1: Lời mở đầu'), findsOneWidget);
    expect(find.text('Chưa có chương nào'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu "Gửi duyệt" → hộp thoại quyền → chip "Chờ duyệt"', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');

    // Dùng truyện seed (đã có mô tả / thể loại / chương) để đạt điều kiện
    // gửi duyệt; đưa về nháp như thể tác giả vừa mới soạn xong.
    MockApiService.setModerationForTest(1, 'draft');
    await pumpUpload(tester, mock);
    expect(find.text('Nháp'), findsOneWidget);

    await openMenuOf(tester, 'Kiếm Sư Vọng Tường');
    await tester.tap(find.text('Gửi duyệt'));
    await tester.pumpAndSettle();

    // Hộp thoại xác nhận quyền đăng — chưa tích thì nút Gửi duyệt bị khóa.
    expect(find.text('Gửi truyện đi duyệt'), findsOneWidget);
    expect(
      find.byType(CheckboxListTile),
      findsOneWidget,
    );
    FilledButton send =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gửi duyệt'));
    expect(send.onPressed, isNull); // chưa xác nhận quyền

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    send =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gửi duyệt'));
    expect(send.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Gửi duyệt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Đã gửi'), findsOneWidget);
    expect(find.text('Nháp'), findsNothing); // đã chuyển sang chờ duyệt
    expect(find.text('Chờ duyệt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('truyện thiếu điều kiện → lỗi 400 ngay khi gửi duyệt', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);
    // Truyện mới tạo chưa có mô tả / thể loại / chương → 400 kèm lý do.
    await createStory(tester, 'Truyện Chưa Đủ Điều Kiện');

    await openMenuOf(tester, 'Truyện Chưa Đủ Điều Kiện');
    await tester.tap(find.text('Gửi duyệt'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Gửi duyệt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chưa đủ điều kiện gửi duyệt'), findsOneWidget);
    expect(find.text('Nháp'), findsOneWidget); // vẫn là nháp
    expect(tester.takeException(), isNull);
  });

  testWidgets('truyện bị từ chối → hiện lý do + menu "Gửi lại"', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    MockApiService.setModerationForTest(
      1,
      'rejected',
      rejectReason: 'Mô tả còn quá ngắn, vui lòng bổ sung.',
    );
    await pumpUpload(tester, mock);

    expect(find.text('Bị từ chối'), findsOneWidget);
    expect(
      find.textContaining('Lý do: Mô tả còn quá ngắn'),
      findsOneWidget,
    );

    await openMenuOf(tester, 'Kiếm Sư Vọng Tường');
    expect(find.text('Gửi lại'), findsOneWidget);
    expect(find.text('Đăng công khai'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('truyện đã duyệt → menu "Gỡ xuống" → về nháp', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);
    expect(find.text('Đã duyệt'), findsWidgets); // seed đều đã duyệt

    await openFirstMenu(tester);
    await tester.tap(find.text('Gỡ xuống'));
    await tester.pumpAndSettle();

    // Dialog xác nhận
    expect(find.widgetWithText(FilledButton, 'Gỡ xuống'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Gỡ xuống').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Đã gỡ'), findsOneWidget);
    expect(find.text('Nháp'), findsOneWidget); // dòng đầu về nháp
    expect(tester.takeException(), isNull);
  });

  testWidgets('truyện đang chờ duyệt → menu "Đang chờ duyệt"', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    MockApiService.setModerationForTest(1, 'pending');
    await pumpUpload(tester, mock);

    expect(find.text('Chờ duyệt'), findsOneWidget);
    await openMenuOf(tester, 'Kiếm Sư Vọng Tường');
    expect(find.text('Đang chờ duyệt'), findsOneWidget);
    expect(find.text('Gửi duyệt'), findsNothing);
    expect(find.text('Gỡ xuống'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu "Xoá truyện" → dialog xác nhận → biến mất', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);
    await createStory(tester, 'Truyện Bị Xoá');

    await openFirstMenu(tester);
    await tester.tap(find.text('Xoá truyện'));
    await tester.pumpAndSettle();

    // Dialog xác nhận (Huỷ | Xoá)
    expect(find.text('Xoá "Truyện Bị Xoá"?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Xoá'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();

    expect(find.text('Đã xoá truyện.'), findsOneWidget);
    expect(find.text('Truyện Bị Xoá'), findsNothing);
    // Truyện seed còn nguyên.
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog "Huỷ" → truyện không bị xoá', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await pumpUpload(tester, mock);

    await openFirstMenu(tester);
    await tester.tap(find.text('Xoá truyện'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
    await tester.pumpAndSettle();

    expect(find.text('Đã xoá truyện.'), findsNothing);
    expect(find.text('Hoàng Đạo Chi Tâm'), findsOneWidget); // dòng đầu seed
  });
}
