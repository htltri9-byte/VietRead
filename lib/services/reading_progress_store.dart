import '../models/reading_progress.dart';
import 'db_helper.dart';
import 'prefs_service.dart';

/// Kho tiến độ đọc: giữ 1 bản trong RAM (thẻ "Đọc tiếp") và lưu bền vững
/// bằng `shared_preferences` — **lưu tiến độ đọc thật** theo yêu cầu Bước 5 (A3.5).
///
/// Bước 7: mỗi lần lưu còn ghi thêm 1 dòng vào bảng `reading_history` (SQLite, A4)
/// để tab **Lịch sử** ở Tủ sách hiển thị được — lỗi SQLite không được phá luồng đọc.
class ReadingProgressStore {
  ReadingProgressStore._();

  static final ReadingProgressStore instance = ReadingProgressStore._();

  ReadingProgress? _current;

  /// Truyện đọc gần nhất (dùng cho thẻ "Đọc tiếp" ở trang Khám phá).
  ReadingProgress? get current => _current;

  /// Nạp tiến độ gần nhất — gọi một lần khi app mở trang Khám phá.
  Future<void> loadLatest() async {
    _current = await PrefsService.instance.latestProgress();
  }

  /// Lưu tiến độ: gọi khi mở chương, đổi chương hoặc cuộn tới chỗ mới.
  Future<void> save(ReadingProgress value) async {
    _current = value;
    await PrefsService.instance.saveProgress(value);
    try {
      await DbHelper.instance.recordHistory(value); // reading_history (A4)
    } catch (_) {
      // SQLite không mở được (thiết bị không hỗ trợ) → vẫn giữ tiến độ ở prefs.
    }
  }

  /// Tiến độ của một truyện (nút "Đọc tiếp" trong chi tiết truyện).
  Future<ReadingProgress?> of(int storyId) =>
      PrefsService.instance.progressOf(storyId);

  /// Xoá tiến độ một truyện.
  Future<void> clear(int storyId) async {
    if (_current?.story.id == storyId) {
      _current = null;
    }
    await PrefsService.instance.clearProgress(storyId);
  }
}
