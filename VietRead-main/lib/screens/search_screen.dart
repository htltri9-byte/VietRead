import 'package:flutter/material.dart';

import '../models/genre.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../widgets/chip_genre.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton.dart';
import '../widgets/story_card.dart';
import 'story_detail_screen.dart';

/// Màn **Tìm kiếm & lọc** (A3.3): tìm theo tên truyện / tên tác giả,
/// lọc theo thể loại + trạng thái, sắp xếp (mới, hot, điểm, tên).
///
/// Gọi `GET /stories?query=&genre=&status=&sort=` — backend đã có sẵn từ Bước 2.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.api,
    this.initialQuery,
    this.initialGenre,
  });

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  /// Từ khoá / thể loại chọn sẵn khi mở màn (vd: bấm chip thể loại ở trang chủ).
  final String? initialQuery;
  final String? initialGenre;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery ?? '',
  );

  /// Bộ lọc hiện tại — khớp tên tham số của backend (Bước 2).
  String? _genre;
  String? _status; // null = tất cả, ongoing, completed
  String _sort = 'newest';

  late Future<List<Story>> _results;

  /// Danh sách tên thể loại cho hàng chip lọc (bọc lỗi: không tải được
  /// thể loại thì vẫn tìm kiếm được với các bộ lọc khác).
  List<Genre> _genreList = <Genre>[];

  @override
  void initState() {
    super.initState();
    _genre = widget.initialGenre;
    _results = _search();
    _loadGenreList();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Tải danh sách thể loại cho chip lọc — lỗi thì bỏ qua
  /// (vẫn tìm kiếm được với các bộ lọc khác).
  Future<void> _loadGenreList() async {
    try {
      final List<Genre> list = await _api.fetchGenres();
      if (mounted) setState(() => _genreList = list);
    } catch (_) {
      // Không tải được thể loại → vẫn cho phép tìm kiếm.
    }
  }

  /// Gọi API tìm kiếm với bộ lọc hiện tại.
  Future<List<Story>> _search() => _api.fetchStories(
    query: _query.text,
    genre: _genre,
    status: _status,
    sort: _sort,
    page: 1,
    pageSize: 50,
  );

  /// Chạy lại tìm kiếm (sau khi đổi từ khoá / bộ lọc).
  void _runSearch() {
    setState(() {
      _results = _search();
    });
  }

  String _errorMessage(Object error) {
    if (error is ApiException) return error.message;
    return 'Đã có lỗi xảy ra. Vui lòng thử lại.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- Thanh quay lại + ô tìm kiếm ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Quay lại',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(),
                      decoration: InputDecoration(
                        hintText: 'Tìm truyện, tác giả...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                tooltip: 'Xoá từ khoá',
                                onPressed: () {
                                  _query.clear();
                                  _runSearch();
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ---------- Chip thể loại (lọc) ----------
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  GenreChip(
                    label: 'Tất cả',
                    selected: _genre == null,
                    onTap: () => _applyGenre(null),
                  ),
                  for (final Genre g in _genreList) ...<Widget>[
                    const SizedBox(width: 8),
                    GenreChip(
                      label: g.name,
                      selected: _genre == g.name,
                      onTap: () =>
                          _applyGenre(_genre == g.name ? null : g.name),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ---------- Trạng thái + sắp xếp ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterMenu<String>(
                    label: _statusLabel,
                    icon: Icons.tune_rounded,
                    value: _status,
                    items: const <String, String>{
                      '': 'Tất cả trạng thái',
                      'ongoing': 'Đang ra',
                      'completed': 'Hoàn thành',
                    },
                    onChanged: (String value) {
                      setState(() => _status = value.isEmpty ? null : value);
                      _runSearch();
                    },
                  ),
                  const SizedBox(width: 10),
                  _FilterMenu<String>(
                    label: _sortLabel,
                    icon: Icons.sort_rounded,
                    value: _sort,
                    items: const <String, String>{
                      'newest': 'Mới nhất',
                      'hot': 'Hot',
                      'rating': 'Điểm cao',
                      'title': 'Tên A→Z',
                    },
                    onChanged: (String value) {
                      setState(() => _sort = value);
                      _runSearch();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ---------- Kết quả ----------
            Expanded(
              child: FutureBuilder<List<Story>>(
                future: _results,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<Story>> snapshot,
                    ) {
                      // --- Đang tải: skeleton lưới 2 cột ---
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const _ResultsSkeleton();
                      }
                      // --- Lỗi ---
                      if (snapshot.hasError) {
                        return ListView(
                          padding: const EdgeInsets.only(top: 40),
                          children: <Widget>[
                            ErrorState(
                              message: _errorMessage(snapshot.error!),
                              onRetry: _runSearch,
                            ),
                          ],
                        );
                      }
                      final List<Story> stories = snapshot.data!;
                      // --- Rỗng ---
                      if (stories.isEmpty) {
                        return ListView(
                          padding: const EdgeInsets.only(top: 20),
                          children: const <Widget>[
                            EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'Không tìm thấy truyện nào',
                              message:
                                  'Thử đổi từ khoá hoặc bỏ bớt bộ lọc nhé!',
                            ),
                          ],
                        );
                      }
                      // --- Có kết quả: lưới 2 cột như mục "Đang hot" ---
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.62,
                            ),
                        itemCount: stories.length,
                        itemBuilder: (BuildContext context, int index) =>
                            StoryCard(
                              story: stories[index],
                              onTap: () => _openDetail(stories[index]),
                            ),
                      );
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nhãn trạng thái đang chọn cho nút bộ lọc.
  String get _statusLabel => switch (_status) {
    'ongoing' => 'Đang ra',
    'completed' => 'Hoàn thành',
    _ => 'Trạng thái',
  };

  /// Nhãn sắp xếp đang chọn cho nút bộ lọc.
  String get _sortLabel => switch (_sort) {
    'hot' => 'Hot',
    'rating' => 'Điểm cao',
    'title' => 'Tên A→Z',
    _ => 'Mới nhất',
  };

  void _applyGenre(String? genre) {
    setState(() => _genre = genre);
    _runSearch();
  }

  /// Mở màn chi tiết truyện (cùng trang Khám phá).
  void _openDetail(Story story) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoryDetailScreen(story: story, api: _api),
      ),
    );
  }
}

/// Nút mở menu chọn giá trị lọc (trạng thái / sắp xếp).
class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final T? value;

  /// value → nhãn hiển thị.
  final Map<T, String> items;

  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Expanded(
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        items: items.entries
            .map(
              (MapEntry<T, String> e) => DropdownMenuItem<T>(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (T? newValue) {
          if (newValue != null) onChanged(newValue);
        },
      ),
    );
  }
}

/// Skeleton cho vùng kết quả (giống lưới 2 cột của trang Khám phá).
class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.62,
      ),
      itemCount: 6,
      itemBuilder: (BuildContext context, int index) => const SkeletonBox(
        width: double.infinity,
        height: double.infinity,
        radius: 16,
      ),
    );
  }
}
