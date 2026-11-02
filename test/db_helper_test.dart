import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
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

  group('nâng cấp SQLite v1 → v2 (thêm cột, giữ dữ liệu đã tải)', () {
    test('onUpgrade ALTER TABLE: truyện/chương cũ vẫn đọc được', () async {
      final String path = p.join(
        await databaseFactory.getDatabasesPath(),
        'vietread_v1_upgrade_test.db',
      );
      await databaseFactory.deleteDatabase(path);

      // Đúng schema v1 — TRƯỚC KHI thêm originalAuthor/uploaderName.
      final Database v1 = await openDatabase(
        path,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE downloaded_stories(
              id INTEGER PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT NOT NULL DEFAULT '',
              coverPath TEXT,
              description TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE downloaded_chapters(
              id INTEGER PRIMARY KEY,
              storyId INTEGER NOT NULL,
              idx INTEGER NOT NULL,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              UNIQUE(storyId, idx)
            )
          ''');
          await db.execute('''
            CREATE TABLE reading_history(
              storyId INTEGER PRIMARY KEY,
              chapterIndex INTEGER NOT NULL,
              chapterTitle TEXT NOT NULL,
              progress REAL NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
          await db.insert('downloaded_stories', <String, Object?>{
            'id': 7,
            'title': 'Bảy Ngày Trước Bình Minh',
            'author': 'Tên Cũ',
          });
          await db.insert('downloaded_chapters', <String, Object?>{
            'id': 7001,
            'storyId': 7,
            'idx': 1,
            'title': 'Chương 1',
            'content': 'Nội dung đã tải trước nâng cấp.',
          });
        },
      );
      await v1.close();

      // Mở lại bằng DbHelper (v2) → onUpgrade chạy ALTER TABLE ADD COLUMN.
      DbHelper.resetForTest(path: path);
      final DbHelper db = DbHelper.instance;

      final DownloadedStory upgraded =
          (await db.downloadedStories()).single;
      expect(upgraded.id, 7);
      expect(upgraded.title, 'Bảy Ngày Trước Bình Minh');
      expect(upgraded.author, 'Tên Cũ'); // cột cũ giữ nguyên
      // Cột mới trên db cũ → NULL: hiện "Chưa rõ" tới khi tải lại/làm mới.
      expect(upgraded.originalAuthor, isNull);
      expect(upgraded.uploaderName, isNull);
      expect(upgraded.toStory().originalAuthor, isNull);
      // Chương + nội dung đọc offline vẫn nguyên vẹn.
      expect(await db.downloadedChapterCount(7), 1);
      final Chapter? c1 = await db.downloadedChapter(7, 1);
      expect(c1!.content, contains('trước nâng cấp'));

      // Ghi được vào cột mới sau nâng cấp (khi tải lại/làm mới).
      await db.upsertDownloadedStory(
        DownloadedStory(
          id: 7,
          title: 'Bảy Ngày Trước Bình Minh',
          author: 'Tên Cũ',
          originalAuthor: 'Nguyễn Hải Đăng',
          uploaderName: 'ZTE',
        ),
      );
      final DownloadedStory rewritten =
          (await db.downloadedStories()).single;
      expect(rewritten.originalAuthor, 'Nguyễn Hải Đăng');
      expect(rewritten.uploaderName, 'ZTE');
      expect(await db.downloadedChapterCount(7), 1); // chương không mất

      await db.close();
      await databaseFactory.deleteDatabase(path);
    });
  });
}
