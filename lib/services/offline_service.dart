import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/chapter.dart';
import '../models/downloaded_story.dart';
import '../models/story.dart';
import 'api_service.dart';
import 'db_helper.dart';

/// Kéo truyện về SQLite để **đọc khi mất mạng** (A3.8):
/// tải toàn bộ hoặc một khoảng chương, có tiến trình, xoá để giải phóng bộ nhớ.
class OfflineService {
  OfflineService({ApiService? api, DbHelper? db})
    : _api = api ?? ApiService(),
      _db = db ?? DbHelper.instance;

  /// Phiên duy nhất của app (test tạo bản riêng với mock api + db riêng).
  static OfflineService instance = OfflineService();

  final ApiService _api;
  final DbHelper _db;

  /// Các truyện đã tải — tab "Đã tải" (A3.7).
  Future<List<DownloadedStory>> downloadedStories() => _db.downloadedStories();

  Future<bool> isDownloaded(int storyId) => _db.isDownloaded(storyId);

  Future<int> chapterCount(int storyId) => _db.downloadedChapterCount(storyId);

  /// Danh sách chương đã tải (tăng dần) — dựng danh sách khi đọc offline.
  Future<List<ChapterSummary>> downloadedChapters(int storyId) =>
      _db.downloadedChapterSummaries(storyId);

  /// Xoá một truyện + chương đã tải để giải phóng bộ nhớ (A3.8).
  Future<void> removeStory(int storyId) => _db.deleteDownloadedStory(storyId);

  /// Tải chương [from]..[to] (mặc định toàn bộ) của [story] vào SQLite.
  ///
  /// - [onProgress] gọi sau mỗi chương: `(đã tải, tổng số)` để hiện tiến trình.
  /// - [isCancelled] trả `true` thì dừng giữa chừng (nút "Huỷ").
  /// - Trả về số chương đã tải xong.
  Future<int> downloadStory(
    Story story, {
    int from = 1,
    int? to,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // 1) Lấy danh sách toàn bộ chương (phân trang 50 chương/lần).
    final List<ChapterSummary> all = <ChapterSummary>[];
    int page = 1;
    while (true) {
      final List<ChapterSummary> more = await _api.fetchChapters(
        story.id,
        page: page,
        pageSize: 50,
      );
      all.addAll(more);
      if (more.length < 50) break;
      page++;
    }
    if (all.isEmpty) {
      throw const ApiException('Truyện này chưa có chương nào để tải.');
    }

    // 2) Cắt khoảng chương hợp lệ.
    final int start = from.clamp(1, all.length);
    final int end = (to ?? all.length).clamp(start, all.length);
    final List<ChapterSummary> range = all.sublist(start - 1, end);

    // 3) Ghi thông tin truyện ngay để tab "Đã tải" thấy được dù tải dở.
    await _db.upsertDownloadedStory(
      DownloadedStory(
        id: story.id,
        title: story.title,
        author: story.author,
        coverPath: await _downloadCover(story),
        description: story.description,
      ),
    );

    // 4) Tải nội dung từng chương (tuần tự để tiến trình phản ánh đúng).
    final List<Chapter> downloaded = <Chapter>[];
    onProgress?.call(0, range.length);
    for (final ChapterSummary summary in range) {
      if (isCancelled?.call() == true) break;
      final Chapter chapter = await _api.fetchChapter(summary.id);
      downloaded.add(chapter);
      onProgress?.call(downloaded.length, range.length);
    }

    // 5) Ghi vào SQLite một lần cho gọn (giữ chương đã tải ngoài khoảng này).
    if (downloaded.isNotEmpty) {
      await _db.insertDownloadedChapters(story.id, downloaded);
    }
    return downloaded.length;
  }

  /// Tải ảnh bìa về thư mục documents để có ảnh khi ngoại tuyến.
  /// Lỗi mạng / không lưu được → trả `null`, vẫn tải chữ bình thường.
  Future<String?> _downloadCover(Story story) async {
    final String? url = story.coverUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final http.Response res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final Directory dir = await getApplicationDocumentsDirectory();
      final Directory covers = Directory(p.join(dir.path, 'covers'));
      await covers.create(recursive: true);
      final File file = File(p.join(covers.path, '${story.id}.img'));
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null; // Ảnh bìa chỉ là phụ kiện — không chặn việc tải chữ.
    }
  }
}
