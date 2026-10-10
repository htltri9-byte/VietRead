import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/genre.dart';
import 'package:vietread/models/reading_progress.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/screens/home_screen.dart';
import 'package:vietread/screens/search_screen.dart';
import 'package:vietread/screens/story_detail_screen.dart';
import 'package:vietread/services/api_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/services/prefs_service.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/error_state.dart';
import 'package:vietread/widgets/skeleton.dart';

/// Nguồn luôn rỗng (test trạng thái rỗng).
class _EmptyApi extends MockApiService {
  _EmptyApi() : super(latency: Duration.zero, useCoverImages: false);

  @override
  Future<List<Genre>> fetchGenres() async => <Genre>[];

  @override
  Future<List<Story>> fetchStories({
    String? query,
    String? genre,
    String? status,
    String sort = 'newest',
    int page = 1,
    int pageSize = 12,
  }) async => <Story>[];
}

/// Nguồn lỗi lần đầu, các lần sau trả dữ liệu (test nút "Thử lại").
class _FlakyApi extends MockApiService {
  _FlakyApi() : super(latency: Duration.zero, useCoverImages: false);

  int _calls = 0;

  @override
  Future<List<Genre>> fetchGenres() async {
    if (_calls++ == 0) {
      throw const ApiException(
        'Không kết nối được máy chủ. Kiểm tra Wi-Fi và địa chỉ API.',
      );
    }
    return super.fetchGenres();
  }
}

void main() {
  MockApiService mockApi() => MockApiService(
    latency: const Duration(milliseconds: 100),
    useCoverImages: false, // test không cần mạng
  );

  /// Trồng sẵn tiến độ "đọc dở" trong shared_preferences —
  /// thẻ "Đọc tiếp" giờ đọc dữ liệu thật đã lưu (Bước 5).
  setUp(() {
    final ReadingProgress seeded = ReadingProgress(
      story: Story(
        id: 1,
        title: 'Kiếm Sư Vọng Tường',
        author: 'Trần Nhật Nam',
        authorId: 1,
        coverUrl: null,
        genres: const <String>['Tiên Hiệp', 'Kiếm Hiệp'],
        chapterCount: 128,
        updatedAt: DateTime.now(),
      ),
      chapterIndex: 12,
      chapterTitle: 'Kiếm Ngưng Tường',
      progress: 0.62,
      updatedAt: DateTime.now(),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'last_read_story_id': 1,
      PrefsService.progressKey(1): jsonEncode(seeded.toJson()),
    });
  });

  /// Bơm app với màn hình cao để toàn bộ khối của trang chủ được dựng.
  Future<void> pumpHome(WidgetTester tester, ApiService api) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(api: api),
      ),
    );
  }

  testWidgets(
    'hiện skeleton khi tải, sau đó hiện đủ 5 khối của trang Khám phá',
    (WidgetTester tester) async {
      await pumpHome(tester, mockApi());

      // Đang tải → skeleton
      expect(find.byType(HomeSkeleton), findsOneWidget);
      expect(find.text('Đang hot'), findsNothing);

      // Hết thời gian tải (mock delay 100ms)
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(find.byType(HomeSkeleton), findsNothing);

      // Khối 1: header chào + ô tìm kiếm bo tròn
      expect(find.textContaining('Chào buổi'), findsOneWidget);
      expect(find.text('Hôm nay bạn muốn đọc gì?'), findsOneWidget);
      expect(find.text('Tìm truyện, tác giả...'), findsOneWidget);

      // Khối 2: thẻ "Đọc tiếp" (mock store có sẵn 1 mục)
      expect(find.text('ĐỌC TIẾP'), findsOneWidget);
      expect(find.text('Chương 12 — Kiếm Ngưng Tường'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);

      // Khối 3: chip thể loại cuộn ngang
      expect(find.text('Chọn thể loại'), findsOneWidget);
      expect(find.text('Tiên Hiệp'), findsOneWidget);

      // Khối 4: lưới "Đang hot"
      expect(find.text('Đang hot'), findsOneWidget);
      expect(find.text('Hoàng Đạo Chi Tâm'), findsWidgets);
      expect(find.text('4.8'), findsWidgets); // điểm số
      expect(find.text('128 chương'), findsWidgets); // số chương

      // Khối 5: "Mới cập nhật" có thời gian tương đối
      expect(find.text('Mới cập nhật'), findsOneWidget);
      expect(find.textContaining('trước'), findsWidgets);

      // Không có lỗi tràn layout
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('trạng thái lỗi có nút "Thử lại" và tải lại được', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, _FlakyApi());

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // Lỗi → thông báo tiếng Việt + nút Thử lại
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.textContaining('Wi-Fi'), findsOneWidget);
    expect(find.text('Đang hot'), findsNothing);

    // Bấm "Thử lại" → tải lại thành công
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Đang hot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dữ liệu rỗng → trạng thái rỗng', (WidgetTester tester) async {
    await pumpHome(tester, _EmptyApi());

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Chưa có truyện nào'), findsOneWidget);
    expect(find.text('Đang hot'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chạm chip thể loại → mở màn Tìm kiếm & lọc với thể loại chọn sẵn', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, mockApi());
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    // Dùng chip "Tiên Hiệp" (luôn nằm trong vùng nhìn thấy của hàng cuộn ngang)
    await tester.tap(find.text('Tiên Hiệp').first);
    await tester.pumpAndSettle();

    // Mở màn Tìm kiếm & lọc (A3.3) thay cho snackbar "chưa làm"
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.textContaining('sẽ có ở bước tiếp theo'), findsNothing);
    // Chip "Tiên Hiệp" trong màn tìm kiếm đang được chọn (chỉ 1)
    expect(find.text('Tiên Hiệp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chạm ô tìm kiếm → mở màn Tìm kiếm & lọc', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, mockApi());
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    await tester.tap(find.text('Tìm truyện, tác giả...'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // ô nhập của màn tìm kiếm
    expect(tester.takeException(), isNull);
  });

  testWidgets('chạm thẻ truyện mở màn chi tiết truyện (Bước 5)', (
    WidgetTester tester,
  ) async {
    await pumpHome(tester, mockApi());
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    await tester.tap(find.text('Hoàng Đạo Chi Tâm').first);
    await tester.pumpAndSettle();

    // Đã vào màn chi tiết: hiện tác giả + tab Chương/Bình luận + danh sách chương
    expect(find.byType(StoryDetailScreen), findsOneWidget);
    expect(find.text('Trần Nhật Nam'), findsOneWidget);
    expect(find.text('Bình luận'), findsOneWidget);
    expect(find.textContaining('Chương 1:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
