import 'package:flutter/material.dart';

import '../models/moderation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton.dart';

/// Màn đọc chương **dành cho Admin** khi kiểm duyệt: nội dung đã resolve
/// marker (không dấu `{}`), chuyển sang bản gốc bằng nút nếu backend có trả.
///
/// Màn đọc đơn giản — KHÔNG ghi tiến độ đọc, không chỉnh sửa.
class ModerationChapterScreen extends StatefulWidget {
  const ModerationChapterScreen({
    super.key,
    required this.chapterId,
    this.api,
  });

  final int chapterId;

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  @override
  State<ModerationChapterScreen> createState() => _ModerationChapterScreenState();
}

class _ModerationChapterScreenState extends State<ModerationChapterScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  AdminChapter? _chapter;
  Object? _error;
  bool _showOriginal = false; // xem bản gốc (nếu có)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _chapter = null;
      _error = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final AdminChapter chapter = await _api.fetchAdminChapter(
        widget.chapterId,
      );
      if (!mounted) return;
      setState(() => _chapter = chapter);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_chapter?.title ?? 'Đọc chương'),
        actions: <Widget>[
          // Bản gốc chỉ hiện khi backend trả OriginalContent.
          if ((_chapter?.originalContent ?? '').isNotEmpty)
            TextButton(
              onPressed: () =>
                  setState(() => _showOriginal = !_showOriginal),
              child: Text(_showOriginal ? 'Bản dịch' : 'Bản gốc'),
            ),
        ],
      ),
      body: _body(theme),
    );
  }

  Widget _body(ThemeData theme) {
    if (_error != null) {
      return ErrorState(
        message: _error is ApiException
            ? (_error as ApiException).message
            : 'Không tải được nội dung chương.',
        onRetry: _load,
      );
    }

    final AdminChapter? chapter = _chapter;
    if (chapter == null) return const ListSkeleton(rows: 4);

    final String text = _showOriginal
        ? (chapter.originalContent ?? chapter.content)
        : chapter.content;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: <Widget>[
          Text(chapter.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(
            text.isEmpty ? '(Chương trống)' : text,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: AppFonts.reading,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
