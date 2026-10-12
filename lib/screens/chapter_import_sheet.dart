import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Mở bottom sheet **Thêm chương** — trả `true` khi thêm thành công
/// (caller nạp lại danh sách chương + báo SnackBar).
Future<bool?> showChapterImportSheet(
  BuildContext context, {
  required ApiService api,
  required int storyId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext ctx) => Padding(
      // Không để bàn phím che form khi đang gõ.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: ChapterImportSheet(api: api, storyId: storyId),
    ),
  );
}

/// Bottom sheet thêm chương vào truyện đã có — A3.11:
///
/// - Tab **Dán link**: link chương Qidian + số chương (tuỳ chọn) →
///   `POST /stories/{id}/chapters/import` (backend cào + dịch).
/// - Tab **Dán văn bản**: nội dung + ngôn ngữ nguồn (Trung/Việt) →
///   `POST /stories/{id}/chapters/import-text`.
///
/// Validate link ngay trên ô; lỗi backend hiện đúng message kèm nút
/// **Thử lại**; đang xử lý thì vô hiệu hoá nút (không bấm trùng).
class ChapterImportSheet extends StatefulWidget {
  const ChapterImportSheet({super.key, required this.api, required this.storyId});

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService api;

  final int storyId;

  @override
  State<ChapterImportSheet> createState() => _ChapterImportSheetState();
}

class _ChapterImportSheetState extends State<ChapterImportSheet> {
  static const String _modeLink = 'link';
  static const String _modeText = 'text';

  final TextEditingController _url = TextEditingController();
  final TextEditingController _chapterNo = TextEditingController();
  final TextEditingController _text = TextEditingController();

  String _mode = _modeLink;
  String _sourceLang = 'zh'; // khớp mặc định của backend
  bool _busy = false;

  String? _urlError; // validate ngay trên ô link
  String? _chapterNoError;
  String? _textError;
  String? _submitError; // lỗi backend (trùng chương, VIP, nguồn chặn…)

  /// Người dùng bấm chọn tay ngôn ngữ → không auto-đổi nữa (không "đánh lừa").
  bool _langPinned = false;

  /// Chữ Trung (CJK Unified + Extension A + Compatibility) — dán trúng thì tự
  /// chọn "Trung" để backend dịch sang tiếng Việt.
  static final RegExp _cjkPattern = RegExp(
    r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]',
  );

  /// Tự nhận diện ngôn ngữ mỗi lần nội dung đổi: có chữ Trung → 'zh' (dịch),
  /// không có → 'vi' (lưu nguyên). Bỏ qua khi người dùng đã chọn tay.
  void _syncLangFromText() {
    if (_langPinned) return;
    final String text = _text.text;
    if (text.trim().isEmpty) return;
    final String detected = _cjkPattern.hasMatch(text) ? 'zh' : 'vi';
    if (detected != _sourceLang) setState(() => _sourceLang = detected);
  }

  @override
  void dispose() {
    _url.dispose();
    _chapterNo.dispose();
    _text.dispose();
    super.dispose();
  }

  String _messageOf(Object error) => error is ApiException
      ? error.message
      : 'Không thêm được chương. Vui lòng thử lại.';

  Future<void> _submit() async {
    if (_busy) return;

    if (_mode == _modeLink) {
      final String url = _url.text.trim();
      if (url.isEmpty) {
        setState(() => _urlError = 'Vui lòng dán link chương Qidian');
        return;
      }
      final Uri? uri = Uri.tryParse(url);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        setState(() => _urlError = 'Link không hợp lệ — cần http(s) đầy đủ');
        return;
      }
      final String host = uri.host.toLowerCase();
      if (host != 'qidian.com' && !host.endsWith('.qidian.com')) {
        setState(() => _urlError = 'Chỉ hỗ trợ thêm chương từ Qidian');
        return;
      }
      int? chapterNo;
      final String rawNo = _chapterNo.text.trim();
      if (rawNo.isNotEmpty) {
        chapterNo = int.tryParse(rawNo);
        if (chapterNo == null || chapterNo < 1) {
          setState(() => _chapterNoError = 'Số chương phải là số nguyên ≥ 1');
          return;
        }
      }
      setState(() {
        _busy = true;
        _urlError = null;
        _chapterNoError = null;
        _submitError = null;
      });
      try {
        widget.api.setToken(AuthService.instance.session?.token);
        await widget.api.importChapterFromUrl(
          widget.storyId,
          chapterUrl: url,
          chapterNo: chapterNo,
        );
        if (mounted) Navigator.of(context).pop(true);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _submitError = _messageOf(error);
        });
      }
      return;
    }

    // ---- Tab dán văn bản ----
    final String text = _text.text;
    if (text.trim().isEmpty) {
      setState(() => _textError = 'Vui lòng dán nội dung chương');
      return;
    }
    if (text.length > 100000) {
      setState(() => _textError = 'Nội dung chương tối đa 100.000 ký tự');
      return;
    }
    setState(() {
      _busy = true;
      _textError = null;
      _submitError = null;
    });
    try {
      widget.api.setToken(AuthService.instance.session?.token);
      await widget.api.importChapterFromText(
        widget.storyId,
        text: text,
        sourceLang: _sourceLang,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _submitError = _messageOf(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Thanh kéo của bottom sheet
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Thêm chương', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Dán link chương Qidian, hoặc dán văn bản khi không cào được.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),

          // ---- Chế độ: link / dán văn bản ----
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: _modeLink,
                label: Text('Dán link'),
                icon: Icon(Icons.link_rounded, size: 18),
              ),
              ButtonSegment<String>(
                value: _modeText,
                label: Text('Dán văn bản'),
                icon: Icon(Icons.notes_rounded, size: 18),
              ),
            ],
            selected: <String>{_mode},
            showSelectedIcon: false,
            onSelectionChanged: _busy
                ? null
                : (Set<String> selection) => setState(() {
                      _mode = selection.first;
                      _submitError = null;
                    }),
          ),
          const SizedBox(height: 16),

          if (_mode == _modeLink) ...<Widget>[
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Link chương Qidian *',
                hintText: 'https://m.qidian.com/chapter/123/456/',
                errorText: _urlError,
              ),
              onChanged: (_) {
                if (_urlError != null) setState(() => _urlError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _chapterNo,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Số chương (tuỳ chọn)',
                hintText: 'để trống = tự đánh số',
                errorText: _chapterNoError,
              ),
              onChanged: (_) {
                if (_chapterNoError != null) {
                  setState(() => _chapterNoError = null);
                }
              },
            ),
          ] else ...<Widget>[
            TextField(
              controller: _text,
              enabled: !_busy,
              minLines: 5,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: 'Nội dung chương *',
                hintText: 'Dán nội dung chương vào đây...',
                errorText: _textError,
              ),
              onChanged: (_) {
                if (_textError != null) setState(() => _textError = null);
                _syncLangFromText(); // dán tiếng Trung → tự chọn "Trung"
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'zh', label: Text('Trung')),
                ButtonSegment<String>(value: 'vi', label: Text('Việt')),
              ],
              selected: <String>{_sourceLang},
              showSelectedIcon: false,
              onSelectionChanged: _busy
                  ? null
                  : (Set<String> selection) => setState(() {
                        _sourceLang = selection.first;
                        _langPinned = true; // chọn tay → giữ nguyên
                      }),
            ),
            const SizedBox(height: 4),
            Text(
              _sourceLang == 'zh'
                  ? 'Văn bản tiếng Trung sẽ được dịch sang tiếng Việt.'
                  : 'Văn bản tiếng Việt được lưu nguyên, không dịch.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Text(
              'Ngôn ngữ tự nhận diện theo nội dung dán — vẫn đổi được bằng cách '
              'bấm chọn.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],

          // ---- Lỗi backend → hiện đúng message + nút Thử lại ----
          if (_submitError != null) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    _submitError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded, size: 18),
            label: const Text('Thêm'),
          ),
        ],
      ),
    );
  }
}
