import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../models/comment.dart';
import '../models/reading_progress.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/offline_service.dart';
import '../services/reading_progress_store.dart';
import '../theme/app_theme.dart';
import '../widgets/chip_genre.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton.dart';
import '../widgets/story_card.dart';
import 'auth_screen.dart';
import 'reader_screen.dart';

/// Màn **chi tiết truyện** (A3.4): bìa, tên, tác giả, thể loại, mô tả, điểm,
/// trạng thái, danh sách chương (phân trang), nút Đọc/Đọc tiếp, Theo dõi,
/// Tải offline và tab Bình luận.
class StoryDetailScreen extends StatefulWidget {
  const StoryDetailScreen({super.key, required this.story, this.api});

  final Story story;

  /// Tiêm nguồn dữ liệu (test dùng mock không ảnh bìa).
  final ApiService? api;

  @override
  State<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends State<StoryDetailScreen> {
  static const int _pageSize = 50;

  late final ApiService _api = widget.api ?? ApiService();

  final List<ChapterSummary> _chapters = [];
  bool _loadingChapters = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _chapterError;
  ReadingProgress? _progress;
  bool _descriptionExpanded = false;
  int _tab = 0; // 0 = chương, 1 = bình luận

  // Theo dõi (Bước 7 — API /follows)
  bool _following = false;
  bool _followBusy = false;

  // Tải offline (Bước 7 — A3.8)
  bool _downloaded = false;
  int _downloadedCount = 0;

  // Nhập khoảng chương (thuộc State để không dispose khi dialog đóng
  // khi animation còn đang chạy — xem _showDownloadOptions).
  TextEditingController? _rangeFrom;
  TextEditingController? _rangeTo;

  // Bình luận (Bước 8 — A3.6: xem / gửi / xoá của mình)
  final TextEditingController _commentInput = TextEditingController();
  final List<Comment> _comments = <Comment>[];
  bool _loadingComments = false;
  bool _commentsLoaded = false;
  Object? _commentsError;
  bool _sendingComment = false;

  @override
  void dispose() {
    _rangeFrom?.dispose();
    _rangeTo?.dispose();
    _commentInput.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadChapters();
    _loadProgress();
    _loadFollowStatus();
    _checkDownloaded();
  }

  /// Tải trang chương đầu tiên.
  Future<void> _loadChapters() async {
    setState(() {
      _loadingChapters = true;
      _chapterError = null;
    });
    try {
      final List<ChapterSummary> first = await _api.fetchChapters(
        widget.story.id,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _chapters
          ..clear()
          ..addAll(first);
        _hasMore = first.length == _pageSize;
        _loadingChapters = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chapterError = e;
        _loadingChapters = false;
      });
    }
  }

  /// Tải thêm trang chương.
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final int page = (_chapters.length ~/ _pageSize) + 1;
      final List<ChapterSummary> more = await _api.fetchChapters(
        widget.story.id,
        page: page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _chapters.addAll(more);
        _hasMore = more.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chapterError = e;
        _loadingMore = false;
      });
    }
  }

  /// Nạp tiến độ đọc của truyện này để hiện nút "Đọc tiếp".
  Future<void> _loadProgress() async {
    final ReadingProgress? value = await ReadingProgressStore.instance.of(
      widget.story.id,
    );
    if (!mounted || value == null) return;
    setState(() => _progress = value);
  }

  /// Chương đọc tiếp theo: ưu tiên tiến độ đã lưu, không có thì chương 1.
  int get _startIndex {
    final int? saved = _progress?.chapterIndex;
    if (saved == null || saved < 1) return 1;
    return saved;
  }

  void _openReader({int? index}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          story: widget.story,
          initialIndex: index ?? _startIndex,
          chapters: List<ChapterSummary>.of(_chapters),
          api: _api,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------
  // Theo dõi (Bước 7 — POST/DELETE /follows, GET /me/follows)
  // ------------------------------------------------------------------

  /// Nạp trạng thái theo dõi của truyện này (chỉ khi đã đăng nhập).
  Future<void> _loadFollowStatus() async {
    if (!AuthService.instance.isLoggedIn) return;
    try {
      _api.setToken(AuthService.instance.session?.token);
      final List<Story> follows = await _api.fetchMyFollows();
      if (!mounted) return;
      setState(() {
        _following = follows.any((Story s) => s.id == widget.story.id);
      });
    } catch (_) {
      // Lỗi mạng → giữ trạng thái mặc định; bấm nút sẽ tự thử lại.
    }
  }

  /// Bật/tắt theo dõi — bắt buộc đăng nhập (A3.1).
  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    setState(() => _followBusy = true);
    try {
      _api.setToken(AuthService.instance.session?.token);
      if (_following) {
        await _api.unfollowStory(widget.story.id);
        _following = false;
        _showMessage('Đã bỏ theo dõi truyện.');
      } else {
        await _api.followStory(widget.story.id);
        _following = true;
        _showMessage('Đã theo dõi truyện.');
      }
    } on ApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  /// Chưa đăng nhập → màn đăng nhập; đăng nhập xong là theo dõi luôn.
  Future<void> _onFollow() async {
    if (!AuthService.instance.isLoggedIn) {
      final bool? ok = await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
      if (ok == true && mounted) await _toggleFollow();
      return;
    }
    await _toggleFollow();
  }

  // ------------------------------------------------------------------
  // Tải offline (Bước 7 — A3.8)
  // ------------------------------------------------------------------

  Future<void> _checkDownloaded() async {
    try {
      final bool value = await OfflineService.instance.isDownloaded(
        widget.story.id,
      );
      final int count = await OfflineService.instance.chapterCount(
        widget.story.id,
      );
      if (!mounted) return;
      setState(() {
        _downloaded = value;
        _downloadedCount = count;
      });
    } catch (_) {
      // SQLite chưa sẵn sàng → coi như chưa tải, bấm nút sẽ thử lại.
    }
  }

  /// Tổng số chương của truyện (ưu tiên số server trả về).
  int get _totalChapters {
    if (widget.story.chapterCount > 0) return widget.story.chapterCount;
    return _chapters.length;
  }

  void _onOffline() {
    if (_downloaded) {
      _showDownloadedMenu();
    } else {
      _showDownloadOptions();
    }
  }

  /// Dialog chọn phạm vi: tải toàn bộ hoặc một khoảng chương.
  Future<void> _showDownloadOptions() async {
    final int total = _totalChapters;
    // Controller thuộc về State này (không dispose ngay khi dialog đóng:
    // widget vẫn còn trong animation đóng → dùng controller đã dispose sẽ lỗi).
    _rangeFrom?.dispose();
    _rangeTo?.dispose();
    _rangeFrom = TextEditingController(text: '1');
    _rangeTo = TextEditingController(text: '$total');
    bool showRange = false;
    String? rangeError;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext dialogContext, StateSetter setDialogState) {
            Widget content;
            List<Widget> actions;
            if (!showRange) {
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Truyện có $total chương. Chọn phạm vi muốn lưu vào máy '
                    'để đọc được khi mất mạng.',
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _startDownload();
                      },
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text('Tải toàn bộ ($total chương)'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => setDialogState(() => showRange = true),
                      icon: const Icon(Icons.toc_rounded, size: 18),
                      label: const Text('Chọn khoảng chương...'),
                    ),
                  ),
                ],
              );
              actions = <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Huỷ'),
                ),
              ];
            } else {
              content = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rangeFrom,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Từ chương',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _rangeTo,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Đến chương',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (rangeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      rangeError!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              );
              actions = <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Huỷ'),
                ),
                FilledButton(
                  onPressed: () {
                    final int? from = int.tryParse(_rangeFrom!.text.trim());
                    final int? to = int.tryParse(_rangeTo!.text.trim());
                    if (from == null ||
                        to == null ||
                        from < 1 ||
                        to > total ||
                        from > to) {
                      setDialogState(
                        () => rangeError =
                            'Nhập khoảng hợp lệ: 1 ≤ từ ≤ đến ≤ $total.',
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    _startDownload(from: from, to: to);
                  },
                  child: const Text('Tải'),
                ),
              ];
            }

            return AlertDialog(
              title: const Text('Tải offline'),
              content: content,
              actions: actions,
            );
          },
        );
      },
    );
  }

  /// Dialog khi truyện đã tải: tải lại / xoá bản tải.
  Future<void> _showDownloadedMenu() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Đã tải $_downloadedCount chương'),
        content: const Text(
          'Bạn có thể tải lại để lấy bản mới nhất, hoặc xoá để giải phóng bộ nhớ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Huỷ'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _removeDownloaded();
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Xoá bản tải'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _startDownload();
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tải lại'),
          ),
        ],
      ),
    );
  }

  /// Tải [from]..[to] chương vào SQLite, hiện dialog tiến trình + nút Huỷ.
  Future<void> _startDownload({int from = 1, int? to}) async {
    bool cancelled = false;
    int done = 0;
    String? errorMessage;
    final ValueNotifier<double> progress = ValueNotifier<double>(0);
    final ValueNotifier<String> status = ValueNotifier<String>(
      'Đang chuẩn bị...',
    );

    // Hiện dialog tiến trình (chỉ parent mới đóng được — xem PopScope).
    final Future<void> dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => _DownloadProgressDialog(
        progress: progress,
        status: status,
        onCancel: () {
          cancelled = true;
          status.value = 'Đang huỷ...';
        },
      ),
    );

    try {
      done = await OfflineService.instance.downloadStory(
        widget.story,
        from: from,
        to: to,
        onProgress: (int d, int total) {
          progress.value = total == 0 ? 0 : d / total;
          status.value = 'Đang tải $d/$total chương...';
        },
        isCancelled: () => cancelled,
      );
    } on ApiException catch (e) {
      errorMessage = e.message;
    } catch (_) {
      errorMessage = 'Không tải được truyện. Kiểm tra mạng rồi thử lại.';
    }

    if (mounted) Navigator.of(context).pop(); // đóng dialog tiến trình
    await dialog;
    progress.dispose();
    status.dispose();

    if (errorMessage != null) {
      _showMessage(errorMessage);
      return;
    }
    await _checkDownloaded();
    if (cancelled) {
      _showMessage('Đã huỷ — máy đã lưu $done chương.');
    } else {
      _showMessage('Đã tải $done chương. Giờ đọc được cả khi mất mạng!');
    }
  }

  Future<void> _removeDownloaded() async {
    try {
      await OfflineService.instance.removeStory(widget.story.id);
      await _checkDownloaded();
      _showMessage('Đã xoá bản tải để giải phóng bộ nhớ.');
    } catch (_) {
      _showMessage('Không xoá được bản tải. Vui lòng thử lại.');
    }
  }

  String _dateLabel(DateTime time) {
    final String dd = time.day.toString().padLeft(2, '0');
    final String mm = time.month.toString().padLeft(2, '0');
    return '$dd/$mm/${time.year}';
  }

  // ------------------------------------------------------------------
  // Bình luận (Bước 8 — GET/POST /stories/{id}/comments,
  // DELETE /comments/{id}; xem / gửi / xoá của mình — A3.6)
  // ------------------------------------------------------------------

  /// Mở tab Bình luận lần đầu → tải danh sách.
  void _openCommentTab() {
    setState(() => _tab = 1);
    if (!_commentsLoaded && !_loadingComments) _loadComments();
  }

  /// Tải toàn bộ bình luận của truyện (cho phép cả khách).
  Future<void> _loadComments() async {
    setState(() {
      _loadingComments = true;
      _commentsError = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final List<Comment> list = await _api.fetchComments(widget.story.id);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(list);
        _loadingComments = false;
        _commentsLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commentsError = e;
        _loadingComments = false;
      });
    }
  }

  /// Gửi bình luận — bắt buộc đăng nhập (ô nhập chỉ hiện khi đã đăng nhập).
  Future<void> _sendComment() async {
    if (_sendingComment) return;
    final String text = _commentInput.text.trim();
    if (text.isEmpty) {
      _showMessage('Nội dung bình luận không được để trống.');
      return;
    }
    setState(() => _sendingComment = true);
    try {
      _api.setToken(AuthService.instance.session?.token);
      final Comment created = await _api.addComment(widget.story.id, text);
      _commentInput.clear();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        _comments.insert(0, created); // mới nhất lên đầu
        _sendingComment = false;
      });
      _showMessage('Đã gửi bình luận.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sendingComment = false);
      if (e.statusCode == 401) {
        _showMessage('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
      } else {
        _showMessage(e.message);
      }
    }
  }

  /// Xoá bình luận của chính mình — hỏi lại trước khi xoá.
  Future<void> _deleteComment(Comment comment) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Xoá bình luận?'),
        content: const Text('Bình luận sẽ bị xoá vĩnh viễn, bạn không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      _api.setToken(AuthService.instance.session?.token);
      await _api.deleteComment(comment.id);
      if (!mounted) return;
      setState(() => _comments.removeWhere((Comment c) => c.id == comment.id));
      _showMessage('Đã xoá bình luận.');
    } on ApiException catch (e) {
      _showMessage(e.message);
      // Quyền thay đổi sau khi gửi yêu cầu → tải lại cho đúng.
      _loadComments();
    }
  }

  /// Mở màn đăng nhập rồi tải lại danh sách (phòng khi quyền thay đổi).
  Future<void> _openLoginForComment() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Story story = widget.story;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ---------- Thanh quay lại ----------
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Quay lại',
                ),
              ],
            ),
            const SizedBox(height: 4),

            // ---------- Bìa + thông tin ----------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 116,
                  height: 160,
                  child: StoryCover(story: story, radius: 14),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(story.title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        story.author,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: story.genres
                            .map((String g) => GenreChip(label: g))
                            .toList(),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                story.ratingLabel,
                                style: theme.textTheme.labelMedium,
                              ),
                            ],
                          ),
                          Text(
                            story.chapterLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          _StatusPill(label: story.statusLabel),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---------- Nút Đọc / Đọc tiếp + Theo dõi + Tải offline ----------
            FilledButton.icon(
              onPressed: _chapters.isEmpty ? null : () => _openReader(),
              icon: const Icon(Icons.menu_book_rounded),
              label: Text(_progress == null ? 'Đọc' : 'Đọc tiếp'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _following
                      ? FilledButton.icon(
                          onPressed: _followBusy ? null : _onFollow,
                          icon: const Icon(Icons.favorite_rounded, size: 18),
                          label: const Text('Đã theo dõi'),
                        )
                      : OutlinedButton.icon(
                          onPressed: _followBusy ? null : _onFollow,
                          icon: const Icon(
                            Icons.favorite_border_rounded,
                            size: 18,
                          ),
                          label: const Text('Theo dõi'),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onOffline,
                    icon: Icon(
                      _downloaded
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _downloaded
                          ? 'Đã tải ($_downloadedCount)'
                          : 'Tải offline',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---------- Mô tả ----------
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.description ?? 'Chưa có mô tả cho truyện này.',
                  maxLines: _descriptionExpanded ? null : 4,
                  overflow: _descriptionExpanded ? null : TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _descriptionExpanded = !_descriptionExpanded,
                  ),
                  child: Text(_descriptionExpanded ? 'Thu gọn' : 'Xem thêm'),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // ---------- Tab: Chương | Bình luận ----------
            Row(
              children: [
                _TabPill(
                  label: 'Chương',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
                _TabPill(
                  label: 'Bình luận',
                  selected: _tab == 1,
                  onTap: _openCommentTab,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---------- Nội dung tab ----------
            if (_tab == 1)
              ..._commentSection(theme)
            else
              ..._chapterSection(theme),
          ],
        ),
      ),
    );
  }

  /// Danh sách chương + phân trang.
  List<Widget> _chapterSection(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;

    if (_loadingChapters) {
      return <Widget>[
        const SkeletonBox(width: double.infinity, height: 56, radius: 12),
        const SizedBox(height: 8),
        const SkeletonBox(width: double.infinity, height: 56, radius: 12),
        const SizedBox(height: 8),
        const SkeletonBox(width: double.infinity, height: 56, radius: 12),
      ];
    }

    if (_chapterError != null) {
      return <Widget>[
        ErrorState(
          message: _chapterError is ApiException
              ? (_chapterError as ApiException).message
              : 'Không tải được danh sách chương.',
          onRetry: _loadChapters,
        ),
      ];
    }

    if (_chapters.isEmpty) {
      return <Widget>[
        const EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'Chưa có chương nào',
          message: 'Truyện này chưa đăng chương.',
        ),
      ];
    }

    return <Widget>[
      for (final ChapterSummary chapter in _chapters)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => _openReader(index: chapter.index),
              leading: Text(
                '${chapter.index}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
              title: Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                _dateLabel(chapter.updatedAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
          ),
        ),
      if (_hasMore)
        Center(
          child: _loadingMore
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                )
              : TextButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: const Text('Xem thêm chương'),
                ),
        ),
    ];
  }

  /// Tab Bình luận: ô nhập (chỉ khi đã đăng nhập) + danh sách bình luận (A3.6).
  List<Widget> _commentSection(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;

    // ---------------- Ô nhập / lời mời đăng nhập ----------------
    // AnimatedBuilder để ô nhập hiện ra ngay khi đăng nhập xong.
    final Widget inputBox = AnimatedBuilder(
      animation: AuthService.instance,
      builder: (BuildContext context, _) {
        if (!AuthService.instance.isLoggedIn) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: Text(
                'Đăng nhập để bình luận',
                style: theme.textTheme.titleSmall,
              ),
              subtitle: const Text('Chia sẻ cảm nhận của bạn về truyện.'),
              trailing: FilledButton(
                onPressed: _openLoginForComment,
                child: const Text('Đăng nhập'),
              ),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentInput,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendComment(),
                    decoration: const InputDecoration(
                      hintText: 'Viết bình luận...',
                      counterText: '',
                      border: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _sendingComment
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : IconButton.filled(
                        onPressed: _sendComment,
                        icon: const Icon(Icons.send_rounded, size: 20),
                        tooltip: 'Gửi bình luận',
                      ),
              ],
            ),
          ),
        );
      },
    );

    // ---------------- Trạng thái đang tải ----------------
    if (_loadingComments && _comments.isEmpty && _commentsError == null) {
      return <Widget>[
        inputBox,
        const SizedBox(height: 12),
        const SkeletonBox(width: double.infinity, height: 72, radius: 12),
        const SizedBox(height: 8),
        const SkeletonBox(width: double.infinity, height: 72, radius: 12),
      ];
    }

    // ---------------- Trạng thái lỗi ----------------
    if (_commentsError != null) {
      return <Widget>[
        inputBox,
        const SizedBox(height: 12),
        ErrorState(
          message: _commentsError is ApiException
              ? (_commentsError as ApiException).message
              : 'Không tải được bình luận.',
          onRetry: _loadComments,
        ),
      ];
    }

    // ---------------- Rỗng ----------------
    if (_comments.isEmpty) {
      return <Widget>[
        inputBox,
        const SizedBox(height: 12),
        const EmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Chưa có bình luận nào',
          message: 'Hãy là người đầu tiên chia sẻ cảm nhận về truyện này.',
        ),
      ];
    }

    // ---------------- Danh sách ----------------
    final int? myId = AuthService.instance.user?.id;
    return <Widget>[
      inputBox,
      const SizedBox(height: 12),
      Text(
        '${_comments.length} bình luận',
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      for (final Comment comment in _comments)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar chữ ký tự đầu tên (giống fallback ảnh bìa)
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.primary,
                    child: Text(
                      comment.initial,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                comment.userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            Text(
                              _dateLabel(comment.createdAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(comment.content, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  // Chỉ hiện nút xoá khi là bình luận của mình (A3.6)
                  if (myId != null && comment.userId == myId)
                    IconButton(
                      onPressed: () => _deleteComment(comment),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      tooltip: 'Xoá bình luận',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}

/// Viên trạng thái "Đang ra" / "Hoàn thành" ở đầu trang chi tiết.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Tab pill cùng phong cách với thanh điều hướng.
class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? AppColors.white : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog tiến trình tải offline: thanh phần trăm + nhãn + nút Huỷ (A3.8).
///
/// Chỉ `_startDownload` đóng dialog này; phím Back của máy gọi [onCancel]
/// (không được dismiss lung tung khi đang tải dở).
class _DownloadProgressDialog extends StatelessWidget {
  const _DownloadProgressDialog({
    required this.progress,
    required this.status,
    required this.onCancel,
  });

  /// Tiến độ 0.0–1.0.
  final ValueListenable<double> progress;

  /// Nhãn hiện tại, ví dụ `Đang tải 3/128 chương...`.
  final ValueListenable<String> status;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) onCancel();
      },
      child: AlertDialog(
        title: const Text('Đang tải offline'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (BuildContext context, String value, _) =>
                  Text(value, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (BuildContext context, double value, _) =>
                  LinearProgressIndicator(value: value),
            ),
          ],
        ),
        actions: [TextButton(onPressed: onCancel, child: const Text('Huỷ'))],
      ),
    );
  }
}
