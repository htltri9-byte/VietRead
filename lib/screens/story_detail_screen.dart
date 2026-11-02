import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../models/comment.dart';
import '../models/reading_progress.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/offline_service.dart';
import '../services/reading_progress_store.dart';
import '../widgets/chapter_list_section.dart';
import '../widgets/comment_section.dart';
import '../widgets/download_dialogs.dart';
import '../widgets/story_action_buttons.dart';
import '../widgets/story_header.dart';
import '../widgets/tab_pill.dart';
import 'auth_screen.dart';
import 'reader_screen.dart';

/// Màn **chi tiết truyện** (A3.4): bìa, tên, tác giả, thể loại, mô tả, điểm,
/// trạng thái, danh sách chương (phân trang), nút Đọc/Đọc tiếp, Theo dõi,
/// Tải offline và tab Bình luận.
///
/// Phần giao diện được tách thành widget độc lập: [StoryHeader],
/// [StoryActionButtons], [TabPill], [ChapterListSection], [CommentSection]
/// và các dialog trong `widgets/download_dialogs.dart` — State này giữ toàn
/// bộ trạng thái + logic (tải chương, theo dõi, tải offline, bình luận).
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
    await showDownloadRangeDialog(
      context,
      total: total,
      from: _rangeFrom!,
      to: _rangeTo!,
      onDownload: (int from, int? to) => _startDownload(from: from, to: to),
    );
  }

  /// Dialog khi truyện đã tải: tải lại / xoá bản tải.
  Future<void> _showDownloadedMenu() async {
    await showDownloadedMenuDialog(
      context,
      downloadedCount: _downloadedCount,
      onRemove: _removeDownloaded,
      onDownload: _startDownload,
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
      builder: (BuildContext dialogContext) => DownloadProgressDialog(
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
        content: const Text(
          'Bình luận sẽ bị xoá vĩnh viễn, bạn không thể khôi phục.',
        ),
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

  /// Mở màn đăng nhập (tab Bình luận tự hiện ô nhập khi đăng nhập xong).
  Future<void> _openLoginForComment() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
            StoryHeader(story: story),
            const SizedBox(height: 16),

            // ---------- Nút Đọc / Đọc tiếp + Theo dõi + Tải offline ----------
            StoryActionButtons(
              onRead: _chapters.isEmpty ? null : _openReader,
              hasProgress: _progress != null,
              following: _following,
              followBusy: _followBusy,
              onFollow: _onFollow,
              downloaded: _downloaded,
              downloadedCount: _downloadedCount,
              onOffline: _onOffline,
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
                TabPill(
                  label: 'Chương',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                const SizedBox(width: 8),
                TabPill(
                  label: 'Bình luận',
                  selected: _tab == 1,
                  onTap: _openCommentTab,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---------- Nội dung tab ----------
            if (_tab == 1)
              CommentSection(
                controller: _commentInput,
                comments: _comments,
                loading: _loadingComments,
                error: _commentsError,
                sending: _sendingComment,
                onSend: _sendComment,
                onDelete: _deleteComment,
                onLogin: _openLoginForComment,
                onRetry: _loadComments,
              )
            else
              ChapterListSection(
                loading: _loadingChapters,
                error: _chapterError,
                chapters: _chapters,
                hasMore: _hasMore,
                loadingMore: _loadingMore,
                onRetry: _loadChapters,
                onLoadMore: _loadMore,
                onSelect: (int index) => _openReader(index: index),
              ),
          ],
        ),
      ),
    );
  }
}
