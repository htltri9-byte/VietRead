import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/screens/auth_screen.dart';
import 'package:vietread/screens/reader_screen.dart';
import 'package:vietread/screens/story_detail_screen.dart';
import 'package:vietread/services/api_service.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/error_state.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Comment là state static của mock → trả về dữ liệu mẫu trước mỗi test.
    MockApiService.resetCommentsForTest();
  });

  MockApiService api() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  Story story() => Story(
    id: 1,
    title: 'Kiếm Sư Vọng Tường',
    author: 'Trần Nhật Nam',
    authorId: 1,
    originalAuthor: 'Trần Nhật Nam',
    uploaderName: 'ZTE',
    coverUrl: null,
    description: 'Một thiếu niên đói nghèo ở biên cương vô tình thức tỉnh kiếm ý vạn năm.',
    genres: const <String>['Tiên Hiệp', 'Kiếm Hiệp'],
    status: 'ongoing',
    rating: 4.5,
    chapterCount: 128,
    isDraft: false,
    updatedAt: DateTime.now(),
  );

  Future<void> pumpDetail(WidgetTester tester, {ApiService? service}) async {
    // Màn hình rất cao để đủ 50 chương của trang 1 + nút "Xem thêm" được dựng
    tester.view.physicalSize = const Size(420, 4800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StoryDetailScreen(story: story(), api: service ?? api()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hiện đủ thông tin truyện + danh sách chương phân trang', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester);

    // Thông tin (A3.4)
    expect(find.text('Kiếm Sư Vọng Tường'), findsOneWidget);
    // Hai dòng tách bạch: Tác giả (nguyên tác) + Người đăng.
    expect(find.text('Tác giả: Trần Nhật Nam', findRichText: true),
        findsOneWidget);
    expect(find.text('Người đăng: ZTE', findRichText: true), findsOneWidget);
    expect(find.text('Tiên Hiệp'), findsWidgets);
    expect(find.text('4.5'), findsOneWidget); // điểm
    expect(find.text('Đang ra'), findsOneWidget); // trạng thái
    expect(find.text('128 chương'), findsOneWidget);
    expect(
      find.textContaining('thiếu niên đói nghèo'),
      findsOneWidget,
    ); // mô tả

    // Nút Đọc + tab
    expect(find.text('Đọc'), findsOneWidget);
    expect(find.text('Theo dõi'), findsOneWidget);
    expect(find.text('Tải offline'), findsOneWidget);
    expect(find.text('Chương'), findsOneWidget);
    expect(find.text('Bình luận'), findsOneWidget);

    // Danh sách chương: trang đầu 50 chương của 128 → có nút Xem thêm
    expect(find.textContaining('Chương 1:'), findsOneWidget);
    expect(find.text('Xem thêm chương'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bấm "Xem thêm chương" nạp tiếp trang 2', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester);

    await tester.tap(find.text('Xem thêm chương'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chương 51:'), findsOneWidget); // trang 2

    // ListView chỉ dựng chương nằm trong màn hình → cuộn xuống cuối
    // để nút "Xem thêm chương" (còn trang 3) được dựng rồi mới kiểm.
    await tester.scrollUntilVisible(
      find.text('Xem thêm chương'),
      400,
      maxScrolls: 100,
    );
    await tester.pumpAndSettle();
    expect(find.text('Xem thêm chương'), findsOneWidget); // còn trang 3
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab Bình luận: xem bình luận + lời mời đăng nhập (A3.6)', (
    WidgetTester tester,
  ) async {
    AuthService.resetForTest(api: api()); // chưa đăng nhập
    await pumpDetail(tester);

    await tester.tap(find.text('Bình luận'));
    await tester.pumpAndSettle();

    // Danh sách bình luận mẫu của mock + đếm số lượng
    expect(find.text('Truyện đọc cuốn lắm, mong chương mới!'), findsOneWidget);
    expect(find.text('Lê Minh Anh'), findsOneWidget);
    expect(find.text('1 bình luận'), findsOneWidget);
    // Chưa đăng nhập → không có ô nhập, thay bằng lời mời đăng nhập
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Đăng nhập để bình luận'), findsOneWidget);
    // Không còn placeholder "chờ Bước 8"
    expect(find.textContaining('Bước 8'), findsNothing);
    expect(find.textContaining('Chương 1:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('đã đăng nhập: gửi bình luận mới hiện lên đầu danh sách', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('docgia@vietread.vn', 'VietRead@123');
    await pumpDetail(tester, service: mock);

    await tester.tap(find.text('Bình luận'));
    await tester.pumpAndSettle();

    // Đã đăng nhập → có ô nhập + nút gửi
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Truyện hay, mong chương mới!',
    );
    await tester.tap(find.byTooltip('Gửi bình luận'));
    await tester.pumpAndSettle();

    expect(find.text('Đã gửi bình luận.'), findsOneWidget); // snackbar
    expect(find.text('Truyện hay, mong chương mới!'), findsOneWidget);
    expect(find.text('2 bình luận'), findsOneWidget);
    // Bình luận của mình → có nút xoá; của người khác thì không
    expect(find.byTooltip('Xoá bình luận'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('xoá bình luận của mình sau khi hỏi xác nhận', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('docgia@vietread.vn', 'VietRead@123');
    await pumpDetail(tester, service: mock);

    await tester.tap(find.text('Bình luận'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bình luận thử nghiệm');
    await tester.tap(find.byTooltip('Gửi bình luận'));
    await tester.pumpAndSettle();
    expect(find.text('Bình luận thử nghiệm'), findsOneWidget);

    // Bấm xoá → dialog xác nhận → Huỷ thì bình luận vẫn còn
    await tester.tap(find.byTooltip('Xoá bình luận'));
    await tester.pumpAndSettle();
    expect(find.text('Xoá bình luận?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
    await tester.pumpAndSettle();
    expect(find.text('Bình luận thử nghiệm'), findsOneWidget);

    // Xác nhận xoá → biến mất + snackbar
    await tester.tap(find.byTooltip('Xoá bình luận'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();

    expect(find.text('Đã xoá bình luận.'), findsOneWidget);
    expect(find.text('Bình luận thử nghiệm'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bấm một chương mở màn hình đọc', (WidgetTester tester) async {
    await pumpDetail(tester);

    await tester.tap(find.textContaining('Chương 1:'));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.textContaining('Hết chương 1'), findsOneWidget);
    expect(find.text('Chương 1'), findsOneWidget); // thanh dưới
    expect(tester.takeException(), isNull);
  });

  testWidgets('lỗi tải chương → trạng thái lỗi + nút Thử lại', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, service: _FailingChaptersApi());

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.textContaining('Wi-Fi'), findsOneWidget);
  });

  testWidgets('chưa đăng nhập bấm Theo dõi → mở màn đăng nhập (A3.1)', (
    WidgetTester tester,
  ) async {
    AuthService.resetForTest(api: api());
    await pumpDetail(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Theo dõi'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
  });

  testWidgets('đã đăng nhập: bấm Theo dõi → Đã theo dõi, bấm lại thì bỏ', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('docgia@vietread.vn', 'VietRead@123');
    await pumpDetail(tester, service: mock);

    // Trạng thái ban đầu: chưa theo dõi
    expect(find.widgetWithText(OutlinedButton, 'Theo dõi'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Theo dõi'));
    await tester.pumpAndSettle();

    expect(find.text('Đã theo dõi truyện.'), findsOneWidget); // snackbar
    expect(find.widgetWithText(FilledButton, 'Đã theo dõi'), findsOneWidget);
    expect(await mock.fetchMyFollows(), hasLength(1));

    // Bấm lần nữa → bỏ theo dõi
    await tester.tap(find.widgetWithText(FilledButton, 'Đã theo dõi'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Theo dõi'), findsOneWidget);
    expect(await mock.fetchMyFollows(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bấm Tải offline → dialog chọn toàn bộ hoặc khoảng chương', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Tải offline'));
    await tester.pumpAndSettle();

    // Dialog: tải toàn bộ hay chọn khoảng
    expect(
      find.widgetWithText(FilledButton, 'Tải toàn bộ (128 chương)'),
      findsOneWidget,
    );
    expect(find.text('Chọn khoảng chương...'), findsOneWidget);
    expect(find.textContaining('Truyện có 128 chương'), findsOneWidget);

    // Chọn khoảng → nhập sai → báo lỗi khoảng hợp lệ
    await tester.tap(find.text('Chọn khoảng chương...'));
    await tester.pumpAndSettle();
    expect(find.text('Từ chương'), findsOneWidget);
    expect(find.text('Đến chương'), findsOneWidget);

    final Iterable<TextField> fields = find
        .byType(TextField)
        .evaluate()
        .map((e) => e.widget as TextField);
    await tester.enterText(find.byType(TextField).first, '999');
    await tester.enterText(find.byType(TextField).last, '1');
    expect(fields, hasLength(2));

    await tester.tap(find.widgetWithText(FilledButton, 'Tải'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nhập khoảng hợp lệ'), findsOneWidget);

    // Huỷ → dialog đóng, không tải gì
    await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
    await tester.pumpAndSettle();
    expect(find.text('Từ chương'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// API chỉ lỗi ở phần danh sách chương (test nút "Thử lại").
class _FailingChaptersApi extends MockApiService {
  _FailingChaptersApi() : super(latency: Duration.zero, useCoverImages: false);

  @override
  Future<List<ChapterSummary>> fetchChapters(
    int storyId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    throw const ApiException(
      'Không kết nối được máy chủ. Kiểm tra Wi-Fi và địa chỉ API.',
    );
  }
}
