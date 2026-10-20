/// Model kết quả "Tìm & thay thế" theo truyện — khớp backend
/// (`POST /stories/{id}/replace`, `/replace/undo`, `GET /stories/{id}/glossary`).
library;

/// Quy tắc đã lưu của truyện (A → B) — bảng `StoryGlossary`.
class GlossaryRule {
  const GlossaryRule({
    required this.id,
    required this.findText,
    required this.replaceText,
    required this.matchCase,
    required this.wholeWord,
    required this.applyToFuture,
    required this.createdAt,
  });

  final int id;
  final String findText;
  final String replaceText;
  final bool matchCase;
  final bool wholeWord;
  final bool applyToFuture;
  final DateTime createdAt;

  factory GlossaryRule.fromJson(Map<String, dynamic> json) => GlossaryRule(
    id: (json['id'] as num?)?.toInt() ?? 0,
    findText: json['findText'] as String? ?? '',
    replaceText: json['replaceText'] as String? ?? '',
    matchCase: json['matchCase'] as bool? ?? false,
    wholeWord: json['wholeWord'] as bool? ?? false,
    applyToFuture: json['applyToFuture'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// Một chương bị ảnh hưởng: `{ chapterId, chapterNo, matches }`.
class ReplaceChapterHit {
  const ReplaceChapterHit({
    required this.chapterId,
    required this.chapterNo,
    required this.matches,
  });

  final int chapterId;
  final int chapterNo;
  final int matches;

  factory ReplaceChapterHit.fromJson(Map<String, dynamic> json) =>
      ReplaceChapterHit(
        chapterId: (json['chapterId'] as num?)?.toInt() ?? 0,
        chapterNo: (json['chapterNo'] as num?)?.toInt() ?? 0,
        matches: (json['matches'] as num?)?.toInt() ?? 0,
      );
}

/// Phản hồi `POST /stories/{id}/replace`:
/// `dryRun=true` → chỉ đếm; `dryRun=false` → kèm `batchId` để hoàn tác.
class ReplaceResult {
  const ReplaceResult({
    required this.dryRun,
    required this.totalMatches,
    required this.chapters,
    this.batchId,
    this.chaptersChanged,
  });

  final bool dryRun;
  final int totalMatches;
  final List<ReplaceChapterHit> chapters;

  /// Chỉ có khi thay thật — dùng cho `POST /replace/undo`.
  final String? batchId;
  final int? chaptersChanged;

  factory ReplaceResult.fromJson(Map<String, dynamic> json) => ReplaceResult(
    dryRun: json['dryRun'] as bool? ?? false,
    totalMatches: (json['totalMatches'] as num?)?.toInt() ?? 0,
    chapters: (json['chapters'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ReplaceChapterHit.fromJson)
        .toList(),
    batchId: json['batchId'] as String?,
    chaptersChanged: (json['chaptersChanged'] as num?)?.toInt(),
  );
}

/// Phản hồi `POST /stories/{id}/replace/undo` — số chương đã/bị bỏ qua.
class UndoResult {
  const UndoResult({
    required this.message,
    required this.restored,
    required this.skipped,
  });

  final String message;
  final int restored;
  final int skipped;

  factory UndoResult.fromJson(Map<String, dynamic> json) => UndoResult(
    message: json['message'] as String? ?? '',
    restored: (json['restored'] as num?)?.toInt() ?? 0,
    skipped: (json['skipped'] as num?)?.toInt() ?? 0,
  );
}
