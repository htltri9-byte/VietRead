import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/screens/chapter_manager_screen.dart';
import 'package:vietread/screens/replace_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';

/// Test màn **Tìm & thay thế** theo truyện: xem trước (dryRun), thay thật,
/// hoàn tác, quy tắc "Áp dụng cho chương thêm sau này" và cô lập giữa truyện.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MockApiService.resetStoriesForTest();
    MockApiService.resetFollowsForTest();
    MockApiService.resetCommentsForTest();
    MockApiService.resetImportsForTest();
  MockApiService.resetGlossaryForTest();
  });

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  Future<void> pumpReplace(
    WidgetTester tester,
    MockApiService mock, {
    int storyId = 1,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ReplaceScreen(api: mock, storyId: storyId),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Nhập A/B và bấm Xem trước.
  Future<void> preview(WidgetTester tester, String a, String b) async {
    await tester.enterText(find.byType(TextField).at(0), a);
    await tester.enterText(find.byType(TextField).at(1), b);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Xem trước'));
    await tester.pumpAndSettle();
  }

  testWidgets('xem trước đếm đúng chỗ/chương, thay thật và hoàn tác được', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');

    final Chapter ch1 = await mock.createChapter(
      1,
      title: 'Mở đầu',
      content: 'Đầu bếp Tống Triều nấu nước mắm.',
    );
    final Chapter ch2 = await mock.createChapter(
      1,
      title: 'Tiếp tục',
      content: 'Tống Triều thịnh vượng.',
    );
    // Truyện khác — không được đụng tới.
    final Chapter other = await mock.createChapter(
      4,
      title: 'Truyện khác',
      content: 'Tống Triều không được đụng.',
    );

    await pumpReplace(tester, mock);
    await preview(tester, 'Tống Triều', 'Đại Tống');

    expect(find.text('Tìm thấy 2 chỗ trong 2 chương'), findsOneWidget);
    expect(find.text('Chương ${ch1.index} — 1 chỗ'), findsOneWidget);
    expect(find.text('Chương ${ch2.index} — 1 chỗ'), findsOneWidget);

    // Sau xem trước → nút "Thay ngay" mới bật.
    final FilledButton afterPreview = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Thay ngay'),
    );
    expect(afterPreview.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Thay ngay'));
    await tester.pumpAndSettle();
    expect(find.text('Thay 2 chỗ trong 2 chương?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Thay thật'));
    await tester.pumpAndSettle();

    expect(find.text('Đã thay 2 chỗ trong 2 chương'), findsOneWidget);
    expect((await mock.fetchChapter(ch1.id)).content, contains('Đại Tống'));
    // Truyện khác vẫn nguyên vẹn.
    expect(
      (await mock.fetchChapter(other.id)).content,
      'Tống Triều không được đụng.',
    );

    // Hoàn tác batch gần nhất
    await tester.tap(find.widgetWithText(OutlinedButton, 'Hoàn tác'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hoàn tác'));
    await tester.pumpAndSettle();

    expect(find.text('Đã hoàn tác 2 chương'), findsAtLeastNWidgets(1));
    expect(
      (await mock.fetchChapter(ch1.id)).content,
      'Đầu bếp Tống Triều nấu nước mắm.',
    );
    expect(
      (await mock.fetchChapter(ch2.id)).content,
      'Tống Triều thịnh vượng.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'quy tắc ApplyToFuture áp cho chương MỚI của truyện này, không truyện khác',
    (WidgetTester tester) async {
      final MockApiService mock = api();
      final AuthService auth = AuthService.resetForTest(api: mock);
      await auth.login('tacgia@vietread.vn', 'VietRead@123');

      await mock.createChapter(
        1,
        title: 'Có La sinh',
        content: 'La sinh ôm Lâm Hiếu Lỗ. La sinh cười.',
      );

      await pumpReplace(tester, mock);
      await tester.enterText(find.byType(TextField).at(0), 'La sinh');
      await tester.enterText(find.byType(TextField).at(1), 'La Sinh');
      await tester.pumpAndSettle();
      // Bật "Áp dụng cho chương thêm sau này"
      await tester.tap(find.text('Áp dụng cho chương thêm sau này'));
      await tester.pumpAndSettle();

      await preview(tester, 'La sinh', 'La Sinh');
      expect(find.text('Tìm thấy 2 chỗ trong 1 chương'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Thay ngay'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Thay thật'));
      await tester.pumpAndSettle();

      // Quy tắc xuất hiện trong danh sách
      expect(find.text('La sinh → La Sinh'), findsOneWidget);

      // Chương MỚI của truyện này được áp quy tắc tự động...
      final Chapter newChapter = await mock.createChapter(
        1,
        title: 'Chương mới',
        content: 'La sinh nói.',
      );
      expect((await mock.fetchChapter(newChapter.id)).content, 'La Sinh nói.');

      // ...nhưng truyện khác KHÔNG bị ảnh hưởng.
      final Chapter otherStory = await mock.createChapter(
        4,
        title: 'Truyện khác',
        content: 'La sinh nói.',
      );
      expect((await mock.fetchChapter(otherStory.id)).content, 'La sinh nói.');

      // Xoá quy tắc → chương mới sau đó không còn bị thay.
      await tester.tap(find.byTooltip('Xoá quy tắc'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa có quy tắc nào'), findsOneWidget);

      final Chapter afterDelete = await mock.createChapter(
        1,
        title: 'Chương sau xoá',
        content: 'La sinh nói.',
      );
      expect((await mock.fetchChapter(afterDelete.id)).content, 'La sinh nói.');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'validate: rỗng / A giống B / nút Thay ngay chỉ bật sau xem trước',
    (WidgetTester tester) async {
      final MockApiService mock = api();
      final AuthService auth = AuthService.resetForTest(api: mock);
      await auth.login('tacgia@vietread.vn', 'VietRead@123');

      await pumpReplace(tester, mock);

      // "Thay ngay" tắt khi chưa xem trước
      final FilledButton runButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Thay ngay'),
      );
      expect(runButton.onPressed, isNull);

      // Rỗng
      await tester.tap(find.widgetWithText(OutlinedButton, 'Xem trước'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập tên cần thay.'), findsOneWidget);

      // A == B
      await preview(tester, 'abc', 'abc');
      expect(
        find.text('Chuỗi cần tìm và chuỗi thay thế không được giống nhau'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('vào được màn Tìm & thay thế từ màn Quản lý chương', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Story story = Story(
      id: 1,
      title: 'Kiếm Sư Vọng Tường',
      author: 'Trần Nhật Nam',
      authorId: 1,
      genres: const <String>['Tiên Hiệp'],
      chapterCount: 128,
      updatedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChapterManagerScreen(api: mock, story: story),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tìm & thay thế'));
    await tester.pumpAndSettle();

    expect(find.byType(ReplaceScreen), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
