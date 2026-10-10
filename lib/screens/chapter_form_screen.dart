import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/error_state.dart';

/// Form thêm / sửa chương — A3.9 (Bước 9).
///
/// - `chapter == null` → thêm mới (POST /stories/{id}/chapters);
/// - `chapter != null` → sửa (PUT /chapters/{id}); cần tải nội dung trước
///   vì danh sách chỉ trả `ChapterSummary` (không có content).
class ChapterFormScreen extends StatefulWidget {
  const ChapterFormScreen({
    super.key,
    this.api,
    required this.storyId,
    this.chapter,
  });

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  final int storyId;

  /// Chương cần sửa; `null` = thêm mới.
  final ChapterSummary? chapter;

  @override
  State<ChapterFormScreen> createState() => _ChapterFormScreenState();
}

class _ChapterFormScreenState extends State<ChapterFormScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  late final TextEditingController _index;
  late final TextEditingController _title;
  late final TextEditingController _content;

  /// Đang tải nội dung chương khi sửa (chưa xong chưa hiện form).
  bool _loading = true;
  Object? _error;
  bool _saving = false;
  bool _titleError = false;
  bool _contentError = false;

  bool get _isEdit => widget.chapter != null;

  @override
  void initState() {
    super.initState();
    _index = TextEditingController(
      text: _isEdit ? '${widget.chapter!.index}' : '',
    );
    _title = TextEditingController(text: widget.chapter?.title ?? '');
    _content = TextEditingController();
    if (_isEdit) {
      _loadChapter();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _index.dispose();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  /// Sửa chương → GET /chapters/{id} lấy nội dung đầy đủ.
  Future<void> _loadChapter() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final Chapter chapter = await _api.fetchChapter(widget.chapter!.id);
      if (!mounted) return;
      setState(() {
        _title.text = chapter.title;
        _content.text = chapter.content;
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

  /// Số chương từ ô nhập: rỗng → null (tự đánh số / giữ nguyên).
  int? get _parsedIndex {
    final String raw = _index.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Lưu — validate rồi POST/PUT; pop về màn quản lý để nạp lại.
  Future<void> _save() async {
    if (_saving) return;
    final String title = _title.text.trim();
    final String content = _content.text;
    bool bad = false;
    if (title.isEmpty) bad = true;
    if (content.trim().isEmpty) bad = true;
    if (_parsedIndex != null && _parsedIndex! < 1) bad = true;
    if (bad) {
      setState(() {
        _titleError = title.isEmpty;
        _contentError = content.trim().isEmpty;
      });
      if (_parsedIndex != null && _parsedIndex! < 1) {
        _showMessage('Số chương phải là số nguyên lớn hơn 0.');
      }
      return;
    }

    setState(() => _saving = true);
    try {
      _api.setToken(AuthService.instance.session?.token);
      if (!_isEdit) {
        await _api.createChapter(
          widget.storyId,
          title: title,
          content: content,
          index: _parsedIndex,
        );
      } else {
        await _api.updateChapter(
          widget.chapter!.id,
          title: title,
          content: content,
          index: _parsedIndex,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(e is ApiException ? e.message : 'Không lưu được chương.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa chương' : 'Chương mới'),
        actions: <Widget>[
          TextButton(
            onPressed: (_saving || _loading) ? null : _save,
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(
              message: _error is ApiException
                  ? (_error as ApiException).message
                  : 'Không tải được nội dung chương.',
              onRetry: _loadChapter,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                TextField(
                  controller: _index,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Số chương',
                    hintText: 'Để trống để tự đánh số tiếp',
                    errorText: (_parsedIndex != null && _parsedIndex! < 1)
                        ? 'Số chương phải lớn hơn 0'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Tên chương *',
                    errorText: _titleError
                        ? 'Tên chương không được để trống'
                        : null,
                  ),
                  onChanged: (_) {
                    if (_titleError) setState(() => _titleError = false);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _content,
                  minLines: 12,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: 'Nội dung chương *',
                    alignLabelWithHint: true,
                    errorText: _contentError
                        ? 'Nội dung chương không được để trống'
                        : null,
                  ),
                  onChanged: (_) {
                    if (_contentError) setState(() => _contentError = false);
                  },
                ),
              ],
            ),
    );
  }
}
