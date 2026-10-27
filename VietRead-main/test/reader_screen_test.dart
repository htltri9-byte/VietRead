import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/screens/reader_screen.dart';
import 'package:vietread/services/api_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/services/prefs_service.dart';
import 'package:vietread/services/reading_progress_store.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/error_state.dart';

void main() {
  // SQLite ngoài máy không khởi tạo được trong testWidgets → DbHelper fail
  // ngay (StateError) và bị bắt sẵn, không treo luồng đọc.
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  Story story() => Story(
    id: 1,
    title: 'Kiếm Sư Vọng Tường',
    author: 'Trần Nhật Nam',
    authorId: 1,
    coverUrl: null,
    genres: const <String>['Tiên Hiệp', 'Kiếm Hiệp'],
    chapterCount: 128,
    updatedAt: DateTime.now(),
  );

  Future<void> pumpReader(
    WidgetTester tester, {
    int startIndex = 1,
    Size surface = const Size(420, 900),
    ApiService? service,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ReaderScreen(
          story: story(),
          initialIndex: startIndex,
          api: service ?? api(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tải nội dung chương, chuyển chương trước/sau, hiện tiến độ %', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);

    // Nội dung chương 1
    expect(find.textContaining('Hết chương 1'), findsOneWidget);
    expect(find.text('Chương 1'), findsOneWidget); // thanh dưới
    expect(find.text('0%'), findsOneWidget);
    expect(
      find.byTooltip('Chương trước'),
      findsOneWidget,
    ); // có nút nhưng bị tắt

    // Chương sau
    await tester.tap(find.byTooltip('Chương sau'));
    await tester.pumpAndSettle();
    expect(find.text('Chương 2'), findsOneWidget);
    expect(find.textContaining('Hết chương 2'), findsOneWidget);

    // Chương trước
    await tester.tap(find.byTooltip('Chương trước'));
    await tester.pumpAndSettle();
    expect(find.text('Chương 1'), findsOneWidget);
    expect(find.textContaining('Hết chương 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mở cài đặt đọc: chọn nền Sepia và đổi cỡ chữ', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester);

    await tester.tap(find.byTooltip('Cài đặt đọc'));
    await tester.pumpAndSettle();

    expect(find.text('Cài đặt đọc'), findsOneWidget);
    expect(find.text('Nền'), findsOneWidget);
    expect(find.text('Font chữ'), findsOneWidget);

    // Chọn nền Sepia
    await tester.tap(find.text('Sepia'));
    await tester.pumpAndSettle();
    final SharedPreferences sp = await SharedPreferences.getInstance();
    expect(sp.getString('reader_background'), 'sepia');

    // Đổi cỡ chữ bằng slider (slider đầu tiên là cỡ chữ)
    final Slider sizeSlider = tester
        .widgetList<Slider>(find.byType(Slider))
        .first;
    sizeSlider.onChanged!(24);
    await tester.pumpAndSettle();
    expect(sp.getDouble('reader_font_size'), 24.0);
    expect(find.text('Cỡ chữ: 24'), findsOneWidget);

    // Đóng sheet
    await tester.tap(find.text('Xong'));
    await tester.pumpAndSettle();
    expect(find.text('Cài đặt đọc'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tự lưu tiến độ đọc khi mở chương (shared_preferences)', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester, startIndex: 3);

    final SharedPreferences sp = await SharedPreferences.getInstance();
    final String? raw = sp.getString(PrefsService.progressKey(1));

    expect(raw, isNotNull);
    final Map<String, dynamic> saved = jsonDecode(raw!) as Map<String, dynamic>;
    expect(saved['chapterIndex'], 3);
    expect(saved['chapterTitle'], isNotEmpty);
    expect((saved['progress'] as num).toDouble(), 0.0);
    expect(sp.getInt('last_read_story_id'), 1);

    // Kho tiến độ trong RAM cũng được cập nhật (thẻ "Đọc tiếp")
    expect(ReadingProgressStore.instance.current?.chapterIndex, 3);
    expect(
      ReadingProgressStore.instance.current?.chapterLabel,
      startsWith('Chương 3'),
    );
  });

  testWidgets('cuộn tới cuối chương thì tiến độ > 0 và được lưu', (
    WidgetTester tester,
  ) async {
    // Màn hình thấp để nội dung phải cuộn
    await pumpReader(tester, surface: const Size(420, 500));

    expect(find.text('0%'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -2000),
    );
    await tester.pump(const Duration(milliseconds: 900)); // debounce 700ms

    final SharedPreferences sp = await SharedPreferences.getInstance();
    final String? raw = sp.getString(PrefsService.progressKey(1));
    expect(raw, isNotNull);
    final double saved =
        ((jsonDecode(raw!) as Map<String, dynamic>)['progress'] as num)
            .toDouble();
    expect(saved, greaterThan(0.5));

    // Thanh dưới hiển thị % đã cuộn tới
    expect(find.textContaining('%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lỗi tải chương → trạng thái lỗi + nút Thử lại', (
    WidgetTester tester,
  ) async {
    await pumpReader(tester, service: _FailingChapterApi());

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.textContaining('Wi-Fi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// API lỗi ở phần nội dung chương.
class _FailingChapterApi extends MockApiService {
  _FailingChapterApi() : super(latency: Duration.zero, useCoverImages: false);

  @override
  Future<Chapter> fetchChapter(int chapterId, {bool raw = false}) async {
    throw const ApiException(
      'Không kết nối được máy chủ. Kiểm tra Wi-Fi và địa chỉ API.',
    );
  }
}
