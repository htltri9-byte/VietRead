import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/story_credits.dart';

/// Widget dùng chung tách bạch **Tác giả (nguyên tác)** vs **Người đăng**.
void main() {
  Story story({
    String? originalAuthor,
    String? uploaderName,
    String author = '',
  }) =>
      Story(
        id: 1,
        title: 'Truyện Thử',
        author: author,
        authorId: 1,
        originalAuthor: originalAuthor,
        uploaderName: uploaderName,
        updatedAt: DateTime(2026, 10, 6),
      );

  Future<void> pumpCredits(WidgetTester tester, Story value) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: StoryCredits(story: value)),
      ),
    );
  }

  testWidgets('hiện đủ hai dòng: Tác giả + Người đăng', (WidgetTester tester) async {
    await pumpCredits(
      tester,
      story(originalAuthor: 'Băng Tụy Trà', uploaderName: 'ZTE'),
    );

    expect(find.text('Tác giả: Băng Tụy Trà', findRichText: true), findsOneWidget);
    expect(find.text('Người đăng: ZTE', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('không có tác giả → "Tác giả: Chưa rõ" (vẫn giữ người đăng)',
      (WidgetTester tester) async {
    await pumpCredits(tester, story(uploaderName: 'ZTE'));

    expect(find.text('Tác giả: Chưa rõ', findRichText: true), findsOneWidget);
    expect(find.text('Người đăng: ZTE', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('không có người đăng → chỉ một dòng, không dòng trống',
      (WidgetTester tester) async {
    await pumpCredits(tester, story(originalAuthor: 'Trần Nhật Nam'));

    expect(find.byType(RichText), findsOneWidget);
    expect(find.text('Tác giả: Trần Nhật Nam', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tên tác giả dài → gói 1 dòng, cắt bằng ellipsis',
      (WidgetTester tester) async {
    final String longName = 'Tên Tác Giả Rất Dài Bị Cắt Đúng Một Dòng Trong Một Ô Nhỏ';
    await pumpCredits(
      tester,
      story(originalAuthor: longName, uploaderName: 'ZTE'),
    );

    final RichText line = tester.widget<RichText>(find.byType(RichText).first);
    expect(line.maxLines, 1);
    expect(line.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  test('cardAuthor: có tên trả tên; rỗng/null trả "Chưa rõ"', () {
    expect(
      StoryCredits.cardAuthor(story(originalAuthor: 'Trần Nhật Nam')),
      'Trần Nhật Nam',
    );
    expect(StoryCredits.cardAuthor(story()), 'Chưa rõ');
    expect(StoryCredits.cardAuthor(story(originalAuthor: '   ')), 'Chưa rõ');
  });
}
