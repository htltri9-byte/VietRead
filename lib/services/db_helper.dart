import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/chapter.dart';
import '../models/downloaded_story.dart';
import '../models/reading_progress.dart';

/// Một dòng trong bảng `reading_history` (A4).
class HistoryEntry {
  const HistoryEntry({
    required this.storyId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.progress,
    required this.updatedAt,
  });

  final int storyId;

  /// Chương đọc gần nhất của truyện (bắt đầu từ 1).
  final int chapterIndex;
  final String chapterTitle;

  /// Vị trí đọc trong chương, 0.0–1.0.
  final double progress;
  final DateTime updatedAt;

  /// Dòng hiển thị ở tab Lịch sử, ví dụ `Chương 12 – Kiếm Ngưng Tường` (A3.7).
  String get chapterLabel => 'Chương $chapterIndex – $chapterTitle';

  /// Ví dụ `06/10/2026 14:32`.
  String get timeLabel {
    final String dd = updatedAt.day.toString().padLeft(2, '0');
    final String mm = updatedAt.month.toString().padLeft(2, '0');
    final String hh = updatedAt.hour.toString().padLeft(2, '0');
    final String mi = updatedAt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${updatedAt.year} $hh:$mi';
  }

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    storyId: (json['storyId'] as num?)?.toInt() ?? 0,
    chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 1,
    chapterTitle: json['chapterTitle'] as String? ?? '',
    progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// Truy cập SQLite cục bộ — đúng 3 bảng trong **A4**:
/// `downloaded_stories`, `downloaded_chapters`, `reading_history`.
///
/// SQLite chỉ để dùng offline trên máy; CSDL chính nằm ở SQL Server phía backend (A1).
/// Test dùng `sqflite_common_ffi` (đổi [databaseFactory] trong setUpAll).
class DbHelper {
  DbHelper._(this._path);

  /// Phiên duy nhất của app (đổi được trong test).
  static DbHelper instance = DbHelper._(null);

  /// Dùng trong test: tạo phiên với đường dẫn riêng (ví dụ `inMemoryDatabasePath`).
  @visibleForTesting
  static DbHelper resetForTest({String? path}) {
    instance = DbHelper._(path);
    return instance;
  }

  final String? _path;
  Future<Database>? _dbFuture;

  /// Mở db lười (mở 1 lần, giữ cho tới khi [close]).
  ///
  /// Lỗi mở (ví dụ SQLite chưa sẵn sàng trong test) không được giữ lại:
  /// nếu giữ Future lỗi thì các lần đọc sau có thể chờ phải một Future đã
  /// "chết" từ lần gọi trước → treo giao diện.
  Future<Database> get _db {
    final Future<Database>? cached = _dbFuture;
    if (cached != null) return cached;
    return _dbFuture = _open().catchError((Object e) {
      _dbFuture = null; // bỏ bản lỗi, lần sau tự thử lại
      throw e;
    });
  }

  Future<Database> _open() async {
    // Chưa có factory SQLite (plugin/ffi chưa khởi tạo, ví dụ flutter test
    // trên máy tính) → fail ngay bằng StateError thay vì chờ MethodChannel
    // hay isolate không có hồi đáp làm treo mọi lần đọc/ghi sau này.
    if (databaseFactoryOrNull == null) {
      throw StateError(
        'SQLite chưa sẵn sàng trên máy này (chưa khởi tạo databaseFactory).',
      );
    }
    final String path =
        _path ??
        p.join(await databaseFactory.getDatabasesPath(), 'vietread.db');
    return openDatabase(
      path,
      version: 2,
      // Không dùng singleInstance: nếu lần mở trước lỗi/ở môi trường khác
      // thì Future cũ còn "treo" kéo theo mọi lần mở sau.
      singleInstance: false,
      // v1→v2: thêm cột originalAuthor/uploaderName (giữ nguyên dữ liệu đã tải).
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await _addColumnIfMissing(db, 'downloaded_stories', 'originalAuthor');
          await _addColumnIfMissing(db, 'downloaded_stories', 'uploaderName');
        }
      },
      onCreate: (Database db, int version) async {
        // A4: downloaded_stories + cột tác giả/người đăng (v2)
        await db.execute('''
          CREATE TABLE downloaded_stories(
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT NOT NULL DEFAULT '',
            originalAuthor TEXT,
            uploaderName TEXT,
            coverPath TEXT,
            description TEXT
          )
        ''');
        // A4: downloaded_chapters(id, storyId, idx, title, content)
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
        // A4: reading_history(storyId, chapterIndex, chapterTitle, progress, updatedAt)
        await db.execute('''
          CREATE TABLE reading_history(
            storyId INTEGER PRIMARY KEY,
            chapterIndex INTEGER NOT NULL,
            chapterTitle TEXT NOT NULL,
            progress REAL NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
      },
    );
  }

  /// Đóng db (dùng trong test để dọn dẹp; app thật giữ db mở xuyên suốt).
  Future<void> close() async {
    final Future<Database>? pending = _dbFuture;
    _dbFuture = null;
    if (pending != null) await (await pending).close();
  }

  // ------------------------------------------------------------------
  // Truyện / chương đã tải
  // ------------------------------------------------------------------

  /// Thêm cột vào bảng đã tồn tại nếu chưa có (migration idempotent).
  Future<void> _addColumnIfMissing(Database db, String table, String column) async {
    final List<Map<String, Object?>> info = await db.rawQuery(
      'PRAGMA table_info($table)',
    );
    final bool exists = info.any(
      (Map<String, Object?> c) => c['name'] == column,
    );
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');
    }
  }

  /// Ghi (hoặc ghi đè) thông tin truyện vào `downloaded_stories`.
  Future<void> upsertDownloadedStory(DownloadedStory story) async {
    final Database db = await _db;
    await db.insert('downloaded_stories', <String, Object?>{
      'id': story.id,
      'title': story.title,
      'author': story.author,
      'originalAuthor': story.originalAuthor,
      'uploaderName': story.uploaderName,
      'coverPath': story.coverPath,
      'description': story.description,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Thay toàn bộ chương đã tải của một truyện (dùng khi tải xong một khoảng).
  Future<void> replaceDownloadedChapters(
    int storyId,
    List<Chapter> chapters,
  ) async {
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        'downloaded_chapters',
        where: 'storyId = ?',
        whereArgs: <Object>[storyId],
      );
      final Batch batch = txn.batch();
      for (final Chapter c in chapters) {
        batch.insert('downloaded_chapters', <String, Object?>{
          'id': c.id,
          'storyId': storyId,
          'idx': c.index,
          'title': c.title,
          'content': c.content,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Thêm chương mới, giữ các chương đã tải trước đó (khi tải thêm một khoảng).
  Future<void> insertDownloadedChapters(
    int storyId,
    List<Chapter> chapters,
  ) async {
    final Database db = await _db;
    final Batch batch = db.batch();
    for (final Chapter c in chapters) {
      batch.insert('downloaded_chapters', <String, Object?>{
        'id': c.id,
        'storyId': storyId,
        'idx': c.index,
        'title': c.title,
        'content': c.content,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Danh sách truyện đã tải (kèm số chương) — tab "Đã tải" (A3.7).
  Future<List<DownloadedStory>> downloadedStories() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT s.id, s.title, s.author, s.originalAuthor, s.uploaderName,
             s.coverPath, s.description,
             (SELECT COUNT(*) FROM downloaded_chapters c WHERE c.storyId = s.id) AS chapterCount
      FROM downloaded_stories s
      ORDER BY s.title COLLATE NOCASE
    ''');
    return rows.map(DownloadedStory.fromJson).toList(growable: false);
  }

  /// Một truyện có đang được tải không.
  Future<bool> isDownloaded(int storyId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'downloaded_stories',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object>[storyId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Số chương đã tải của một truyện.
  Future<int> downloadedChapterCount(int storyId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM downloaded_chapters WHERE storyId = ?',
      <Object>[storyId],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Danh sách chương đã tải (tăng dần theo idx) — dựng danh sách khi đọc offline.
  Future<List<ChapterSummary>> downloadedChapterSummaries(int storyId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'downloaded_chapters',
      columns: <String>['id', 'storyId', 'idx', 'title'],
      where: 'storyId = ?',
      whereArgs: <Object>[storyId],
      orderBy: 'idx',
    );
    return rows
        .map(
          (Map<String, Object?> r) => ChapterSummary(
            id: (r['id'] as num?)?.toInt() ?? 0,
            storyId: (r['storyId'] as num?)?.toInt() ?? 0,
            index: (r['idx'] as num?)?.toInt() ?? 0,
            title: r['title'] as String? ?? '',
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .toList(growable: false);
  }

  /// Nội dung một chương đã tải (`null` = chưa tải chương này).
  Future<Chapter?> downloadedChapter(int storyId, int index) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'downloaded_chapters',
      where: 'storyId = ? AND idx = ?',
      whereArgs: <Object>[storyId, index],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> r = rows.first;
    return Chapter(
      id: (r['id'] as num?)?.toInt() ?? 0,
      storyId: (r['storyId'] as num?)?.toInt() ?? 0,
      index: (r['idx'] as num?)?.toInt() ?? index,
      title: r['title'] as String? ?? '',
      content: r['content'] as String? ?? '',
    );
  }

  /// Một chương đã được tải chưa (dùng để quyết định đọc offline hay online).
  Future<bool> hasChapter(int storyId, int index) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'downloaded_chapters',
      columns: <String>['idx'],
      where: 'storyId = ? AND idx = ?',
      whereArgs: <Object>[storyId, index],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Xoá một truyện + toàn bộ chương đã tải (giải phóng bộ nhớ — A3.8).
  Future<void> deleteDownloadedStory(int storyId) async {
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        'downloaded_chapters',
        where: 'storyId = ?',
        whereArgs: <Object>[storyId],
      );
      await txn.delete(
        'downloaded_stories',
        where: 'id = ?',
        whereArgs: <Object>[storyId],
      );
    });
  }

  // ------------------------------------------------------------------
  // Lịch sử đọc (reading_history — A4)
  // ------------------------------------------------------------------

  /// Ghi (ghi đè) tiến độ đọc của một truyện — mỗi truyện 1 dòng, mới nhất trước.
  Future<void> recordHistory(ReadingProgress value) async {
    final Database db = await _db;
    await db.insert('reading_history', <String, Object?>{
      'storyId': value.story.id,
      'chapterIndex': value.chapterIndex,
      'chapterTitle': value.chapterTitle,
      'progress': value.progress,
      'updatedAt': value.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Toàn bộ lịch sử đọc, mới đọc gần nhất trước — tab "Lịch sử" (A3.7).
  Future<List<HistoryEntry>> history() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'reading_history',
      orderBy: 'updatedAt DESC',
    );
    return rows.map(HistoryEntry.fromJson).toList(growable: false);
  }

  /// Xoá một dòng lịch sử (nút "×" ở tab Lịch sử).
  Future<void> deleteHistory(int storyId) async {
    final Database db = await _db;
    await db.delete(
      'reading_history',
      where: 'storyId = ?',
      whereArgs: <Object>[storyId],
    );
  }
}
