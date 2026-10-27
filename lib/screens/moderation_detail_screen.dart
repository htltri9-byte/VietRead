import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../models/moderation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_spacing.dart';
import '../widgets/error_state.dart';
import '../widgets/moderation_chip.dart';
import '../widgets/skeleton.dart';
import 'moderation_chapter_screen.dart';

/// Màn **Chi tiết kiểm duyệt** (Admin): thông tin truyện + danh sách chương
/// (bấm để đọc nội dung dù truyện chưa công khai), nút Duyệt / Từ chối.
///
/// Truyện `approved` đang **cần xem lại** → chỉ liệt kê chương thay đổi sau
/// lần duyệt trước (`updatedAt > reviewedAt`); chương đã duyệt rồi không hiện
/// lại. Trạng thái khác hiển thị toàn bộ chương như cũ.
///
/// Quay về danh sách với kết quả `true` khi vừa duyệt/từ chối → màn danh
/// sách nạp lại.
class ModerationDetailScreen extends StatefulWidget {
  const ModerationDetailScreen({super.key, required this.storyId, this.api});

  final int storyId;

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  @override
  State<ModerationDetailScreen> createState() => _ModerationDetailScreenState();
}

class _ModerationDetailScreenState extends State<ModerationDetailScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  AdminStoryDetail? _detail;
  Object? _error;
  bool _busy = false; // đang gọi approve/reject → khóa nút

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _detail = null;
      _error = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final AdminStoryDetail detail = await _api.fetchAdminStory(widget.storyId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  String _errorMessage(Object error) =>
      error is ApiException ? error.message : 'Không tải được thông tin truyện.';

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ------------------------- Duyệt / Từ chối -------------------------

  /// Xác nhận rồi duyệt (pending hoặc approved+cần xem lại → approved).
  Future<void> _approve(AdminStory story) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Duyệt truyện?'),
        content: Text(
          '«${story.title}» sẽ xuất hiện công khai trên app cho mọi người đọc.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Duyệt'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      _api.setToken(AuthService.instance.session?.token);
      await _api.approveAdminStory(widget.storyId);
      if (!mounted) return;
      _showMessage('Đã duyệt "${story.title}".');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(_errorMessage(e)); // 409: admin khác đã xử lý trước
      _load(); // nạp lại cho đúng trạng thái mới
    }
  }

  /// Hộp thoại nhập lý do (bắt buộc 5–1000 ký tự) rồi từ chối/gỡ truyện.
  Future<void> _reject(AdminStory story) async {
    final TextEditingController reason = TextEditingController();
    String? errorText;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setDialog) {
          return AlertDialog(
            title: const Text('Từ chối / Gỡ truyện'),
            content: TextField(
              controller: reason,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'Lý do (5–1000 ký tự)',
                hintText: 'Nêu rõ lý do để tác giả biết và sửa...',
                errorText: errorText,
              ),
              onChanged: (String value) {
                if (errorText == null) return;
                setDialog(() {
                  errorText = _validateReason(value);
                });
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Huỷ'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () {
                  final String? err = _validateReason(reason.text);
                  if (err != null) {
                    setDialog(() => errorText = err);
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('Từ chối'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true || !mounted) return;
    final String text = reason.text.trim();

    setState(() => _busy = true);
    try {
      _api.setToken(AuthService.instance.session?.token);
      await _api.rejectAdminStory(widget.storyId, reason: text);
      if (!mounted) return;
      _showMessage('Đã từ chối "${story.title}".');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(_errorMessage(e));
      _load();
    }
  }

  /// Lý do bắt buộc 5–1000 ký tự (đã trim).
  static String? _validateReason(String raw) {
    final String text = raw.trim();
    if (text.length < 5) return 'Lý do phải có ít nhất 5 ký tự.';
    if (text.length > 1000) return 'Lý do tối đa 1000 ký tự.';
    return null;
  }

  // ------------------------- Giao diện -------------------------

  /// Duyệt chỉ hợp lệ khi pending (hoặc approved đang cần xem lại).
  bool get _canApprove {
    final AdminStoryDetail? d = _detail;
    if (d == null) return false;
    final String s = d.story.moderationStatus;
    return s == 'pending' || (s == 'approved' && d.story.needsRecheck);
  }

  /// Từ chối / gỡ: truyện chờ duyệt hoặc đã duyệt.
  bool get _canReject {
    final String? s = _detail?.story.moderationStatus;
    return s == 'pending' || s == 'approved';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kiểm duyệt')),
        body: ErrorState(message: _errorMessage(_error!), onRetry: _load),
      );
    }

    final AdminStoryDetail? detail = _detail;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kiểm duyệt')),
        body: const ListSkeleton(rows: 4),
      );
    }

    final AdminStory story = detail.story;

    // Approved + cần xem lại + có mốc duyệt → chỉ hiện chương đổi sau mốc đó.
    final bool changedOnly = story.moderationStatus == 'approved' &&
        story.needsRecheck &&
        story.reviewedAt != null;
    final DateTime? reviewedAt = story.reviewedAt;
    final List<ChapterSummary> chapters = !changedOnly
        ? detail.chapters
        : detail.chapters
            .where((ChapterSummary c) => c.updatedAt.isAfter(reviewedAt!))
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Kiểm duyệt')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: <Widget>[
            // ---------- Thông tin truyện ----------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(story.title, style: theme.textTheme.titleLarge),
                        ),
                        const SizedBox(width: 8),
                        ModerationChip(
                          status: story.moderationStatus,
                          needsRecheck: story.needsRecheck,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      <String>[
                        detail.uploaderName.isEmpty
                            ? story.author
                            : detail.uploaderName,
                        story.chapterLabel,
                        if (detail.genres.isNotEmpty) detail.genres.join(', '),
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (detail.originalAuthor != null &&
                        detail.originalAuthor!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        'Tác giả gốc: ${detail.originalAuthor}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      detail.description?.trim().isNotEmpty == true
                          ? detail.description!.trim()
                          : 'Chưa có mô tả.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (story.submittedAt != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        'Gửi duyệt: ${_formatDateTime(story.submittedAt!)}'
                        '${story.reviewedAt != null ? ' · Xem xét: ${_formatDateTime(story.reviewedAt!)}' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (story.moderationStatus == 'rejected' &&
                        (story.rejectReason ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Lý do từ chối: ${story.rejectReason}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ---------- Kết quả quét tự động (ẩn khi chưa có) ----------
            if (detail.hasScanResult) ...<Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Kết quả quét tự động', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        _scanLabel(detail.story.scanStatus),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ---------- Danh sách chương ----------
            Text(
              changedOnly
                  ? 'Chương thay đổi (${chapters.length}/${detail.chapters.length})'
                  : 'Chương (${chapters.length})',
              style: theme.textTheme.titleMedium,
            ),
            if (changedOnly) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Chỉ hiển thị chương thay đổi sau lần duyệt trước.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (chapters.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    changedOnly
                        ? 'Không có chương nào thay đổi sau lần duyệt trước '
                              '(chương có thể đã bị xoá).'
                        : 'Truyện chưa có chương nào.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Card(
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < chapters.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              theme.colorScheme.primary.withValues(alpha: 0.08),
                          child: Text(
                            '${chapters[i].index}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        title: Text(
                          chapters[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openChapter(chapters[i].id),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 96), // chừa chỗ cho 2 nút dưới
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                // Đang duyệt/từ chối, hoặc trạng thái không cho phép → khóa.
                onPressed: (_busy || !_canApprove) ? null : () => _approve(story),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Duyệt'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: (_busy || !_canReject) ? null : () => _reject(story),
                icon: const Icon(Icons.block_rounded),
                label: const Text('Từ chối'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChapter(int chapterId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ModerationChapterScreen(api: _api, chapterId: chapterId),
      ),
    );
  }

  static String _scanLabel(String? status) => switch ((status ?? '').trim()) {
    'clean' => 'Nội dung sạch — không phát hiện vấn đề.',
    'flagged' => 'Có dấu hiệu cần xem xét — hãy đọc kỹ trước khi duyệt.',
    'error' => 'Quét thất bại — nên duyệt thủ công.',
    _ => status ?? '',
  };

  static String _formatDateTime(DateTime value) {
    final DateTime t = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}/${t.year}';
  }
}
