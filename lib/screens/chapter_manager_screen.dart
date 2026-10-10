import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton.dart';
import 'chapter_form_screen.dart';
import 'story_form_screen.dart';

/// Quản lý chương của một truyện — A3.9 (Bước 9).
///
/// Danh sách chương (thêm / sửa / xoá) + lối vào sửa thông tin truyện.
/// Mọi thao tác pop về sẽ nạp lại để hiển thị số chương mới nhất.
class ChapterManagerScreen extends StatefulWidget {
  const ChapterManagerScreen({
    super.key,
    this.api,
    required this.story,
  });

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  /// Truyện được quản lý (chỉ tác giả mới vào được — backend chặn ở API).
  final Story story;

  @override
  State<ChapterManagerScreen> createState() => _ChapterManagerScreenState();
}

class _ChapterManagerScreenState extends State<ChapterManagerScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  /// Thông tin truyện hiện tại (nạp lại sau khi sửa thông tin / thêm chương).
  late Story _story = widget.story;
  List<ChapterSummary> _chapters = <ChapterSummary>[];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Nạp thông tin truyện + toàn bộ chương (pageSize 200 = đủ với giới hạn backend).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final Story story = await _api.fetchStory(_story.id);
      final List<ChapterSummary> chapters = await _api.fetchChapters(
        _story.id,
        pageSize: 200,
      );
      if (!mounted) return;
      setState(() {
        _story = story;
        _chapters = chapters;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  /// 'Chương N: Tên' — tránh lặp tiền đề khi tên chương đã sẵn 'Chương N...'.
  String _chapterLabel(ChapterSummary c) {
    final String prefix = 'Chương ${c.index}';
    if (c.title.startsWith(prefix)) return c.title;
    return c.title.isEmpty ? prefix : '$prefix: ${c.title}';
  }

  /// Thêm chương mới → quay về nạp lại.
  Future<void> _addChapter() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChapterFormScreen(api: _api, storyId: _story.id),
      ),
    );
    if (mounted) _load();
  }

  /// Sửa chương → quay về nạp lại.
  Future<void> _editChapter(ChapterSummary chapter) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            ChapterFormScreen(api: _api, storyId: _story.id, chapter: chapter),
      ),
    );
    if (mounted) _load();
  }

  /// Xác nhận rồi xoá chương.
  Future<void> _confirmDelete(ChapterSummary chapter) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Xoá "Chương ${chapter.index}"?'),
        content: const Text(
          'Nội dung chương và bình luận của chương này sẽ bị xoá. '
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
      await _api.deleteChapter(chapter.id);
      _showMessage('Đã xoá chương.');
      _load();
    } catch (e) {
      _showMessage(e is ApiException ? e.message : 'Không xoá được chương.');
    }
  }

  /// Sửa thông tin truyện → quay về nạp lại (tên / thể loại / trạng thái đổi).
  Future<void> _editStory() async {
    await Navigator.of(context).push<Story>(
      MaterialPageRoute<Story>(
        builder: (_) => StoryFormScreen(api: _api, story: _story),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý chương'),
        actions: <Widget>[
          IconButton(
            onPressed: _editStory,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Sửa thông tin truyện',
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addChapter,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Chương mới'),
            ),
      body: _loading
          ? const ListSkeleton(rows: 6)
          : _error != null
          ? ErrorState(
              message: _error is ApiException
                  ? (_error as ApiException).message
                  : 'Không tải được danh sách chương.',
              onRetry: _load,
            )
          : Column(
              children: <Widget>[
                // ---------- Header: tên truyện + trạng thái ----------
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(
                        Icons.menu_book_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        _story.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        <String>[
                          if (_story.isDraft) 'Nháp',
                          _story.statusLabel,
                          _story.chapterLabel,
                        ].join(' · '),
                      ),
                    ),
                  ),
                ),

                // ---------- Danh sách chương ----------
                Expanded(
                  child: _chapters.isEmpty
                      ? const EmptyState(
                          icon: Icons.article_outlined,
                          title: 'Chưa có chương nào',
                          message:
                              'Bấm "Chương mới" để thêm chương đầu tiên của truyện.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: _chapters.length,
                          itemBuilder: (BuildContext context, int i) {
                            final ChapterSummary chapter = _chapters[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                child: ListTile(
                                  onTap: () => _editChapter(chapter),
                                  title: Text(
                                    _chapterLabel(chapter),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    tooltip: 'Tuỳ chọn',
                                    onSelected: (String action) {
                                      if (action == 'edit') {
                                        _editChapter(chapter);
                                      } else {
                                        _confirmDelete(chapter);
                                      }
                                    },
                                    itemBuilder: (BuildContext menuContext) =>
                                        const <PopupMenuEntry<String>>[
                                          PopupMenuItem<String>(
                                            value: 'edit',
                                            child: ListTile(
                                              leading:
                                                  Icon(Icons.edit_outlined),
                                              title: Text('Sửa chương'),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'delete',
                                            child: ListTile(
                                              leading: Icon(
                                                Icons.delete_outline_rounded,
                                              ),
                                              title: Text('Xoá chương'),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
