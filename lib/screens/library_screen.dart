import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../models/downloaded_story.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/db_helper.dart';
import '../services/offline_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton.dart';
import '../widgets/story_card.dart';
import 'auth_screen.dart';
import 'reader_screen.dart';
import 'story_detail_screen.dart';

/// Tab **Tủ sách** — 3 tab *Theo dõi | Lịch sử | Đã tải* (A3.7, Bước 7).
///
/// - **Theo dõi**: GET /me/follows (bắt buộc đăng nhập).
/// - **Lịch sử**: đọc từ bảng SQLite `reading_history` (A4), dòng
///   "Chương N – Tên chương" kèm nút "…" và "×".
/// - **Đã tải**: đọc từ `downloaded_stories`, mở được khi mất mạng;
///   xoá để giải phóng bộ nhớ (A3.8).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.api,
    this.initialHistory,
    this.shellTab,
  });

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  /// Trồng sẵn danh sách lịch sử — test widget không cần SQLite thật.
  @visibleForTesting
  final List<HistoryEntry>? initialHistory;

  /// Tab shell (bottom nav) đang chọn — MainShell truyền vào để LibraryScreen
  /// **tải lại cả 3 tab mỗi lần quay về Tủ sách** (IndexedStack không tự
  /// reload khi người dùng theo dõi / đọc / tải truyện ở màn khác).
  final ValueListenable<int>? shellTab;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  int _tab = 0; // 0 = theo dõi, 1 = lịch sử, 2 = đã tải

  // ------------------------- Theo dõi -------------------------
  List<Story> _follows = <Story>[];
  bool _loadingFollows = true;
  Object? _followsError;

  /// Id người dùng mà [_follows] hiện tại thuộc về (`null` = khách).
  int? _followsForUser;

  // ------------------------- Lịch sử --------------------------
  List<HistoryEntry> _history = <HistoryEntry>[];
  bool _loadingHistory = true;

  /// Tên truyện theo id — làm phụ đề cho dòng lịch sử (nạp qua API nếu cần).
  final Map<int, Story> _storyCache = <int, Story>{};

  // ------------------------- Đã tải ---------------------------
  List<DownloadedStory> _downloaded = <DownloadedStory>[];
  bool _loadingDownloaded = true;
  Object? _downloadedError;

  @override
  void initState() {
    super.initState();
    if (widget.initialHistory != null) {
      _history = List<HistoryEntry>.of(widget.initialHistory!);
      _loadingHistory = false;
    } else {
      _loadHistory();
    }
    _loadDownloaded();
    _syncFollows();
    widget.shellTab?.addListener(_onShellTabChanged);
  }

  @override
  void dispose() {
    widget.shellTab?.removeListener(_onShellTabChanged);
    super.dispose();
  }

  /// Shell vừa chọn lại tab Tủ sách (index 1) → tải lại dữ liệu mới nhất:
  /// người dùng vừa theo dõi / đọc / tải truyện ở màn khác (A3.7).
  void _onShellTabChanged() {
    if (widget.shellTab?.value == 1) _refreshAll();
  }

  /// Nạp lại cả 3 tab mà không để skeleton chiếm chỗ khi đã có dữ liệu cũ.
  void _refreshAll() {
    if (!mounted) return;
    // Chỉ nạp lại khi đã đăng nhập — chưa đăng nhập tab Theo dõi vẫn là lời mời
    // (AnimatedBuilder đã tự xử lý khi đổi phiên).
    if (AuthService.instance.isLoggedIn) _loadFollows();
    _loadHistory();
    _loadDownloaded();
  }

  int? get _currentUserId => AuthService.instance.session?.user.id;

  // ==================================================================
  // Theo dõi
  // ==================================================================

  /// Nạp danh sách theo dõi nếu nó chưa thuộc người dùng hiện tại.
  ///
  /// Có thể gọi từ builder nghe [AuthService] nên phải trì hoãn [_loadFollows]
  /// sang frame sau, tránh `setState` ngay trong lúc build.
  void _syncFollows() {
    final int? uid = _currentUserId;
    if (_followsForUser == uid) return;
    _followsForUser = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _followsForUser == uid) _loadFollows();
    });
  }

  Future<void> _loadFollows() async {
    final int? uid = _followsForUser;
    if (uid == null) {
      // Chưa đăng nhập → tab Theo dõi hiển thị lời mời đăng nhập.
      if (!mounted) return;
      setState(() {
        _follows = <Story>[];
        _loadingFollows = false;
        _followsError = null;
      });
      return;
    }
    setState(() {
      _loadingFollows = true;
      _followsError = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final List<Story> list = await _api.fetchMyFollows();
      if (!mounted || _currentUserId != uid) return;
      setState(() {
        _follows = list;
        _loadingFollows = false;
      });
    } catch (e) {
      if (!mounted || _currentUserId != uid) return;
      setState(() {
        _followsError = e;
        _loadingFollows = false;
      });
    }
  }

  Future<void> _openLogin() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
    // AuthService.notifyListeners → AnimatedBuilder tự gọi _syncFollows.
  }

  // ==================================================================
  // Lịch sử
  // ==================================================================

  Future<void> _loadHistory() async {
    try {
      final List<HistoryEntry> list = await DbHelper.instance.history();
      if (!mounted) return;
      setState(() {
        _history = list;
        _loadingHistory = false;
      });
      await _hydrateStoryTitles(list);
    } catch (_) {
      // SQLite không mở được → tab Lịch sử rỗng (không phá luồng đọc).
      if (!mounted) return;
      setState(() {
        _history = <HistoryEntry>[];
        _loadingHistory = false;
      });
    }
  }

  /// Gắn tên truyện vào phụ đề dòng lịch sử: ưu tiên bản đã tải, không có
  /// thì hỏi API (mất mạng thì bỏ qua — dòng vẫn hiển thị "Chương N – ...").
  Future<void> _hydrateStoryTitles(List<HistoryEntry> list) async {
    final Map<int, DownloadedStory> downloadedById = <int, DownloadedStory>{
      for (final DownloadedStory d in _downloaded) d.id: d,
    };
    for (final int storyId in list.map((HistoryEntry e) => e.storyId).toSet()) {
      if (_storyCache.containsKey(storyId)) continue;
      final DownloadedStory? local = downloadedById[storyId];
      final Story resolved;
      if (local != null) {
        resolved = local.toStory();
      } else {
        try {
          resolved = await _api.fetchStory(storyId);
        } catch (_) {
          continue; // ngoại tuyến → để trống tên truyện
        }
      }
      if (!mounted) return;
      setState(() => _storyCache[storyId] = resolved);
    }
  }

  Future<void> _openHistory(HistoryEntry entry) async {
    final Story? cached = _storyCache[entry.storyId];
    final Story story;
    if (cached != null) {
      story = cached;
    } else {
      try {
        story = await _api.fetchStory(entry.storyId);
      } catch (e) {
        _showMessage(
          e is ApiException ? e.message : 'Không mở được truyện đã đọc.',
        );
        return;
      }
    }
    if (!mounted) return;

    // Truyện có chương này trong SQLite → đọc offline được ngay.
    bool offline = false;
    try {
      offline = await DbHelper.instance.hasChapter(
        entry.storyId,
        entry.chapterIndex,
      );
    } catch (_) {}

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          story: story,
          initialIndex: entry.chapterIndex,
          api: _api,
          offline: offline,
        ),
      ),
    );
    if (mounted) _refreshAll(); // quay lại → cập nhật lịch sử + các tab khác
  }

  Future<void> _removeHistory(HistoryEntry entry) async {
    if (!mounted) return;
    // Xoá khỏi UI trước — luôn xoá được kể cả khi SQLite chưa sẵn sàng;
    // history chỉ là bản sao cục bộ nên ghi db lỗi không chặn thao tác.
    setState(
      () =>
          _history.removeWhere((HistoryEntry e) => e.storyId == entry.storyId),
    );
    try {
      await DbHelper.instance.deleteHistory(entry.storyId);
    } catch (_) {
      // SQLite chưa sẵn sàng → dòng sẽ tự quay lại ở lần mở sau.
    }
    _showMessage('Đã xoá khỏi lịch sử đọc.');
  }

  // ==================================================================
  // Đã tải
  // ==================================================================

  Future<void> _loadDownloaded() async {
    try {
      final List<DownloadedStory> list = await OfflineService.instance
          .downloadedStories();
      if (!mounted) return;
      setState(() {
        _downloaded = list;
        _loadingDownloaded = false;
        _downloadedError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadedError = e;
        _loadingDownloaded = false;
      });
    }
  }

  Future<void> _openDownloaded(DownloadedStory story) async {
    final List<ChapterSummary> chapters = await OfflineService.instance
        .downloadedChapters(story.id);
    if (chapters.isEmpty) {
      _showMessage('Truyện này chưa có chương nào trong máy.');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          story: story.toStory(),
          initialIndex: chapters.first.index,
          api: _api,
          offline: true, // đọc hoàn toàn từ SQLite — không cần mạng
        ),
      ),
    );
    if (mounted) _refreshAll(); // đọc offline cũng ghi lịch sử → nạp lại
  }

  Future<void> _confirmRemoveDownloaded(DownloadedStory story) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Xoá "${story.title}"?'),
        content: Text(
          'Sẽ mất ${story.chapterCount} chương đã tải. '
          'Bạn vẫn tải lại được bất cứ lúc nào khi có mạng.',
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
    if (ok != true) return;
    try {
      await OfflineService.instance.removeStory(story.id);
      await _loadDownloaded();
      _showMessage('Đã xoá bản tải để giải phóng bộ nhớ.');
    } catch (_) {
      _showMessage('Không xoá được bản tải. Vui lòng thử lại.');
    }
  }

  // ==================================================================
  // Giao diện
  // ==================================================================

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tủ sách')),
      body: Column(
        children: [
          // ---------- Bộ chọn 3 tab ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  label: Text('Theo dõi'),
                  icon: Icon(Icons.favorite_border_rounded, size: 18),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('Lịch sử'),
                  icon: Icon(Icons.history_rounded, size: 18),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text('Đã tải'),
                  icon: Icon(Icons.download_rounded, size: 18),
                ),
              ],
              selected: <int>{_tab},
              onSelectionChanged: (Set<int> value) =>
                  setState(() => _tab = value.first),
            ),
          ),
          Expanded(
            child: _tab == 0
                ? _followsBody()
                : _tab == 1
                ? _historyBody()
                : _downloadedBody(),
          ),
        ],
      ),
    );
  }

  // ------------------------- Tab: Theo dõi -------------------------

  Widget _followsBody() {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (BuildContext context, _) {
        _syncFollows(); // đăng nhập/đăng xuất → nạp lại danh sách

        if (!AuthService.instance.isLoggedIn) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'Theo dõi truyện yêu thích',
                    message: 'Đăng nhập để giữ danh sách theo dõi trên mọi thiết bị.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _openLogin,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Đăng nhập'),
                  ),
                ],
              ),
            ),
          );
        }

        if (_followsForUser != _currentUserId ||
            (_loadingFollows && _follows.isEmpty)) {
          return _skeletonList(); // đang nạp lần đầu / của người dùng khác
        }

        if (_followsError != null) {
          return ErrorState(
            message: _followsError is ApiException
                ? (_followsError as ApiException).message
                : 'Không tải được danh sách theo dõi.',
            onRetry: _loadFollows,
          );
        }

        if (_follows.isEmpty) {
          return const EmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'Chưa theo dõi truyện nào',
            message: 'Bấm "Theo dõi" ở màn chi tiết truyện để thêm vào đây.',
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: <Widget>[
            for (final Story story in _follows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StoryTile(
                  story: story,
                  // Mở chi tiết → quay về tải lại: theo dõi / tải offline /
                  // lịch sử đều có thể đổi ở màn chi tiết (A3.4).
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            StoryDetailScreen(story: story, api: _api),
                      ),
                    );
                    if (mounted) _refreshAll();
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  // ------------------------- Tab: Lịch sử --------------------------

  Widget _historyBody() {
    if (_loadingHistory) return _skeletonList();

    if (_history.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'Chưa có lịch sử đọc',
        message: 'Những chương bạn đọc sẽ xuất hiện ở đây.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _history.length,
      itemBuilder: (BuildContext context, int i) {
        final HistoryEntry entry = _history[i];
        final Story? story = _storyCache[entry.storyId];
        final String subtitle = <String>[
          if (story != null && story.title.isNotEmpty) story.title,
          entry.timeLabel,
        ].join(' · ');

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => _openHistory(entry),
              title: Text(
                entry.chapterLabel, // "Chương N – Tên chương" (A3.7)
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Nút "…" — menu tuỳ chọn của dòng lịch sử
                  PopupMenuButton<String>(
                    tooltip: 'Tuỳ chọn',
                    onSelected: (String action) {
                      if (action == 'open') {
                        _openHistory(entry);
                      } else {
                        _removeHistory(entry);
                      }
                    },
                    itemBuilder: (BuildContext menuContext) =>
                        const <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'open',
                            child: ListTile(
                              leading: Icon(Icons.menu_book_rounded),
                              title: Text('Đọc tiếp'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline_rounded),
                              title: Text('Xoá khỏi lịch sử'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                  ),
                  // Nút "×" — xoá nhanh
                  IconButton(
                    onPressed: () => _removeHistory(entry),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Xoá khỏi lịch sử',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------- Tab: Đã tải ---------------------------

  Widget _downloadedBody() {
    if (_loadingDownloaded) return _skeletonList();

    if (_downloadedError != null) {
      return ErrorState(
        title: 'Không đọc được dữ liệu ngoại tuyến',
        message: 'SQLite trên máy này không sẵn dùng. Thử lại sau.',
        onRetry: _loadDownloaded,
      );
    }

    if (_downloaded.isEmpty) {
      return const EmptyState(
        icon: Icons.download_rounded,
        title: 'Chưa có truyện tải offline',
        message: 'Dùng nút "Tải offline" ở màn chi tiết truyện để lưu chương về máy, đọc được khi mất mạng.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _downloaded.length,
      itemBuilder: (BuildContext context, int i) {
        final DownloadedStory story = _downloaded[i];
        // Tác giả nguyên tác; db cũ chưa có cột → "Chưa rõ" tới khi tải lại.
        final String author = (story.originalAuthor ?? '').trim();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => _openDownloaded(story),
              leading: _DownloadedCover(story: story),
              title: Text(
                story.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${author.isEmpty ? 'Chưa rõ' : author} · ${story.chapterCount} chương',
              ),
              trailing: IconButton(
                onPressed: () => _confirmRemoveDownloaded(story),
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Xoá bản tải',
              ),
            ),
          ),
        );
      },
    );
  }

  /// Bộ xương chờ dùng chung cho 3 tab.
  Widget _skeletonList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: const <Widget>[
        SkeletonBox(width: double.infinity, height: 72, radius: 16),
        SizedBox(height: 8),
        SkeletonBox(width: double.infinity, height: 72, radius: 16),
        SizedBox(height: 8),
        SkeletonBox(width: double.infinity, height: 72, radius: 16),
      ],
    );
  }
}

/// Bìa truyện ở tab "Đã tải": ưu tiên file ảnh đã lưu, không có thì
/// fallback về bìa chữ cái mặc định (không cần mạng).
class _DownloadedCover extends StatelessWidget {
  const _DownloadedCover({required this.story});

  final DownloadedStory story;

  @override
  Widget build(BuildContext context) {
    final Story forCover = story.toStory();
    final Widget fallback = StoryCover(story: forCover, radius: 8);
    final String? path = story.coverPath;

    if (kIsWeb || path == null || path.isEmpty) return fallback;

    return SizedBox(
      width: 42,
      height: 58,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
              fallback,
        ),
      ),
    );
  }
}
