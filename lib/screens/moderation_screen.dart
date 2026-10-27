import 'package:flutter/material.dart';

import '../models/moderation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/moderation_chip.dart';
import '../widgets/skeleton.dart';
import '../widgets/tab_pill.dart';
import 'moderation_detail_screen.dart';

/// Màn **Kiểm duyệt truyện** (chỉ Admin — vào từ màn Tài khoản).
///
/// - Chip lọc: Chờ duyệt · Đã duyệt · Từ chối · Cần xem lại
///   (khớp `?status=` của `GET /admin/stories`).
/// - Danh sách thẻ: bìa, tên, tác giả, số chương, lúc gửi duyệt, chip trạng thái.
/// - Kéo để làm mới, cuộn hết trang thì tải tiếp (phân trang).
/// - Skeleton / rỗng / lỗi giống các màn khác.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key, this.api});

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  static const int _pageSize = 20;

  late final ApiService _api = widget.api ?? ApiService();

  /// Tab lọc hiện tại (mặc định: chờ duyệt cũ nhất trước — backend tự sắp xếp).
  ModerationTab _tab = ModerationTab.pending;

  final List<AdminStory> _items = <AdminStory>[];
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  /// Bộ đếm yêu cầu — bỏ kết quả về muộn khi đổi tab / kéo làm mới.
  int _gen = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Cuộn gần cuối danh sách → tải trang kế tiếp.
  void _onScroll() {
    if (_loading || _loadingMore || !_hasMore || !_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 240) {
      return;
    }
    _page += 1;
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    final int gen;
    if (reset) {
      gen = ++_gen;
      _page = 1;
      _hasMore = true;
      setState(() {
        _error = null;
        _loading = _items.isEmpty;
      });
    } else {
      gen = _gen;
      setState(() => _loadingMore = true);
    }

    try {
      _api.setToken(AuthService.instance.session?.token);
      final List<AdminStory> page = await _api.fetchAdminStories(
        status: _tab.status,
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page);
        _hasMore = page.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset && _items.isEmpty) {
          _error = e; // trang đầu lỗi → màn lỗi có nút Thử lại
        } else if (!reset) {
          _page = _page > 1 ? _page - 1 : 1; // cuộn lỗi → hoàn tác trang
        }
      });
      if (!reset) _showMessage(_errorMessage(e));
    }
  }

  /// Đổi tab lọc → nạp lại từ trang 1.
  void _selectTab(ModerationTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _items.clear();
      _loading = true;
      _error = null;
    });
    _load(reset: true);
  }

  String _errorMessage(Object error) =>
      error is ApiException ? error.message : 'Không tải được danh sách kiểm duyệt.';

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Mở chi tiết kiểm duyệt; duyệt/từ chối xong quay về → nạp lại danh sách.
  Future<void> _openDetail(AdminStory story) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ModerationDetailScreen(api: _api, storyId: story.id),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Kiểm duyệt truyện')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ---------- Chip lọc trạng thái ----------
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 7,
              ),
              children: <Widget>[
                for (final ModerationTab tab in ModerationTab.values) ...<Widget>[
                  if (tab != ModerationTab.values.first) const SizedBox(width: 8),
                  TabPill(
                    label: tab.label,
                    selected: _tab == tab,
                    onTap: () => _selectTab(tab),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),

          // ---------- Danh sách ----------
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading && _items.isEmpty) return const ListSkeleton();

    if (_error != null) {
      return ErrorState(message: _errorMessage(_error!), onRetry: () => _load(reset: true));
    }

    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.fact_check_outlined,
        title: _emptyTitle,
        message: _emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        // +1 cho dòng "Đang tải thêm" ở cuối.
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final AdminStory story = _items[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                onTap: () => _openDetail(story),
                leading: _Cover(url: story.coverUrl),
                title: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        story.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ModerationChip(
                      status: story.moderationStatus,
                      needsRecheck: story.needsRecheck,
                    ),
                  ],
                ),
                subtitle: Text(
                  <String>[
                    story.author,
                    story.chapterLabel,
                    _submittedLabel(story.submittedAt),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          );
        },
      ),
    );
  }

  String get _emptyTitle => switch (_tab) {
    ModerationTab.pending => 'Không có truyện chờ duyệt',
    ModerationTab.approved => 'Chưa có truyện nào được duyệt',
    ModerationTab.rejected => 'Không có truyện bị từ chối',
    ModerationTab.recheck => 'Không có truyện cần xem lại',
  };

  String? get _emptyMessage => switch (_tab) {
    ModerationTab.pending => 'Truyện mới gửi duyệt sẽ xuất hiện ở đây.',
    ModerationTab.recheck => 'Truyện đã duyệt mà tác giả sửa chương sẽ hiện ở đây.',
    _ => 'Chưa có truyện nào ở trạng thái này.',
  };

  /// "12/10/2026 08:30" — null → "Chưa gửi duyệt".
  static String _submittedLabel(DateTime? at) {
    if (at == null) return 'Chưa gửi duyệt';
    final DateTime t = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'gửi ${two(t.hour)}:${two(t.minute)} '
        '${two(t.day)}/${two(t.month)}/${t.year}';
  }
}

/// Ảnh bìa nhỏ của thẻ kiểm duyệt (không có → khung icon theo theme).
class _Cover extends StatelessWidget {
  const _Cover({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String src = (url ?? '').trim();

    if (src.isEmpty) {
      return _frame(
        theme,
        child: Icon(Icons.menu_book_outlined, color: theme.colorScheme.primary),
      );
    }
    return _frame(
      theme,
      child: Image.network(
        src,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Icon(Icons.menu_book_outlined, color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _frame(ThemeData theme, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 60,
        alignment: Alignment.center,
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        child: child,
      ),
    );
  }
}
