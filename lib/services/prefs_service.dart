import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reading_progress.dart';

/// Cài đặt màn hình đọc — lưu trong `shared_preferences` (Phần A1).
class ReaderSettings {
  const ReaderSettings({
    this.fontSize = 18,
    this.useSerif = true,
    this.background = ReaderSettings.bgLight,
    this.lineHeight = 1.7,
  });

  /// Tên các nền đọc (A3.5: sáng / tối / sepia).
  static const String bgLight = 'light';
  static const String bgDark = 'dark';
  static const String bgSepia = 'sepia';

  /// Cỡ chữ (14–28).
  final double fontSize;

  /// `true` = Noto Serif (mặc định), `false` = Be Vietnam Pro.
  final bool useSerif;

  /// `light` | `dark` | `sepia`.
  final String background;

  /// Giãn dòng (1.3–2.1).
  final double lineHeight;

  String get backgroundLabel {
    switch (background) {
      case bgDark:
        return 'Tối';
      case bgSepia:
        return 'Sepia';
      default:
        return 'Sáng';
    }
  }

  String get fontLabel =>
      useSerif ? 'Serif (Noto Serif)' : 'Sans (Be Vietnam Pro)';

  ReaderSettings copyWith({
    double? fontSize,
    bool? useSerif,
    String? background,
    double? lineHeight,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    useSerif: useSerif ?? this.useSerif,
    background: background ?? this.background,
    lineHeight: lineHeight ?? this.lineHeight,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fontSize': fontSize,
    'useSerif': useSerif,
    'background': background,
    'lineHeight': lineHeight,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) => ReaderSettings(
    fontSize: ((json['fontSize'] as num?)?.toDouble() ?? 18).clamp(14, 28),
    useSerif: json['useSerif'] as bool? ?? true,
    background: json['background'] as String? ?? ReaderSettings.bgLight,
    lineHeight: ((json['lineHeight'] as num?)?.toDouble() ?? 1.7).clamp(
      1.3,
      2.1,
    ),
  );
}

/// Đọc/ghi dữ liệu nhỏ trên máy: cài đặt đọc + tiến độ đọc (shared_preferences).
class PrefsService {
  PrefsService._();

  static final PrefsService instance = PrefsService._();

  static const String _kLastStoryId = 'last_read_story_id';
  static const String _kFontSize = 'reader_font_size';
  static const String _kFontSerif = 'reader_font_serif';
  static const String _kBackground = 'reader_background';
  static const String _kLineHeight = 'reader_line_height';
  static const String _kProgressPrefix = 'reading_progress_';

  /// Key lưu tiến độ của một truyện: `reading_progress_<storyId>`.
  static String progressKey(int storyId) => '$_kProgressPrefix$storyId';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ------------------------- Cài đặt đọc -------------------------

  Future<ReaderSettings> loadSettings() async {
    final SharedPreferences sp = await _prefs;
    return ReaderSettings(
      fontSize: (sp.getDouble(_kFontSize) ?? 18).clamp(14, 28),
      useSerif: sp.getBool(_kFontSerif) ?? true,
      background: sp.getString(_kBackground) ?? ReaderSettings.bgLight,
      lineHeight: (sp.getDouble(_kLineHeight) ?? 1.7).clamp(1.3, 2.1),
    );
  }

  Future<void> saveSettings(ReaderSettings value) async {
    final SharedPreferences sp = await _prefs;
    await sp.setDouble(_kFontSize, value.fontSize);
    await sp.setBool(_kFontSerif, value.useSerif);
    await sp.setString(_kBackground, value.background);
    await sp.setDouble(_kLineHeight, value.lineHeight);
  }

  // ------------------------- Tiến độ đọc -------------------------

  Future<void> saveProgress(ReadingProgress value) async {
    final SharedPreferences sp = await _prefs;
    await sp.setString(progressKey(value.story.id), jsonEncode(value.toJson()));
    await sp.setInt(_kLastStoryId, value.story.id); // truyện đọc gần nhất
  }

  /// Tiến độ của một truyện (dùng cho nút "Đọc tiếp" trong chi tiết truyện).
  Future<ReadingProgress?> progressOf(int storyId) async {
    final SharedPreferences sp = await _prefs;
    final String? raw = sp.getString(progressKey(storyId));
    if (raw == null) return null;
    try {
      return ReadingProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // dữ liệu hỏng → coi như chưa đọc
    }
  }

  /// Tiến độ gần nhất (thẻ "Đọc tiếp" ở trang Khám phá).
  Future<ReadingProgress?> latestProgress() async {
    final SharedPreferences sp = await _prefs;
    final int? storyId = sp.getInt(_kLastStoryId);
    if (storyId == null) return null;
    return progressOf(storyId);
  }

  Future<void> clearProgress(int storyId) async {
    final SharedPreferences sp = await _prefs;
    await sp.remove(progressKey(storyId));
    if (sp.getInt(_kLastStoryId) == storyId) {
      await sp.remove(_kLastStoryId);
    }
  }
}
