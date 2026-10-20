import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/story_word.dart';
import 'package:vietread/screens/chapter_form_screen.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';

/// Test màn **Sửa chương**: hiển thị marker nhiều nghĩa `{a|b}` (KHÔNG chứa
/// chữ Hán — kể cả dữ liệu cũ), chọn nghĩa từ sheet mới (thẻ lớn, vị trí
/// 3/nhị, mũi tên trước/sau, tự chuyển chỗ), duyệt marker, hộp thoại khi lưu
/// còn marker, dịch lại có gợi ý nghĩa và lưu quy tắc theo truyện
/// ("luôn dùng" / "không hỏi lại").
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

  Future<Chapter> seedChapter(MockApiService mock, String content) async {
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    return mock.createChapter(
      1,
      title: 'Chương phục vụ test',
      content: content,
    );
  }

  Future<void> pumpForm(
    WidgetTester tester,
    MockApiService mock,
    Chapter chapter,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChapterFormScreen(
          api: mock,
          storyId: chapter.storyId,
          chapter: ChapterSummary(
            id: chapter.id,
            storyId: chapter.storyId,
            index: chapter.index,
            title: chapter.title,
            updatedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ô nội dung chương — TextField thứ 3 của form (thứ tự ổn định cả khi
  /// sheet đang mở vì sheet nằm ở route phía sau).
  EditableText contentField(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText).at(2));

  /// TextField trong bottom sheet đang mở.
  Finder sheetFields(WidgetTester tester) => find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(TextField),
  );

  testWidgets('hiển thị marker + nhãn "Còn N chỗ" + marker được tô nổi bật', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(
      mock,
      'Còn {vì|là} rút đi kiều mị và {Lý Minh|Lý Meanh} rời đi.',
    );
    await pumpForm(tester, mock, ch);

    expect(find.widgetWithText(FilledButton, 'Còn 2 chỗ'), findsOneWidget);
    expect(contentField(tester).controller.text, contains('{vì|là}'));

    // Marker phải được vẽ với style tô nền (buildTextSpan tùy biến).
    final EditableText et = contentField(tester);
    final TextSpan span = et.controller.buildTextSpan(
      context: tester.element(find.byType(EditableText).last),
      style: et.style,
      withComposing: false,
    );
    bool highlighted = false;
    void visit(InlineSpan s) {
      if (s is TextSpan) {
        if ((s.text ?? '').startsWith('{') &&
            s.style?.backgroundColor != null) {
          highlighted = true;
        }
        s.children?.forEach(visit);
      }
    }

    visit(span);
    expect(highlighted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chọn nghĩa trong sheet thay đúng marker (bỏ dấu { })', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(mock, 'Còn {vì|là} rút đi kiều mị.');
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(FilledButton, 'Còn 1 chỗ'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn nghĩa'), findsOneWidget);
    expect(find.text('Mặc định'), findsOneWidget); // nhãn nghĩa đầu (mới)
    expect(find.text('1 / 1'), findsOneWidget); // chỉ báo vị trí

    await tester.tap(find.text('là'));
    await tester.pumpAndSettle();

    expect(contentField(tester).controller.text, 'Còn là rút đi kiều mị.');
    expect(
      find.widgetWithText(FilledButton, 'Đã chọn hết nghĩa'),
      findsOneWidget,
    );
    // Hết chỗ → sheet tự đóng
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nút Trước / Sau trong sheet nhảy giữa các marker', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(
      mock,
      'Còn {vì|là} rút và {Minh|Minh H} ở lại.',
    );
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(FilledButton, 'Còn 2 chỗ'));
    await tester.pumpAndSettle();
    expect(find.text('vì'), findsOneWidget); // marker thứ nhất
    expect(find.text('1 / 2'), findsOneWidget);

    // Nhảy sang marker kế tiếp (mũi tên + chỉ báo vị trí)
    await tester.tap(find.byTooltip('Chỗ sau'));
    await tester.pumpAndSettle();
    expect(find.text('Minh H'), findsOneWidget);
    expect(find.text('vì'), findsNothing);
    expect(find.text('2 / 2'), findsOneWidget);

    // Quay lại marker đầu
    await tester.tap(find.byTooltip('Chỗ trước'));
    await tester.pumpAndSettle();
    expect(find.text('vì'), findsOneWidget);

    // Chọn nghĩa của marker thứ hai (tự chuyển sang chỗ tiếp theo vẫn bật)
    await tester.tap(find.byTooltip('Chỗ sau'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minh H'));
    await tester.pumpAndSettle();

    expect(
      contentField(tester).controller.text,
      'Còn {vì|là} rút và Minh H ở lại.',
    );
    expect(find.widgetWithText(FilledButton, 'Còn 1 chỗ'), findsOneWidget);
    // Tự chuyển: sheet vẫn mở, đã quay vòng về marker đầu tiên còn lại
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tắt “Tự chuyển sang chỗ tiếp theo” → chọn xong vẫn ở chỗ đó', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(
      mock,
      'Còn {vì|là} rút và {Minh|Minh H} ở lại.',
    );
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(FilledButton, 'Còn 2 chỗ'));
    await tester.pumpAndSettle();

    // Tắt công tắc tự chuyển
    await tester.tap(find.text('Tự chuyển sang chỗ tiếp theo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('là'));
    await tester.pumpAndSettle();

    // Đã áp dụng nhưng KHÔNG đóng sheet và KHÔNG nhảy chỗ
    expect(
      contentField(tester).controller.text,
      'Còn là rút và {Minh|Minh H} ở lại.',
    );
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Còn 1 chỗ'), findsOneWidget);

    // Chọn lại nghĩa khác cho CHÍNH chỗ vừa ghi → thay đúng chỗ đó
    await tester.tap(find.text('vì'));
    await tester.pumpAndSettle();
    expect(
      contentField(tester).controller.text,
      'Còn vì rút và {Minh|Minh H} ở lại.',
    );
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nhập nghĩa khác + áp dụng cho mọi chỗ giống nhau', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(mock, 'Tôi {đi|về} rồi {đi|về} xong.');
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(FilledButton, 'Còn 2 chỗ'));
    await tester.pumpAndSettle();

    // Bật công tắc "mọi chỗ giống nhau"
    await tester.tap(find.text('Áp dụng cho mọi chỗ giống nhau trong chương'));
    await tester.pumpAndSettle();

    // Chọn nghĩa thứ hai → cả hai chỗ đều đổi
    await tester.tap(find.text('về'));
    await tester.pumpAndSettle();

    expect(contentField(tester).controller.text, 'Tôi về rồi về xong.');
    expect(
      find.widgetWithText(FilledButton, 'Đã chọn hết nghĩa'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nhập nghĩa khác điền tay thay marker', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(mock, 'Còn {vì|là} rút đi.');
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(FilledButton, 'Còn 1 chỗ'));
    await tester.pumpAndSettle();

    await tester.enterText(sheetFields(tester), 'bởi vì');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Dùng'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing); // sheet đã đóng
    expect(contentField(tester).controller.text, 'Còn bởi vì rút đi.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Lấy nghĩa đầu cho tất cả" có xác nhận và bỏ hết marker', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(
      mock,
      'Còn {vì|là} và {Minh|Minh H} đây.',
    );
    await pumpForm(tester, mock, ch);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Lấy nghĩa đầu cho tất cả'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lấy nghĩa đầu cho tất cả?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Lấy nghĩa đầu'));
    await tester.pumpAndSettle();

    expect(contentField(tester).controller.text, 'Còn vì và Minh đây.');
    expect(
      find.widgetWithText(FilledButton, 'Đã chọn hết nghĩa'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lưu khi còn marker → "Lưu và làm tiếp sau" giữ marker', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(mock, 'Còn {vì|là} rút đi.');
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Còn 1 chỗ chưa chọn nghĩa'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Lưu và làm tiếp sau'));
    await tester.pumpAndSettle();

    // Đã pop về, marker còn nguyên trong dữ liệu
    expect(find.byType(ChapterFormScreen), findsNothing);
    final Chapter stored = await mock.fetchChapter(ch.id, raw: true);
    expect(stored.content, 'Còn {vì|là} rút đi.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lưu khi còn marker → "Lấy nghĩa đầu rồi lưu" lưu bản resolve', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(mock, 'Còn {vì|là} rút đi.');
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Lấy nghĩa đầu rồi lưu'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChapterFormScreen), findsNothing);
    final Chapter stored = await mock.fetchChapter(ch.id, raw: true);
    expect(stored.content, 'Còn vì rút đi.');
    expect(stored.content, isNot(contains('{')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Dịch lại" thay nội dung bằng bản dịch có marker', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    final Chapter ch = await mock.importChapterFromText(
      1,
      text: '夜色深沉，少年站在山巅。',
      sourceLang: 'zh',
      title: 'Chương dịch lại',
    );
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Dịch lại'));
    await tester.pumpAndSettle();
    expect(find.text('Dịch lại có gợi ý nghĩa?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Dịch lại'));
    await tester.pumpAndSettle();

    expect(contentField(tester).controller.text, contains('Bản dịch lại'));
    // Mức gợi ý mặc định 'low' được gửi kèm — khớp MARK_LEVEL của backend.
    expect(MockApiService.lastRetranslateMarkLevel, 'low');
    expect(
      contentField(tester).controller.text,
      contains('{nghĩa một|nghĩa hai|nghĩa ba}'),
    );
    // Marker MỚI không còn khóa chữ Trung {少年|…}
    expect(contentField(tester).controller.text, isNot(contains('少年')));
    expect(find.widgetWithText(FilledButton, 'Còn 2 chỗ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Dịch lại" lỗi khi không có bản gốc → hiện thông báo', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final Chapter ch = await seedChapter(mock, 'Chương nhập tay không gốc.');
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Dịch lại'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Dịch lại'));
    await tester.pumpAndSettle();

    expect(
      find.text('Chương này không có bản gốc để dịch lại'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '"Luôn dùng nghĩa này" lưu cho cả truyện + thay mọi chỗ cùng nghĩa',
    (WidgetTester tester) async {
      final MockApiService mock = api();
      // Dữ liệu CŨ còn khóa chữ Hán trong ô nội dung — sheet KHÔNG được
      // hiển thị chữ Hán ở bất kỳ đâu, vẫn lưu được theo danh sách nghĩa.
      final Chapter ch = await seedChapter(
        mock,
        'Còn {见过|khớp quá|gặp qua} và {见过|khớp quá|gặp qua} đây.',
      );
      await pumpForm(tester, mock, ch);

      await tester.tap(find.widgetWithText(FilledButton, 'Còn 2 chỗ'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn nghĩa'), findsOneWidget);

      // KHÔNG có chữ Hán nào trong cây widget của sheet
      bool hasCjkText(String value) => RegExp('[㐀-鿿豈-﫿]').hasMatch(value);
      final Iterable<String> texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Text),
            ),
          )
          .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .where((String s) => s.isNotEmpty);
      expect(texts.any(hasCjkText), isFalse, reason: 'sheet chứa chữ Hán');

      // Chọn “gặp qua” trên thẻ → áp dụng chỗ đầu, tự chuyển sang chỗ thứ hai
      // (nghĩa đã chọn được GIỮ khi chỗ mới có cùng nghĩa).
      await tester.tap(find.text('gặp qua'));
      await tester.pumpAndSettle();
      expect(
        contentField(tester).controller.text,
        'Còn gặp qua và {见过|khớp quá|gặp qua} đây.',
      );
      expect(find.byType(BottomSheet), findsOneWidget); // vẫn còn 1 chỗ

      await tester.tap(
        find.widgetWithText(
          OutlinedButton,
          'Luôn dùng nghĩa này cho truyện này',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing); // hết marker → tự đóng
      expect(
        contentField(tester).controller.text,
        'Còn gặp qua và gặp qua đây.',
      );
      expect(
        find.text('Đã "luôn dùng" "gặp qua" cho cả truyện.'),
        findsOneWidget,
      );
      expect(find.text('Hoàn tác'), findsOneWidget); // SnackBar kèm Hoàn tác

      final List<WordChoice> choices = await mock.fetchWordChoices(ch.storyId);
      expect(choices, hasLength(1));
      expect(choices.single.sourceKey, '见过'); // khóa lưu NGẦM — không hiển thị
      expect(choices.single.chosenText, 'gặp qua');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '"Không hỏi lại từ này" bỏ marker và lưu khóa bỏ hỏi theo truyện',
    (WidgetTester tester) async {
      final MockApiService mock = api();
      final Chapter ch = await seedChapter(
        mock,
        'Còn {见过|khớp quá|gặp qua} đây.',
      );
      await pumpForm(tester, mock, ch);

      await tester.tap(find.widgetWithText(FilledButton, 'Còn 1 chỗ'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Không hỏi lại từ này'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      // Lấy nghĩa đầu ngay trong ô nội dung
      expect(contentField(tester).controller.text, 'Còn khớp quá đây.');
      // Thông báo KHÔNG chứa chữ Hán (khóa lưu ngầm bên backend)
      expect(
        find.text('Đã bỏ qua "khớp quá" — không hỏi lại nữa.'),
        findsOneWidget,
      );
      expect(find.text('Hoàn tác'), findsOneWidget);

      final List<IgnoredWord> ignored = await mock.fetchIgnoredWords(
        ch.storyId,
      );
      expect(ignored, hasLength(1));
      expect(ignored.single.sourceKey, '见过');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dialog "Dịch lại" chọn mức gợi ý → gửi markLevel tương ứng', (
    WidgetTester tester,
  ) async {
    final MockApiService mock = api();
    final AuthService auth = AuthService.resetForTest(api: mock);
    await auth.login('tacgia@vietread.vn', 'VietRead@123');
    final Chapter ch = await mock.importChapterFromText(
      1,
      text: '夜色深沉，少年站在山巅。',
      sourceLang: 'zh',
      title: 'Chương chọn mức',
    );
    await pumpForm(tester, mock, ch);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Dịch lại'));
    await tester.pumpAndSettle();
    expect(find.text('Mức gợi ý nhiều nghĩa'), findsOneWidget);
    expect(MockApiService.lastRetranslateMarkLevel, isNull); // chưa gọi API

    // Chọn mức "Vừa" rồi xác nhận
    await tester.tap(find.text('Vừa'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Dịch lại'));
    await tester.pumpAndSettle();

    expect(MockApiService.lastRetranslateMarkLevel, 'medium');
    expect(contentField(tester).controller.text, contains('Bản dịch lại'));
    expect(tester.takeException(), isNull);
  });
}
