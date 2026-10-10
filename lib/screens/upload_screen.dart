import 'package:flutter/material.dart';

import '../models/story.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton.dart';
import 'auth_screen.dart';
import 'chapter_manager_screen.dart';
import 'import_screen.dart';
import 'story_form_screen.dart';

/// Tab **Đăng truyện** — CRUD truyện / chương của tác giả (A3.9, Bước 9).
///
/// - Chưa đăng nhập → lời mời đăng nhập.
/// - Danh sách lấy từ `GET /me/stories` (kể cả truyện nháp).
/// - Mỗi dòng có menu: Sửa thông tin, Quản lý chương,
///   Đăng công khai / Lưu làm nháp, Xoá truyện.
/// - Đồng bộ phiên đăng nhập qua [AuthService] (đăng nhập ở tab khác
///   quay về đây vẫn thấy danh sách của mình).
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, this.api});

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  List<Story> _stories = <Story>[];
  bool _loading = true;
  Object? _error;

  /// Id người dùng mà [_stories] hiện tại thuộc về (`null` = khách).
  int? _forUser;

  @override
  void initState() {
    super.initState();
    _syncUser();
  }

  int? get _currentUserId => AuthService.instance.session?.user.id;

  /// Đồng bộ danh sách với phiên đăng nhập hiện tại (giống LibraryScreen):
  /// đăng nhập / đăng xuất → nạp lại cho đúng người.
  void _syncUser() {
    final int? uid = _currentUserId;
    if (_forUser == uid) return;
    _forUser = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _forUser == uid) _load();
    });
  }

  Future<void> _load() async {
    final int? uid = _forUser;
    if (uid == null) {
      // Chưa đăng nhập → hiển thị lời mời (AnimatedBuilder tự xử lý).
      if (!mounted) return;
      setState(() {
        _stories = <Story>[];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final List<Story> list = await _api.fetchMyStories();
      if (!mounted || _forUser != uid) return;
      setState(() {
        _stories = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _forUser != uid) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AuthScreen()),
    );
    // AuthService.notifyListeners → builder tự gọi _syncUser.
  }

  // ------------------------- Thao tác CRUD -------------------------

  /// Tạo truyện mới → có kết quả thì nạp lại danh sách.
  Future<void> _createStory() async {
    final Story? saved = await Navigator.of(context).push<Story>(
      MaterialPageRoute<Story>(builder: (_) => StoryFormScreen(api: _api)),
    );
    if (saved != null && mounted) _load();
  }

  /// Sửa thông tin truyện → nạp lại (tên / thể loại / nháp đều đổi được).
  Future<void> _editStory(Story story) async {
    final Story? saved = await Navigator.of(context).push<Story>(
      MaterialPageRoute<Story>(
        builder: (_) => StoryFormScreen(api: _api, story: story),
      ),
    );
    if (saved != null && mounted) _load();
  }

  /// Nhập truyện từ link (A3.10) → quay về nạp lại (Bước 10):
  /// truyện nhập xong hiện trong danh sách này ở dạng nháp.
  Future<void> _openImport() async {
    final bool? imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => ImportScreen(api: _api)),
    );
    if (imported == true && mounted) _load();
  }

  /// Quản lý chương → quay về nạp lại (số chương đổi khi thêm/xoá).
  Future<void> _openChapters(Story story) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChapterManagerScreen(api: _api, story: story),
      ),
    );
    if (mounted) _load();
  }

  /// Đăng công khai (nháp → thật) hoặc lưu lại làm nháp (PUT isDraft).
  Future<void> _toggleDraft(Story story) async {
    try {
      _api.setToken(AuthService.instance.session?.token);
      await _api.updateStory(story.id, isDraft: !story.isDraft);
      _showMessage(
        story.isDraft
            ? 'Đã đăng "${story.title}" công khai.'
            : 'Đã chuyển "${story.title}" về nháp.',
      );
      _load();
    } catch (e) {
      _showMessage(e is ApiException ? e.message : 'Không cập nhật được truyện.');
    }
  }

  /// Xác nhận rồi xoá truyện (kèm chương / bình luận / theo dõi).
  Future<void> _confirmDelete(Story story) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Xoá "${story.title}"?'),
        content: const Text(
          'Toàn bộ chương, bình luận và theo dõi của truyện này sẽ bị xoá. '
          'Hành động này không hoàn tác.',
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
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      _api.setToken(AuthService.instance.session?.token);
      await _api.deleteStory(story.id);
      _showMessage('Đã xoá truyện.');
      _load();
    } catch (e) {
      _showMessage(e is ApiException ? e.message : 'Không xoá được truyện.');
    }
  }

  // ------------------------- Giao diện -------------------------

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (BuildContext context, _) {
        _syncUser(); // đăng nhập/đăng xuất → nạp lại danh sách
        final bool loggedIn = AuthService.instance.isLoggedIn;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Đăng truyện'),
            actions: <Widget>[
              IconButton(
                onPressed: _openImport,
                tooltip: 'Nhập truyện từ link',
                icon: const Icon(Icons.add_link_rounded),
              ),
            ],
          ),
          floatingActionButton: loggedIn
              ? FloatingActionButton.extended(
                  onPressed: _createStory,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Truyện mới'),
                )
              : null,
          body: loggedIn ? _body(theme) : _loginPrompt(),
        );
      },
    );
  }

  /// Chưa đăng nhập → lời mời + nút Đăng nhập (giống tab Theo dõi).
  Widget _loginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const EmptyState(
              icon: Icons.edit_note_outlined,
              title: 'Đăng nhập để đăng truyện',
              message:
                  'Tạo tác phẩm của riêng bạn: thêm chương, lưu nháp rồi đăng công khai.',
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

  Widget _body(ThemeData theme) {
    // Đang nạp lần đầu / của người dùng khác → skeleton (A2, Bước 11).
    if (_forUser != _currentUserId || (_loading && _stories.isEmpty)) {
      return const ListSkeleton();
    }

    if (_error != null) {
      return ErrorState(
        message: _error is ApiException
            ? (_error as ApiException).message
            : 'Không tải được danh sách truyện của bạn.',
        onRetry: _load,
      );
    }

    if (_stories.isEmpty) {
      return const EmptyState(
        icon: Icons.edit_note_outlined,
        title: 'Chưa có truyện nào',
        message: 'Bấm "Truyện mới" để đăng tác phẩm đầu tiên của bạn.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          for (final Story story in _stories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  onTap: () => _openChapters(story),
                  title: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          story.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (story.isDraft) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Nháp',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    <String>[
                      story.chapterLabel,
                      story.statusLabel,
                      story.updatedLabel,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Tuỳ chọn',
                    onSelected: (String action) {
                      if (action == 'edit') {
                        _editStory(story);
                      } else if (action == 'chapters') {
                        _openChapters(story);
                      } else if (action == 'publish') {
                        _toggleDraft(story);
                      } else {
                        _confirmDelete(story);
                      }
                    },
                    itemBuilder: (BuildContext menuContext) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Sửa thông tin'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'chapters',
                            child: ListTile(
                              leading: Icon(Icons.list_alt_outlined),
                              title: Text('Quản lý chương'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'publish',
                            child: ListTile(
                              leading: Icon(
                                story.isDraft
                                    ? Icons.publish_rounded
                                    : Icons.unpublished_outlined,
                              ),
                              title: Text(
                                story.isDraft
                                    ? 'Đăng công khai'
                                    : 'Chuyển về nháp',
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline_rounded),
                              title: Text('Xoá truyện'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
