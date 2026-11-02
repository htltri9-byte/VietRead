import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/screens/story_form_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';

/// Form tạo/sửa truyện: ô **Tác giả (nguyên tác)** (không bắt buộc) +
/// nút "Dùng tên tài khoản của tôi" + validate ≤ 200 ký tự.
void main() {
  late MockApiService mock;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MockApiService.resetStoriesForTest();
    mock = MockApiService(latency: Duration.zero, useCoverImages: false);
  });

  /// Mở form qua một nút (để khi Lưu pop về vẫn còn route cha).
  Future<void> openForm(WidgetTester tester, {Story? story}) async {
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext ctx) => FilledButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => StoryFormScreen(api: mock, story: story),
                ),
              ),
              child: const Text('mở form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở form'));
    await tester.pumpAndSettle();
  }

  testWidgets('form có ô "Tác giả (nguyên tác)" kèm gợi ý và nút dùng tên tôi',
      (WidgetTester tester) async {
    await openForm(tester);

    expect(find.widgetWithText(TextField, 'Tác giả (nguyên tác)'), findsOneWidget);
    expect(
      find.text(
        'Tên tác giả gốc của truyện. Nếu bạn tự sáng tác, hãy ghi tên bút danh của bạn.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Dùng tên tài khoản của tôi'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bấm "Dùng tên tài khoản của tôi" điền tên đang đăng nhập',
      (WidgetTester tester) async {
    await openForm(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Dùng tên tài khoản của tôi'));
    await tester.pump();

    // Tên tài khoản đang đăng nhập (mock: name = phần trước @).
    expect(find.widgetWithText(TextField, 'tacgia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ô tác giả giới hạn 200 ký tự', (WidgetTester tester) async {
    await openForm(tester);

    // Thứ tự TextField trong form: tên, mô tả, bìa, tác giả.
    await tester.enterText(
      find.byType(TextField).at(3),
      'N' * 250,
    );
    await tester.pump();

    final TextField field =
        tester.widget<TextField>(find.byType(TextField).at(3));
    expect(field.controller!.text.length, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tạo truyện: gửi originalAuthor lên mock và lưu đúng',
      (WidgetTester tester) async {
    await openForm(tester);

    await tester.enterText(find.byType(TextField).first, 'Truyện Kiểm Thử Tác Giả');
    await tester.enterText(find.byType(TextField).at(3), 'Băng Tụy Trà');
    await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
    await tester.pumpAndSettle();

    final List<Story> mine = await mock.fetchMyStories();
    final Story saved = mine.firstWhere(
      (Story s) => s.title == 'Truyện Kiểm Thử Tác Giả',
    );
    expect(saved.originalAuthor, 'Băng Tụy Trà');
    expect(saved.uploaderName, 'tacgia'); // người đăng = mình
    expect(tester.takeException(), isNull);
  });

  testWidgets('sửa truyện nhập: ô tác giả điền sẵn từ nguồn, sửa được',
      (WidgetTester tester) async {
    await mock.login('tacgia@vietread.vn', 'VietRead@123');
    final int storyId = await mock.createStory(
      title: 'Nhập Từ Link',
      originalAuthor: 'Diễn Kì Tác Người',
    ).then((Story s) => s.id);

    final Story story = await mock.fetchStory(storyId);
    await openForm(tester, story: story);

    // Điền sẵn từ nguồn, vẫn sửa được.
    expect(find.widgetWithText(TextField, 'Diễn Kì Tác Người'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(3), 'Tác Giả Đã Sửa');
    await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
    await tester.pumpAndSettle();

    final Story saved = await mock.fetchStory(storyId);
    expect(saved.originalAuthor, 'Tác Giả Đã Sửa');
    expect(tester.takeException(), isNull);
  });
}
