import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/models/genre.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/screens/search_screen.dart';
import 'package:vietread/screens/story_detail_screen.dart';
import 'package:vietread/services/api_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/empty_state.dart';
import 'package:vietread/widgets/error_state.dart';

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

/// Nguồn lỗi (test trạng thái lỗi + nút Thử lại).
class _FailingApi extends MockApiService {
  _FailingApi() : super(latency: Duration.zero, useCoverImages: false);

  @override
  Future<List<Story>> fetchStories({
    String? query,
    String? genre,
    String? status,
    String sort = 'newest',
    int page = 1,
    int pageSize = 12,
  }) async {
    throw const ApiException(
      'Không kết nối được máy chủ. Kiểm tra Wi-Fi và địa chỉ API.',
    );
  }
}

void main() {
  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  /// Bơm màn tìm kiếm với kích thước lớn để lưới 2 cột đủ chỗ.
  Future<void> pumpSearch(
    WidgetTester tester, {
    ApiService? service,
    String? initialQuery,
    String? initialGenre,
  }) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SearchScreen(
          api: service ?? api(),
          initialQuery: initialQuery,
          initialGenre: initialGenre,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mở màn → hiện đủ ô tìm kiếm + chip thể loại + 2 bộ lọc', (
    WidgetTester tester,
  ) async {
    await pumpSearch(tester);

    // Ô tìm kiếm + nút quay lại
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Quay lại'), findsOneWidget);

    // Chip thể loại: "Tất cả" + 8 thể loại mẫu (Tất cả đang chọn)
    expect(find.text('Tất cả'), findsOneWidget);
    expect(find.text('Tiên Hiệp'), findsOneWidget);
    expect(find.text('Huyền Huyễn'), findsOneWidget);

    // 2 bộ lọc: trạng thái + sắp xếp (mặc định "Trạng thái"/"Mới nhất")
    expect(find.text('Trạng thái'), findsOneWidget);
    expect(find.text('Mới nhất'), findsWidgets); // label + giá trị trong nút

    // Kết quả mặc định: 8 truyện (sort=newest)
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(find.text('Hoàng Đạo Chi Tâm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gõ từ khoá + tìm → chỉ còn kết quả khớp (A3.3)', (
    WidgetTester tester,
  ) async {
    await pumpSearch(tester);

    await tester.enterText(find.byType(TextField), 'Hoàng Đạo');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Hoàng Đạo Chi Tâm'), findsOneWidget);
    expect(find.text('Kiếm Sư Vọng Tường'), findsNothing);
    expect(tester.takeException(), isNull);

    // Nút × hiện ra khi có từ khoá → bấm để xoá
    await tester.tap(find.byTooltip('Xoá từ khoá'));
    await tester.pumpAndSettle();
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
  });

  testWidgets('chọn chip thể loại → lọc theo thể loại đó', (
    WidgetTester tester,
  ) async {
    await pumpSearch(tester);

    // "Huyền Huyễn" nằm trong vùng nhìn thấy của hàng chip cuộn ngang
    await tester.tap(find.text('Huyền Huyễn'));
    await tester.pumpAndSettle();

    expect(find.text('Hoàng Đạo Chi Tâm'), findsOneWidget);
    expect(find.text('Kiếm Sư Vọng Tường'), findsNothing);
    // Chọn lại chip đang chọn → bỏ lọc, hiện lại toàn bộ
    await tester.tap(find.text('Huyền Huyễn'));
    await tester.pumpAndSettle();
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lọc trạng thái + sắp xếp qua menu', (WidgetTester tester) async {
    await pumpSearch(tester);

    // Trạng thái: Hoàn thành → chỉ truyện completed
    await tester.tap(find.text('Trạng thái'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoàn thành')); // item trong menu đang mở
    await tester.pumpAndSettle();

    expect(find.text('Phố Đèn Neon'), findsOneWidget);
    expect(find.text('Kiếm Sư Vọng Tường'), findsNothing); // đang ra → bị loại

    // Bỏ lọc trạng thái → hiện lại 8 truyện
    await tester.tap(
      find.text('Hoàn thành').first,
    ); // label + giá trị trong nút
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tất cả trạng thái'));
    await tester.pumpAndSettle();
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);

    // Sắp xếp: chọn "Tên A→Z" → không lỗi, giữ bộ lọc
    await tester.tap(find.text('Mới nhất').first); // label + giá trị trong nút
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tên A→Z'));
    await tester.pumpAndSettle();

    expect(find.text('Tên A→Z'), findsWidgets); // nhãn nút sau khi chọn
    expect(find.text('Bảy Ngày Trước Bình Minh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initialGenre chọn sẵn khi mở từ chip trang chủ', (
    WidgetTester tester,
  ) async {
    await pumpSearch(tester, initialGenre: 'Tiên Hiệp');

    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    expect(find.text('Lôi Đài Cuối Đời'), findsOneWidget);
    expect(find.text('Phố Đèn Neon'), findsNothing); // Ngôn Tình/Đô Thị
    expect(tester.takeException(), isNull);
  });

  testWidgets('rỗng → trạng thái rỗng (A2)', (WidgetTester tester) async {
    await pumpSearch(tester, service: _EmptyApi());
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Không tìm thấy truyện nào'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lỗi → trạng thái lỗi + nút Thử lại (A6)', (
    WidgetTester tester,
  ) async {
    await pumpSearch(tester, service: _FailingApi());
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.textContaining('Wi-Fi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bấm thẻ kết quả → mở màn chi tiết truyện', (
    WidgetTester tester,
  ) async {
    await pumpSearch(tester, initialQuery: 'Hoàng Đạo');

    await tester.tap(find.text('Hoàng Đạo Chi Tâm'));
    await tester.pumpAndSettle();

    expect(find.byType(StoryDetailScreen), findsOneWidget);
    expect(find.text('Trần Nhật Nam'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
