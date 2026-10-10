import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/models/chapter.dart';
import 'package:vietread/models/downloaded_story.dart';
import 'package:vietread/models/reading_progress.dart';
import 'package:vietread/models/story.dart';
import 'package:vietread/services/db_helper.dart';

import 'helpers/sqflite_test_setup.dart';

void main() {
  setUpAll(setUpSqfliteFfi);
  setUp(resetDbForTest);
  tearDown(() => DbHelper.instance.close());

  Chapter chapter(int storyId, int index) => Chapter(
    id: storyId * 1000 + index,
    storyId: storyId,
    index: index,
    title: 'Chương $index: Thử Nghiệm',
    content: 'Nội dung chương $index đủ dấu tiếng Việt.',
  );

  group('downloaded_stories + downloaded_chapters (A4)', () {
    test('ghi truyện và đếm số chương đã tải', () async {
      final DbHelper db = DbHelper.instance;
      expect(await db.isDownloaded(7), isFalse);

      await db.upsertDownloadedStory(
        DownloadedStory(
          id: 7,
          title: 'Bảy Ngày Trước Bình Minh',
          author: 'Nguyễn Hải Đăng',
          description: 'Trinh thám.',
        ),
      );
      expect(await db.isDownloaded(7), isTrue);
      expect(await db.downloadedChapterCount(7), 0);

      final List<DownloadedStory> list = await db.downloadedStories();
      expect(list.single.id, 7);
      expect(list.single.title, 'Bảy Ngày Trước Bình Minh');
      expect(list.single.chapterCount, 0);
    });

    test(
      'thay toàn bộ chương rồi thêm chương mới (giữ chương ngoài khoảng)',
      () async {
        final DbHelper db = DbHelper.instance;
        await db.upsertDownloadedStory(
          DownloadedStory(id: 7, title: 'Truyện A', author: 'Tác giả A'),
        );

        await db.replaceDownloadedChapters(7, <Chapter>[
          chapter(7, 1),
          chapter(7, 2),
          chapter(7, 3),
        ]);
        expect(await db.downloadedChapterCount(7), 3);
        expect(await db.hasChapter(7, 2), isTrue);

        // Tải thêm khoảng 5–6 mà không xoá 1–3
        await db.insertDownloadedChapters(7, <Chapter>[
          chapter(7, 5),
          chapter(7, 6),
        ]);
        expect(await db.downloadedChapterCount(7), 5);
        expect(await db.hasChapter(7, 1), isTrue);

        // Tóm tắt chương sắp xếp tăng dần theo idx
        final List<ChapterSummary> summaries = await db
            .downloadedChapterSummaries(7);
        expect(summaries.map((ChapterSummary s) => s.index).toList(), <int>[
          1,
          2,
          3,
          5,
          6,
        ]);

        // Nội dung đọc offline đúng
        final Chapter? c5 = await db.downloadedChapter(7, 5);
        expect(c5, isNotNull);
        expect(c5!.content, contains('Nội dung chương 5'));
        expect(await db.downloadedChapter(7, 4), isNull);
      },
    );

    test('xoá truyện thì chương cũng biến mất (giải phóng bộ nhớ)', () async {
      final DbHelper db = DbHelper.instance;
      await db.upsertDownloadedStory(
        DownloadedStory(id: 7, title: 'Truyện A', author: 'Tác giả A'),
      );
      await db.replaceDownloadedChapters(7, <Chapter>[
        chapter(7, 1),
        chapter(7, 2),
      ]);

      await db.deleteDownloadedStory(7);
      expect(await db.isDownloaded(7), isFalse);
      expect(await db.downloadedChapterCount(7), 0);
      expect(await db.downloadedStories(), isEmpty);
    });
  });

  group('reading_history (A4)', () {
    ReadingProgress progress(int storyId, int index, {DateTime? at}) =>
        ReadingProgress(
          story: Story(
            id: storyId,
            title: 'Truyện $storyId',
            author: 'Tác giả',
            authorId: 1,
            updatedAt: DateTime(2026),
          ),
          chapterIndex: index,
          chapterTitle: 'Tên chương $index',
          progress: 0.5,
          updatedAt: at ?? DateTime(2026, 10, 7, 14, index),
        );

    test('mỗi truyện 1 dòng, mới đọc gần nhất trước', () async {
      final DbHelper db = DbHelper.instance;
      await db.recordHistory(progress(1, 3));
      await db.recordHistory(progress(2, 1));
      // Đọc lại truyện 1 → ghi đè, không tạo dòng thứ hai
      await db.recordHistory(progress(1, 4));

      final List<HistoryEntry> rows = await db.history();
      expect(rows.length, 2);
      expect(rows.first.storyId, 1);
      expect(rows.first.chapterIndex, 4);
      expect(rows.first.chapterTitle, 'Tên chương 4');
      expect(rows.first.chapterLabel, 'Chương 4 – Tên chương 4');
      expect(rows.last.storyId, 2);
    });

    test('xoá một dòng lịch sử', () async {
      final DbHelper db = DbHelper.instance;
      await db.recordHistory(progress(1, 3));
      await db.recordHistory(progress(2, 1));

      await db.deleteHistory(1);
      final List<HistoryEntry> rows = await db.history();
      expect(rows.map((HistoryEntry r) => r.storyId).toList(), <int>[2]);
    });
  });
}
