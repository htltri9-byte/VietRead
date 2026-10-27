import 'package:flutter/material.dart';

import '../models/genre.dart';
import '../models/reading_progress.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/reading_progress_store.dart';
import '../theme/app_theme.dart';
import '../widgets/chip_genre.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton.dart';
import '../widgets/story_card.dart';
import 'auth_screen.dart';
import 'reader_screen.dart';
import 'search_screen.dart';
import 'story_detail_screen.dart';

/// Trang **Khám phá** (A2) gồm 5 khối:
/// 1) header chào + ô tìm kiếm bo tròn, 2) thẻ "Đọc tiếp",
/// 3) chip thể loại cuộn ngang, 4) lưới "Đang hot", 5) "Mới cập nhật".
///
/// Dữ liệu lấy qua [ApiService] — Bước 4 đang là `MockApiService`
/// (đổi cờ `ApiConfig.useMock` để gọi API thật ở Bước 6).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.api});

  /// Cho phép tiêm nguồn dữ liệu (test widget dùng mock không ảnh bìa).
  final ApiService? api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  late Future<_HomeFeed> _feed = _load();

  /// Tải song song thể loại + danh sách "Đang hot" + "Mới cập nhật",
  /// đồng thời nạp tiến độ đọc gần nhất cho thẻ "Đọc tiếp".
  Future<_HomeFeed> _load() async {
    await ReadingProgressStore.instance.loadLatest();
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      _api.fetchGenres(),
      _api.fetchStories(sort: 'hot', pageSize: 4),
      _api.fetchStories(sort: 'newest', pageSize: 6),
    ]);
    return _HomeFeed(
      genres: results[0]! as List<Genre>,
      hot: results[1]! as List<Story>,
      latest: results[2]! as List<Story>,
    );
  }

  /// Tải lại dữ liệu (dùng cho nút "Thử lại" và kéo xuống làm mới).
  void _retry() {
    // Để ý: closure của setState phải trả về void — không được trả Future.
    setState(() {
      _feed = _load();
    });
  }

  /// Mở màn Tìm kiếm & lọc (A3.3) — chọn sẵn thể loại nếu bấm chip.
  void _openSearch({String? genre}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchScreen(api: _api, initialGenre: genre),
      ),
    );
  }

  String _errorMessage(Object error) {
    if (error is ApiException) return error.message;
    return 'Đã có lỗi xảy ra. Vui lòng thử lại.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Nghe trạng thái đăng nhập để chào đúng tên người dùng (Bước 6).
        child: AnimatedBuilder(
          animation: AuthService.instance,
          builder: (BuildContext context, _) {
            return RefreshIndicator(
              onRefresh: () async {
                _retry();
                try {
                  await _feed;
                } catch (_) {
                  // lỗi đã được FutureBuilder xử lý ở UI
                }
              },
              child: FutureBuilder<_HomeFeed>(
                future: _feed,
                builder:
                    (BuildContext context, AsyncSnapshot<_HomeFeed> snapshot) {
                      // --- Đang tải: skeleton ---
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const HomeSkeleton();
                      }
                      // --- Lỗi: trạng thái lỗi + nút "Thử lại" ---
                      if (snapshot.hasError) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 60),
                          children: [
                            ErrorState(
                              message: _errorMessage(snapshot.error!),
                              onRetry: _retry,
                            ),
                          ],
                        );
                      }
                      final _HomeFeed feed = snapshot.data!;
                      // --- Rỗng ---
                      if (feed.hot.isEmpty && feed.latest.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            EmptyState(
                              icon: Icons.auto_stories_outlined,
                              title: 'Chưa có truyện nào',
                              message: 'Quay lại sau khi có tác giả đăng truyện nhé!',
                            ),
                          ],
                        );
                      }
                      // --- Có dữ liệu ---
                      return _HomeBody(
                        feed: feed,
                        progress: ReadingProgressStore.instance.current,
                        api: _api,
                        onRetry: _retry,
                        onOpenSearch: _openSearch,
                      );
                    },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Dữ liệu một lần tải của trang Khám phá.
class _HomeFeed {
  const _HomeFeed({
    required this.genres,
    required this.hot,
    required this.latest,
  });

  final List<Genre> genres;
  final List<Story> hot;
  final List<Story> latest;
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.feed,
    required this.progress,
    required this.api,
    required this.onRetry,
    required this.onOpenSearch,
  });

  final _HomeFeed feed;
  final ReadingProgress? progress;
  final ApiService api;
  final VoidCallback onRetry;

  /// Mở màn Tìm kiếm & lọc, chọn sẵn thể loại (null = không chọn).
  final void Function({String? genre}) onOpenSearch;

  /// Lời chào theo giờ + tên người dùng nếu đã đăng nhập (Bước 6).
  String _greeting() {
    final int hour = DateTime.now().hour;
    final String label;
    if (hour < 11) {
      label = 'Chào buổi sáng';
    } else if (hour < 13) {
      label = 'Chào buổi trưa';
    } else if (hour < 18) {
      label = 'Chào buổi chiều';
    } else {
      label = 'Chào buổi tối';
    }
    final String? name = AuthService.instance.user?.name;
    return name == null || name.trim().isEmpty
        ? label
        : '$label, ${name.trim()}';
  }

  /// Chạm avatar ở header: chưa đăng nhập → mở màn đăng nhập (Bước 6),
  /// đã đăng nhập → báo trạng thái thân thiện.
  void _onAccount(BuildContext context) {
    final AuthService auth = AuthService.instance;
    if (!auth.isLoggedIn) {
      Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Bạn đang đăng nhập với tên ${auth.user?.name}.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ---------- 1) Header chào + ô tìm kiếm bo tròn ----------
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_greeting()} 👋', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Hôm nay bạn muốn đọc gì?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _onAccount(context),
              icon: const Icon(Icons.person_outline_rounded, size: 28),
              tooltip: 'Tài khoản',
            ),
          ],
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => onOpenSearch(),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.round),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  'Tìm truyện, tác giả...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ---------- 2) Thẻ lớn "Đọc tiếp" ----------
        if (progress != null) ...[
          _ContinueCard(
            progress: progress!,
            onTap: () => _openReader(context, progress!),
          ),
          const SizedBox(height: 22),
        ],

        // ---------- 3) Chip thể loại cuộn ngang ----------
        if (feed.genres.isNotEmpty) ...[
          Text('Chọn thể loại', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: feed.genres.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int index) => GenreChip(
                label: feed.genres[index].name,
                onTap: () => onOpenSearch(genre: feed.genres[index].name),
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],

        // ---------- 4) Mục "Đang hot" dạng lưới 2 cột ----------
        Text('Đang hot', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemCount: feed.hot.length,
          itemBuilder: (BuildContext context, int index) => StoryCard(
            story: feed.hot[index],
            onTap: () => _openDetail(context, feed.hot[index]),
          ),
        ),
        const SizedBox(height: 22),

        // ---------- 5) Mục "Mới cập nhật" ----------
        Text('Mới cập nhật', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final Story story in feed.latest) ...[
          StoryTile(story: story, onTap: () => _openDetail(context, story)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// Mở màn chi tiết truyện (Bước 5).
  void _openDetail(BuildContext context, Story story) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoryDetailScreen(story: story, api: api),
      ),
    );
  }

  /// Mở màn đọc tiếp ngay tại chương đang đọc dở (Bước 5).
  void _openReader(BuildContext context, ReadingProgress value) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          story: value.story,
          initialIndex: value.chapterIndex,
          api: api,
        ),
      ),
    );
  }
}

/// Thẻ "Đọc tiếp": truyện đang đọc dở + thanh tiến độ (A2).
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.progress, required this.onTap});

  final ReadingProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 74,
                height: 104,
                child: StoryCover(story: progress.story, radius: 12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ĐỌC TIẾP',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progress.story.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progress.chapterLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.progress,
                        minHeight: 6,
                        backgroundColor: scheme.outlineVariant,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          progress.percentLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
