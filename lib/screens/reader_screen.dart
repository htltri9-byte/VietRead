import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/db_helper.dart';
import '../services/prefs_service.dart';
import '../services/reading_progress_store.dart';
import '../theme/app_theme.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton.dart';

/// Màn **đọc truyện** (A3.5): nội dung chương, chuyển chương trước/sau,
/// tuỳ chỉnh cỡ chữ – font – nền (sáng/tối/sepia) – giãn dòng,
/// tự lưu tiến độ đọc và hiển thị tiến độ %.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.story,
    required this.initialIndex,
    this.chapters,
    this.api,
    this.offline = false,
  });

  final Story story;

  /// Chương bắt đầu đọc (bắt đầu từ 1).
  final int initialIndex;

  /// Danh sách chương đã tải sẵn (nếu màn chi tiết truyện truyền vào);
  /// `null` thì màn đọc tự tải.
  final List<ChapterSummary>? chapters;

  final ApiService? api;

  /// `true` = đọc hoàn toàn từ SQLite (tab "Đã tải" ở Tủ sách, A3.7);
  /// `false` = lấy từ API nhưng tự chuyển sang bản đã tải khi mất mạng.
  final bool offline;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const int _pageSize = 50;

  late final ApiService _api = widget.api ?? ApiService();
  final ScrollController _scrollController = ScrollController();

  late final List<ChapterSummary> _chapters = List<ChapterSummary>.of(
    widget.chapters ?? const <ChapterSummary>[],
  );
  late int _index = widget.initialIndex < 1 ? 1 : widget.initialIndex;

  Chapter? _chapter;
  bool _loading = true;
  Object? _error;
  bool _loadingList = false;

  ReaderSettings _settings = const ReaderSettings();
  double _progress = 0; // vị trí đọc trong chương (0.0–1.0)
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Tải dữ liệu
  // ------------------------------------------------------------------

  Future<void> _bootstrap() async {
    final ReaderSettings saved = await PrefsService.instance.loadSettings();
    if (!mounted) return;
    setState(() => _settings = saved);
    if (widget.offline) {
      // Dựng danh sách chương từ SQLite để chuyển chương trước/sau được.
      try {
        _chapters.addAll(
          await DbHelper.instance.downloadedChapterSummaries(widget.story.id),
        );
      } catch (_) {
        // SQLite không mở được → _loadChapter sẽ hiện lỗi thân thiện.
      }
    }
    await _loadChapter();
  }

  /// Tìm tóm tắt chương theo số thứ tự — hoạt động cả với khoảng tải
  /// không bắt đầu từ 1 (vd: chỉ tải chương 5–10).
  ChapterSummary? _summaryAt(int index) {
    for (final ChapterSummary summary in _chapters) {
      if (summary.index == index) return summary;
    }
    return null;
  }

  /// Đọc nội dung chương từ SQLite — dùng khi ngoại tuyến (A3.7/A3.8).
  /// SQLite không sẵn sàng → `null` (coi như chưa tải chương này).
  Future<Chapter?> _loadLocalChapter() async {
    try {
      return await DbHelper.instance.downloadedChapter(widget.story.id, _index);
    } catch (_) {
      return null; // SQLite không sẵn sàng → coi như chưa tải chương này.
    }
  }

  /// Tải thêm trang chương cho tới khi có chương `index`.
  Future<void> _ensureIndex(int index) async {
    if (widget.offline) return; // danh sách chương lấy từ SQLite khi mở
    while (_chapters.length < index && !_loadingList) {
      _loadingList = true;
      final int page = (_chapters.length ~/ _pageSize) + 1;
      final List<ChapterSummary> more = await _api.fetchChapters(
        widget.story.id,
        page: page,
        pageSize: _pageSize,
      );
      _loadingList = false;
      if (more.isEmpty) break; // hết chương
      _chapters.addAll(more);
    }
  }

  Future<void> _loadChapter() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Chapter? chapter;
      if (widget.offline) {
        // Đọc hoàn toàn từ bản đã tải trong SQLite (tab "Đã tải").
        chapter = await _loadLocalChapter();
        if (chapter == null) {
          throw ApiException('Chương $_index chưa được tải về máy.');
        }
      } else {
        try {
          await _ensureIndex(_index);
          if (_index > _chapters.length) {
            throw const ApiException('Chương này chưa tồn tại.');
          }
          final ChapterSummary summary = _chapters[_index - 1];
          chapter = await _api.fetchChapter(summary.id);
        } on ApiException {
          // Mất mạng giữa chừng → đọc tiếp bản đã tải trong SQLite (nếu có).
          chapter = await _loadLocalChapter();
          if (chapter == null) rethrow;
          if (_chapters.isEmpty) {
            try {
              _chapters.addAll(
                await DbHelper.instance.downloadedChapterSummaries(
                  widget.story.id,
                ),
              );
            } catch (_) {}
          }
          _showMessage('Mất mạng — đang đọc bản đã tải trên máy.');
        }
      }
      _chapter = chapter;

      // Lấy lại tiến độ để mở đúng chỗ đã đọc
      final ReadingProgress? saved = await ReadingProgressStore.instance.of(
        widget.story.id,
      );
      if (saved != null && saved.chapterIndex == _index) {
        _progress = saved.progress;
      } else {
        _progress = 0;
      }

      if (!mounted) return;
      setState(() => _loading = false);

      // Cuộn về chỗ đã đọc (sau khi layout xong)
      if (_progress > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final double max = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(max * _progress);
        });
      } else if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      await _saveProgress();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Chuyển chương (tự tải thêm danh sách nếu cần).
  Future<void> _goTo(int index) async {
    if (index < 1 || _loading) return;
    if (widget.offline) {
      // Ngoại tuyến: chỉ nhảy được tới chương đã tải về máy.
      if (_summaryAt(index) == null) {
        _showMessage('Chương $index chưa được tải về máy.');
        return;
      }
    } else {
      if (index > _chapters.length) {
        await _ensureIndex(index);
        if (index > _chapters.length) {
          _showMessage('Bạn đã đọc tới chương cuối cùng.');
          return;
        }
      }
    }
    setState(() => _index = index);
    await _loadChapter();
  }

  // ------------------------------------------------------------------
  // Tiến độ đọc
  // ------------------------------------------------------------------

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients || _loading) return;
    final double max = _scrollController.position.maxScrollExtent;
    final double value = max > 0
        ? (_scrollController.offset / max).clamp(0.0, 1.0)
        : 1.0;
    final bool changed = (value - _progress).abs() > 0.01;
    _progress = value;
    if (changed) setState(() {}); // cập nhật % trên thanh dưới
    _scheduleSave();
  }

  /// Trì hoãn việc ghi tiến độ cho tới khi người đọc ngừng cuộn.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveProgress);
  }

  Future<void> _saveProgress() async {
    if (_index < 1) return;
    final ChapterSummary? summary = _summaryAt(_index);
    final String? rawTitle = summary?.title ?? _chapter?.title;
    if (rawTitle == null) return; // chưa tải được chương nào
    await ReadingProgressStore.instance.save(
      ReadingProgress(
        story: widget.story,
        chapterIndex: _index,
        chapterTitle: _subtitleOf(rawTitle),
        progress: _progress,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// "Chương 12: Kiếm Ngưng Tường" → "Kiếm Ngưng Tường" (cho thẻ Đọc tiếp).
  static String _subtitleOf(String title) {
    final int colon = title.indexOf(':');
    if (colon >= 0 && colon + 1 < title.length) {
      return title.substring(colon + 1).trim();
    }
    return title;
  }

  Future<void> _goBack() async {
    _saveTimer?.cancel();
    await _saveProgress();
    if (mounted) Navigator.of(context).maybePop();
  }

  // ------------------------------------------------------------------
  // Cài đặt đọc
  // ------------------------------------------------------------------

  Future<void> _applySettings(ReaderSettings value) async {
    setState(() => _settings = value);
    await PrefsService.instance.saveSettings(value);
  }

  Future<void> _openSettings() async {
    ReaderSettings draft = _settings;
    final ThemeData theme = Theme.of(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        const List<(String, String)> backgrounds = <(String, String)>[
          ('Sáng', ReaderSettings.bgLight),
          ('Tối', ReaderSettings.bgDark),
          ('Sepia', ReaderSettings.bgSepia),
        ];

        return SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              void change(ReaderSettings value) {
                setSheetState(() => draft = value);
                _applySettings(value);
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cài đặt đọc', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Text('Nền', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final (String label, String value) in backgrounds)
                        ChoiceChip(
                          label: Text(label),
                          selected: draft.background == value,
                          onSelected: (_) =>
                              change(draft.copyWith(background: value)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Font chữ', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      ChoiceChip(
                        label: const Text('Serif (Noto Serif)'),
                        selected: draft.useSerif,
                        onSelected: (_) =>
                            change(draft.copyWith(useSerif: true)),
                      ),
                      ChoiceChip(
                        label: const Text('Sans (Be Vietnam Pro)'),
                        selected: !draft.useSerif,
                        onSelected: (_) =>
                            change(draft.copyWith(useSerif: false)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Cỡ chữ: ${draft.fontSize.round()}',
                    style: theme.textTheme.labelLarge,
                  ),
                  Slider(
                    value: draft.fontSize,
                    min: 14,
                    max: 28,
                    divisions: 14,
                    label: draft.fontSize.round().toString(),
                    onChanged: (double v) =>
                        change(draft.copyWith(fontSize: v)),
                  ),
                  Text(
                    'Giãn dòng: ${draft.lineHeight.toStringAsFixed(1)}',
                    style: theme.textTheme.labelLarge,
                  ),
                  Slider(
                    value: draft.lineHeight,
                    min: 1.3,
                    max: 2.1,
                    divisions: 8,
                    label: draft.lineHeight.toStringAsFixed(1),
                    onChanged: (double v) =>
                        change(draft.copyWith(lineHeight: v)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Xong'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------
  // Giao diện
  // ------------------------------------------------------------------

  Color get _background {
    switch (_settings.background) {
      case ReaderSettings.bgDark:
        return AppColors.night;
      case ReaderSettings.bgSepia:
        return AppColors.sepia;
      default:
        return AppColors.paper;
    }
  }

  Color get _ink {
    switch (_settings.background) {
      case ReaderSettings.bgDark:
        return AppColors.inkNight;
      case ReaderSettings.bgSepia:
        return AppColors.sepiaInk;
      default:
        return AppColors.ink;
    }
  }

  Color get _mutedInk => _ink.withValues(alpha: 0.65);

  String get _currentTitle {
    final ChapterSummary? summary = _summaryAt(_index);
    if (summary != null) return summary.title;
    if (_chapter != null) return _chapter!.title;
    return widget.story.title;
  }

  TextStyle _contentStyle(ThemeData theme) =>
      (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontFamily: _settings.useSerif ? AppFonts.reading : AppFonts.ui,
        fontSize: _settings.fontSize,
        height: _settings.lineHeight,
        color: _ink,
      );

  String _errorMessage() {
    if (_error is ApiException) return (_error as ApiException).message;
    return 'Không tải được nội dung chương. Vui lòng thử lại.';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Quay lại',
        ),
        title: Text(
          _currentTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(color: _ink),
        ),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.text_fields_rounded),
            tooltip: 'Cài đặt đọc',
          ),
        ],
      ),
      body: _body(theme),
      bottomNavigationBar: _bottomBar(theme),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SkeletonBox(width: 220, height: 18, radius: 9),
            const SizedBox(height: 12),
            Text(
              'Đang tải chương...',
              style: theme.textTheme.bodyMedium?.copyWith(color: _mutedInk),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      // Đổi màu chữ theo nền đọc để lỗi vẫn đọc được
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: 60),
        child: Theme(
          data: theme.copyWith(
            textTheme: theme.textTheme.copyWith(
              titleLarge: theme.textTheme.titleLarge?.copyWith(color: _ink),
              titleMedium: theme.textTheme.titleMedium?.copyWith(color: _ink),
              bodyLarge: theme.textTheme.bodyLarge?.copyWith(color: _ink),
              bodyMedium: theme.textTheme.bodyMedium?.copyWith(color: _ink),
              bodySmall: theme.textTheme.bodySmall?.copyWith(color: _ink),
            ),
            colorScheme: theme.colorScheme.copyWith(
              onSurface: _ink,
              onSurfaceVariant: _mutedInk,
            ),
          ),
          child: ErrorState(message: _errorMessage(), onRetry: _loadChapter),
        ),
      );
    }

    final Chapter chapter = _chapter!;
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapter.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: _settings.useSerif ? AppFonts.reading : AppFonts.ui,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
          Text(chapter.content, style: _contentStyle(theme)),
          const SizedBox(height: 28),
          Center(
            child: Text(
              '— Hết chương ${chapter.index} —',
              style: theme.textTheme.labelMedium?.copyWith(color: _mutedInk),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(ThemeData theme) {
    final bool canPrev = _index > 1;
    final String percent = '${(_progress * 100).round()}%';

    return Container(
      decoration: BoxDecoration(
        color: _background,
        border: Border(
          top: BorderSide(color: _mutedInk.withValues(alpha: 0.3)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        6 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: canPrev ? () => _goTo(_index - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: _ink,
            disabledColor: _mutedInk,
            tooltip: 'Chương trước',
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Chương $_index',
                  style: theme.textTheme.labelMedium?.copyWith(color: _ink),
                ),
                const SizedBox(height: 2),
                Text(
                  percent,
                  style: theme.textTheme.labelSmall?.copyWith(color: _mutedInk),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _goTo(_index + 1),
            icon: const Icon(Icons.chevron_right_rounded),
            color: _ink,
            disabledColor: _mutedInk,
            tooltip: 'Chương sau',
          ),
        ],
      ),
    );
  }
}
