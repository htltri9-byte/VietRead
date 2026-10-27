import 'package:flutter/material.dart';

import '../models/genre.dart';
import '../models/story.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Form tạo / sửa thông tin truyện — A3.9 (Bước 9).
///
/// - `story == null` → tạo mới (POST /stories),
/// - `story != null` → sửa (PUT /stories/{id}); pop trả về `Story` đã lưu.
class StoryFormScreen extends StatefulWidget {
  const StoryFormScreen({super.key, this.api, this.story});

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  /// Truyện cần sửa; `null` = tạo mới.
  final Story? story;

  @override
  State<StoryFormScreen> createState() => _StoryFormScreenState();
}

class _StoryFormScreenState extends State<StoryFormScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _cover;

  /// Tác giả nguyên tác — không bắt buộc; rỗng thì backend lưu NULL.
  late final TextEditingController _originalAuthor;

  /// Thể loại server trả về + thể loại người dùng tự nhập (chưa có server tự tạo).
  List<Genre> _allGenres = <Genre>[];
  final Set<String> _selectedGenres = <String>{};

  String _status = 'ongoing';
  bool _isDraft = true;
  bool _saving = false;
  bool _titleError = false;

  @override
  void initState() {
    super.initState();
    final Story? story = widget.story;
    _title = TextEditingController(text: story?.title ?? '');
    _description = TextEditingController(text: story?.description ?? '');
    _cover = TextEditingController(text: story?.coverUrl ?? '');
    // Truyện nhập từ link đã có sẵn tác giả từ nguồn → điền sẵn, vẫn sửa được.
    _originalAuthor = TextEditingController(text: story?.originalAuthor ?? '');
    if (story != null) {
      _status = story.status;
      _isDraft = story.isDraft;
      _selectedGenres.addAll(story.genres);
    }
    _loadGenres();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _cover.dispose();
    _originalAuthor.dispose();
    super.dispose();
  }

  /// Nạp danh sách thể loại để vẽ chip chọn — lỗi mạng thì bỏ qua
  /// (vẫn nhập thể loại mới tay được).
  Future<void> _loadGenres() async {
    try {
      _api.setToken(AuthService.instance.session?.token);
      final List<Genre> genres = await _api.fetchGenres();
      if (mounted) setState(() => _allGenres = genres);
    } catch (_) {
      // Giữ danh sách rỗng — chip thể loại tự nhập vẫn dùng được.
    }
  }

  /// Hộp thoại nhập tên thể loại mới (backend tự tạo thể loại khi chưa có).
  Future<void> _addGenre() async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        final TextEditingController ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Thêm thể loại'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên thể loại'),
            onSubmitted: (String v) => Navigator.of(ctx).pop(v),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Thêm'),
            ),
          ],
        );
      },
    );
    final String clean = (name ?? '').trim();
    if (clean.isNotEmpty && mounted) {
      setState(() => _selectedGenres.add(clean));
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Lưu — validate tên rồi gọi POST/PUT; pop trả `Story` đã lưu.
  Future<void> _save() async {
    if (_saving) return;
    final String title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true); // lỗi ngay trên ô tên
      return;
    }
    setState(() {
      _saving = true;
      _titleError = false;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final Story saved;
      if (widget.story == null) {
        saved = await _api.createStory(
          title: title,
          description: _description.text,
          coverUrl: _cover.text,
          status: _status,
          genres: _selectedGenres.toList(),
          isDraft: _isDraft,
          originalAuthor: _originalAuthor.text,
        );
      } else {
        saved = await _api.updateStory(
          widget.story!.id,
          title: title,
          description: _description.text,
          coverUrl: _cover.text,
          status: _status,
          genres: _selectedGenres.toList(),
          isDraft: _isDraft,
          originalAuthor: _originalAuthor.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(e is ApiException ? e.message : 'Không lưu được truyện.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isEdit = widget.story != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Sửa truyện' : 'Truyện mới'),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Lưu'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          // ---------- Tên truyện ----------
          TextField(
            controller: _title,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Tên truyện *',
              errorText: _titleError ? 'Tên truyện không được để trống' : null,
            ),
            onChanged: (_) {
              if (_titleError) setState(() => _titleError = false);
            },
          ),
          const SizedBox(height: 12),

          // ---------- Mô tả ----------
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Mô tả',
              hintText: 'Giới thiệu ngắn về tác phẩm...',
            ),
          ),
          const SizedBox(height: 12),

          // ---------- Ảnh bìa ----------
          TextField(
            controller: _cover,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Ảnh bìa (URL)',
              hintText: 'https://...',
            ),
          ),
          // ---------- Tác giả (nguyên tác) ----------
          TextField(
            controller: _originalAuthor,
            textInputAction: TextInputAction.next,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'Tác giả (nguyên tác)',
              hintText: 'Tên tác giả gốc của truyện...',
              helperText:
                  'Tên tác giả gốc của truyện. Nếu bạn tự sáng tác, hãy ghi tên bút danh của bạn.',
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final String? name = AuthService.instance.user?.name;
                if (name == null || name.trim().isEmpty) return;
                setState(() => _originalAuthor.text = name.trim());
              },
              icon: const Icon(Icons.person_outline_rounded, size: 18),
              label: const Text('Dùng tên tài khoản của tôi'),
            ),
          ),
          const SizedBox(height: 8),

          // ---------- Trạng thái ----------
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'ongoing',
                label: Text('Đang ra'),
                icon: Icon(Icons.timelapse_rounded, size: 18),
              ),
              ButtonSegment<String>(
                value: 'completed',
                label: Text('Hoàn thành'),
                icon: Icon(Icons.check_circle_outline_rounded, size: 18),
              ),
            ],
            selected: <String>{_status},
            onSelectionChanged: (Set<String> v) =>
                setState(() => _status = v.first),
          ),
          const SizedBox(height: 16),

          // ---------- Thể loại ----------
          Text('Thể loại', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Genre g in _allGenres)
                FilterChip(
                  label: Text(g.name),
                  selected: _selectedGenres.contains(g.name),
                  onSelected: (bool on) {
                    setState(() {
                      if (on) {
                        _selectedGenres.add(g.name);
                      } else {
                        _selectedGenres.remove(g.name);
                      }
                    });
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Thêm'),
                onPressed: _addGenre,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ---------- Lưu như nháp ----------
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lưu làm nháp'),              subtitle: Text(
                'Nháp chỉ mình bạn thấy; bấm "Gửi duyệt" ở danh sách truyện '
                'để gửi Admin xét duyệt.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            value: _isDraft,
            onChanged: (bool v) => setState(() => _isDraft = v),
          ),
        ],
      ),
    );
  }
}
