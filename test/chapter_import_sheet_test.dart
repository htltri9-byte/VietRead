import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/screens/chapter_manager_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';

/// Test bottom sheet **Thêm chương** (link Qidian / dán văn bản) mở từ
/// màn Quản lý chương — A3.11.
void main() {
  const String validLink =
      'https://m.qidian.com/chapter/1040765595/806596284/';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MockApiService.resetStoriesForTest();
    MockApiService.resetFollowsForTest();
    MockApiService.resetCommentsForTest();
    MockApiService.resetImportsForTest();
  });

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  final Story story = Story(
    id: 1,
    title: 'Kiếm Sư Vọng Tường',
    author: 'Trần Nhật Nam',
    authorId: 1,
    genres: const <String>['Tiên Hiệp'],
    chapterCount: 128,
    updatedAt: DateTime.now(),
  );

  Future<void> pumpManager(WidgetTester tester, MockApiService mock) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChapterManagerScreen(api: mock, story: story),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Thêm chương từ link'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm chương'), findsOneWidget);
  }

  testWidgets('validate link trên ô: rỗng / sai URL / không phải Qidian', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    await pumpManager(tester, mock);
    await openSheet(tester);

    // Rỗng
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng dán link chương Qidian'), findsOneWidget);

    // Không phải URL
    await tester.enterText(find.byType(TextField).first, 'khong-phai-link');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Link không hợp lệ — cần http(s) đầy đủ'), findsOneWidget);

    // Đúng URL nhưng không thuộc Qidian
    await tester.enterText(
      find.byType(TextField).first,
      'https://example.com/chapter/1/2',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Chỉ hỗ trợ thêm chương từ Qidian'), findsOneWidget);

    // Vẫn ở trong sheet, chưa thêm chương nào
    expect(find.text('Thêm chương'), findsOneWidget);
    expect(find.text('Đã thêm chương mới.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lỗi backend hiện đúng message + nút Thử lại', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    await pumpManager(tester, mock);
    await openSheet(tester);

    // Link VIP (mock mô phỏng lỗi nguồn)
    await tester.enterText(
      find.byType(TextField).first,
      'https://m.qidian.com/chapter/1040765595/vip/',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('trả phí (VIP)'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Thử lại'), findsOneWidget);
    expect(find.text('Đã thêm chương mới.'), findsNothing);

    // Thử lại → chạy lại và vẫn báo đúng lỗi (không crash)
    await tester.tap(find.widgetWithText(TextButton, 'Thử lại'));
    await tester.pumpAndSettle();
    expect(find.textContaining('trả phí (VIP)'), findsOneWidget);
    expect(find.text('Thêm chương'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thành công: đóng sheet, nạp lại danh sách, hiện SnackBar', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    await pumpManager(tester, mock);
    expect(find.text('Đang ra · 128 chương'), findsOneWidget);

    await openSheet(tester);
    await tester.enterText(find.byType(TextField).first, validLink);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();

    // Sheet đóng + SnackBar
    expect(find.text('Thêm chương'), findsNothing);
    expect(find.text('Đã thêm chương mới.'), findsOneWidget);
    // Danh sách nạp lại: số chương 128 → 129
    expect(find.text('Đang ra · 129 chương'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dán lại cùng chương → hiện lỗi trùng 409 của backend', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    await pumpManager(tester, mock);
    // Thêm sẵn 1 chương từ link này (giống đã import trước đó).
    await mock.login('tacgia@vietread.vn', 'VietRead@123');
    await mock.importChapterFromUrl(1, chapterUrl: validLink);

    await openSheet(tester);
    await tester.enterText(find.byType(TextField).first, validLink);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chương này đã được nhập'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Thử lại'), findsOneWidget);
    expect(find.text('Thêm chương'), findsOneWidget); // vẫn ở trong sheet
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab Dán văn bản: chọn ngôn ngữ nguồn rồi thêm thành công', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    await pumpManager(tester, mock);
    await openSheet(tester);

    // Chuyển sang tab dán văn bản
    await tester.tap(find.text('Dán văn bản'));
    await tester.pumpAndSettle();
    expect(find.text('Nội dung chương *'), findsOneWidget);

    // Văn bản rỗng → lỗi trên ô
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng dán nội dung chương'), findsOneWidget);

    // Chọn nguồn Việt rồi thêm
    await tester.enterText(
      find.byType(TextField),
      'Nội dung chương dán bằng tiếng Việt.',
    );
    await tester.tap(find.text('Việt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();

    expect(find.text('Thêm chương'), findsNothing);
    expect(find.text('Đã thêm chương mới.'), findsOneWidget);
    expect(find.text('Đang ra · 129 chương'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tự nhận diện ngôn ngữ dán: Trung → dịch, Việt → lưu nguyên', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    await pumpManager(tester, mock);

    // Vòng 1: dán tiếng Việt → tự chọn "Việt", lưu nguyên.
    await openSheet(tester);
    await tester.tap(find.text('Dán văn bản'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Nội dung tiếng Việt giữ nguyên.',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Văn bản tiếng Việt được lưu nguyên, không dịch.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Đã thêm chương mới.'), findsOneWidget);

    // Vòng 2: dán Việt trước rồi thay bằng tiếng Trung → tự đổi sang "Trung".
    await openSheet(tester);
    await tester.tap(find.text('Dán văn bản'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Nội dung tiếng Việt khác.',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Văn bản tiếng Việt được lưu nguyên, không dịch.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '第一章 永夜，天地漆黑。');
    await tester.pumpAndSettle();
    expect(
      find.text('Văn bản tiếng Trung sẽ được dịch sang tiếng Việt.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Đã thêm chương mới.'), findsOneWidget);

    // Đúng nội dung lưu theo ngôn ngữ đã tự nhận diện:
    // chương 129 (vi) lưu nguyên; chương 130 (zh) là bản dịch.
    final List<ChapterSummary> chapters = await mock.fetchChapters(
      1,
      pageSize: 200,
    );
    final ChapterSummary viCh =
        chapters.firstWhere((ChapterSummary c) => c.index == 129);
    expect(
      (await mock.fetchChapter(viCh.id)).content,
      'Nội dung tiếng Việt giữ nguyên.',
    );
    final ChapterSummary zhCh =
        chapters.firstWhere((ChapterSummary c) => c.index == 130);
    expect(
      (await mock.fetchChapter(zhCh.id)).content,
      startsWith('Bản dịch'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('chọn tay ngôn ngữ được giữ nguyên khi sửa text', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    await pumpManager(tester, mock);
    await openSheet(tester);
    await tester.tap(find.text('Dán văn bản'));
    await tester.pumpAndSettle();

    // Dán tiếng Trung → tự nhận diện "Trung" (mặc định cũng là Trung).
    await tester.enterText(find.byType(TextField), '第一章 起风。');
    await tester.pumpAndSettle();
    expect(
      find.text('Văn bản tiếng Trung sẽ được dịch sang tiếng Việt.'),
      findsOneWidget,
    );

    // Bấm chọn tay "Việt" rồi sửa text → không bị auto-đổi lại.
    await tester.tap(find.text('Việt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第一章 起风修改。');
    await tester.pumpAndSettle();
    expect(
      find.text('Văn bản tiếng Việt được lưu nguyên, không dịch.'),
      findsOneWidget,
    );

    // Thêm → giữ nguyên theo lựa chọn tay (không dịch).
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Đã thêm chương mới.'), findsOneWidget);
    final List<ChapterSummary> chapters = await mock.fetchChapters(
      1,
      pageSize: 200,
    );
    final ChapterSummary last =
        chapters.firstWhere((ChapterSummary c) => c.index == 129);
    expect((await mock.fetchChapter(last.id)).content, '第一章 起风修改。');
    expect(tester.takeException(), isNull);
  });
}
