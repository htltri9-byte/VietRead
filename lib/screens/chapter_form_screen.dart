import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/alternatives.dart';
import '../utils/marker_text_controller.dart';
import '../widgets/chapter_form_dialogs.dart';
import '../widgets/error_state.dart';
import '../widgets/marker_picker_sheet.dart';
import '../widgets/marker_tool_bar.dart';

/// Form thêm / sửa chương — A3.9 (Bước 9).
///
/// - `chapter == null` → thêm mới (POST /stories/{id}/chapters);
/// - `chapter != null` → sửa (PUT /chapters/{id}); cần tải nội dung trước
///   vì danh sách chỉ trả `ChapterSummary` (không có content).
///
/// Khi sửa, tải bản **thô** (`?raw=1`) để thấy marker nhiều nghĩa `{a|b}`;
/// chọn nghĩa xong marker được thay bằng đúng nghĩa đó rồi mới Lưu.
/// Người đọc chỉ thấy nghĩa đầu (backend resolve trước khi trả).
///
/// Giao diện tách thành phần riêng: [MarkerEditingController] (tô sáng
/// marker trong ô nội dung), [MarkerToolBar] (thanh công cụ chọn nghĩa),
/// các dialog trong `widgets/chapter_form_dialogs.dart` và
/// [MarkerPickerSheet] — State này giữ toàn bộ logic chọn nghĩa / lưu.
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
  late final MarkerEditingController _content;

  /// Đang tải nội dung chương khi sửa (chưa xong chưa hiện form).
  bool _loading = true;
  Object? _error;
  bool _saving = false;
  bool _retranslating = false;
  bool _titleError = false;
  bool _contentError = false;

  /// Số chỗ nhiều nghĩa còn lại — chỉ setState khi số này đổi (gõ trơn).
  int _markerCount = 0;

  /// Chỗ đã ghi nghĩa gần nhất, còn dùng khi sheet đang mở — cho phép đổi ý
  /// chọn nghĩa khác khi KHÔNG bật “Tự chuyển sang chỗ tiếp theo”
  /// (marker đã bị thay khỏi văn bản nên không parse lại được nữa).
  ({int start, String text})? _applied;

  bool get _isEdit => widget.chapter != null;

  @override
  void initState() {
    super.initState();
    _index = TextEditingController(
      text: _isEdit ? '${widget.chapter!.index}' : '',
    );
    _title = TextEditingController(text: widget.chapter?.title ?? '');
    _content = MarkerEditingController();
    _content.addListener(_onContentChanged);
    if (_isEdit) {
      _loadChapter();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _content.removeListener(_onContentChanged);
    _index.dispose();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  /// Chỉ cập nhật nhãn "Còn N chỗ" khi số marker đổi → gõ không bị giật.
  void _onContentChanged() {
    final int count = countMarkers(_content.text);
    if (count == _markerCount) return;
    if (!mounted) {
      _markerCount = count;
      return;
    }
    setState(() => _markerCount = count);
  }

  /// Sửa chương → GET /chapters/{id}?raw=1 lấy bản thô (kèm marker nhiều nghĩa).
  Future<void> _loadChapter() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final Chapter chapter = await _api.fetchChapter(
        widget.chapter!.id,
        raw: true,
      );
      if (!mounted) return;
      setState(() {
        _title.text = chapter.title;
        _content.text = chapter.content;
        _markerCount = countMarkers(chapter.content);
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

  // ------------------------- Chọn nghĩa (marker) -------------------------

  /// Chạm vào ô nội dung → nếu trúng marker thì mở sheet chọn nghĩa.
  void _handleContentTap() {
    final int offset = _content.selection.baseOffset;
    if (offset < 0) return;
    final Marker? marker = markerAt(_content.text, offset);
    if (marker != null) _openMarkerSheet(marker);
  }

  /// Nút "Duyệt nghĩa": nhảy marker kế tiếp (vòng vòng) rồi mở sheet.
  void _browseMarkers() {
    final List<Marker> markers = parseMarkers(_content.text);
    if (markers.isEmpty) return;
    final int cursor = _content.selection.baseOffset;
    Marker? next;
    for (final Marker m in markers) {
      if (m.start >= cursor) {
        next = m;
        break;
      }
    }
    next ??= markers.first;
    _content.selection = TextSelection.collapsed(offset: next.start);
    _openMarkerSheet(next);
  }

  /// Marker kế tiếp / trước đó quanh [marker] (vòng vòng theo danh sách).
  /// Quay sang chỗ khác → quên mốc đã ghi ([_applied]) — chỗ mới là marker thật.
  Marker? _neighborMarker(Marker marker, {required bool forward}) {
    _applied = null;
    final List<Marker> markers = parseMarkers(_content.text);
    if (markers.isEmpty) return null;
    int idx = markers.indexWhere(
      (Marker m) => m.start == marker.start && m.end == marker.end,
    );
    if (idx < 0) {
      idx = markers.indexWhere((Marker m) => m.start >= marker.start);
    }
    if (idx < 0) idx = markers.length - 1;
    final int next = forward ? idx + 1 : idx - 1;
    return markers[(next + markers.length) % markers.length];
  }

  /// Vị trí hiện tại của marker đang mở: (index 0-based, tổng số chỗ).
  /// Marker đã bị ghi thành nghĩa thuần (không tự chuyển) → vẫn cho biết chỗ
  /// đó đứng thứ mấy tính từ đầu chương.
  ({int index, int total})? _markerPosition(Marker marker) {
    final List<Marker> markers = parseMarkers(_content.text);
    if (markers.isEmpty) return null;
    final int live = markers.indexWhere(
      (Marker m) => m.start == marker.start && m.end == marker.end,
    );
    if (live >= 0) return (index: live, total: markers.length);
    final ({int start, String text})? applied = _applied;
    if (applied != null) {
      final int before = markers
          .where((Marker m) => m.start < applied.start)
          .length;
      return (
        index: before.clamp(0, markers.length - 1),
        total: markers.length,
      );
    }
    return null;
  }

  /// Ranh giới [marker] trong văn bản LIVE: còn nguyên → đúng vị trí; đã bị
  /// ghi thành nghĩa → span của nghĩa đó (ngữ cảnh trong sheet đúng chỗ).
  ({int start, int end}) _markerBounds(Marker marker) {
    final String text = _content.text;
    final List<Marker> markers = parseMarkers(text);
    for (final Marker m in markers) {
      if (m.start == marker.start && m.end == marker.end) {
        return (start: m.start, end: m.end);
      }
    }
    final ({int start, String text})? applied = _applied;
    if (applied != null &&
        applied.start <= text.length &&
        applied.start + applied.text.length <= text.length &&
        text.substring(applied.start, applied.start + applied.text.length) ==
            applied.text) {
      return (start: applied.start, end: applied.start + applied.text.length);
    }
    return (
      start: marker.start.clamp(0, text.length),
      end: marker.end.clamp(0, text.length),
    );
  }

  Future<void> _openMarkerSheet(Marker marker) async {
    _applied = null; // mở sheet mới → quên mốc đã ghi trước đó
    final ValueNotifier<Marker> current = ValueNotifier<Marker>(marker);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext ctx) => MarkerPickerSheet(
          current: current,
          textOf: () => _content.text,
          positionOf: _markerPosition,
          boundsOf: _markerBounds,
          // Các thao tác KHÔNG đóng sheet — sheet tự quyết định đóng/không
          // dựa trên số marker còn lại + công tắc “Tự chuyển sang chỗ tiếp theo”.
          onPick: (Marker target, String meaning, bool applyAll) {
            _applyMeaning(target, meaning, applyAll: applyAll);
            return parseMarkers(_content.text).isNotEmpty;
          },
          onNavigate: (bool forward) {
            final Marker? next = _neighborMarker(
              current.value,
              forward: forward,
            );
            if (next != null) current.value = next;
            return next != null;
          },
          onClose: () {
            if (mounted) Navigator.of(ctx).pop();
          },
        ),
      );
    } finally {
      current.dispose();
    }
  }

  /// Thay marker bằng nghĩa đã chọn (bỏ dấu `{}`).
  /// [applyAll] = thay mọi marker có **cùng danh sách nghĩa**.
  ///
  /// Trả về `true` nếu SAU khi thay vẫn còn marker trong ô nội dung (sheet
  /// dùng để quyết định đóng hay tự chuyển chỗ tiếp theo). Nếu marker đã bị
  /// thay trước đó (đổi ý khi không bật tự chuyển) → thay tại đúng chỗ đã ghi.
  bool _applyMeaning(Marker marker, String meaning, {bool applyAll = false}) {
    final String text = _content.text;
    if (marker.end <= text.length) {
      final List<Marker> markers = parseMarkers(text);
      final bool live = markers.any(
        (Marker m) => m.start == marker.start && m.end == marker.end,
      );
      if (live) {
        final StringBuffer buf = StringBuffer();
        int pos = 0;
        int firstStart = -1;
        for (final Marker m in markers) {
          final bool hit = applyAll
              ? listEquals(m.meanings, marker.meanings)
              : (m.start == marker.start && m.end == marker.end);
          if (!hit) continue;
          if (firstStart < 0) firstStart = m.start;
          buf.write(text.substring(pos, m.start));
          buf.write(meaning);
          pos = m.end;
        }
        if (firstStart >= 0) {
          buf.write(text.substring(pos));
          _content.text = buf.toString();
          _content.selection = TextSelection.collapsed(
            offset: (firstStart + meaning.length).clamp(
              0,
              _content.text.length,
            ),
          );
          _applied = (start: firstStart, text: meaning);
          return parseMarkers(_content.text).isNotEmpty;
        }
      }
    }
    // Đã ghi trước đó (đổi ý lần 2 khi sheet vẫn mở) → thay đúng span đã ghi
    final ({int start, String text})? applied = _applied;
    if (applied != null &&
        applied.start <= text.length &&
        applied.start + applied.text.length <= text.length &&
        text.substring(applied.start, applied.start + applied.text.length) ==
            applied.text) {
      final String updated = text.replaceRange(
        applied.start,
        applied.start + applied.text.length,
        meaning,
      );
      _content.text = updated;
      _content.selection = TextSelection.collapsed(
        offset: (applied.start + meaning.length).clamp(0, updated.length),
      );
      _applied = (start: applied.start, text: meaning);
      return parseMarkers(updated).isNotEmpty;
    }
    return parseMarkers(_content.text).isNotEmpty;
  }

  /// "Lấy nghĩa đầu cho tất cả" — hỏi xác nhận rồi bỏ toàn bộ marker.
  Future<void> _resolveAllConfirm() async {
    if (_markerCount == 0) return;
    final bool ok = await showResolveAllConfirmDialog(
      context,
      markerCount: _markerCount,
    );
    if (!ok || !mounted) return;
    setState(() => _content.text = resolveMarkers(_content.text));
  }

  /// "Dịch lại có gợi ý nghĩa" — gọi /retranslate, KHÔNG tự lưu.
  Future<void> _retranslate() async {
    if (!_isEdit || _saving || _retranslating) return;
    final String? level = await showRetranslateDialog(context);
    if (level == null || !mounted) return;
    setState(() => _retranslating = true);
    try {
      _api.setToken(AuthService.instance.session?.token);
      final String newContent = await _api.retranslateChapter(
        widget.chapter!.id,
        markLevel: level,
      );
      if (!mounted) return;
      setState(() {
        _content.text = newContent;
        _markerCount = countMarkers(newContent);
        _retranslating = false;
      });
      _showMessage('Đã dịch lại — chọn nghĩa rồi bấm Lưu để lưu.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _retranslating = false);
      _showMessage(
        e is ApiException ? e.message : 'Không dịch lại được chương.',
      );
    }
  }

  // ------------------------- Lưu -------------------------

  /// Lưu — validate rồi POST/PUT; pop về màn quản lý để nạp lại.
  Future<void> _save() async {
    if (_saving) return;
    final String title = _title.text.trim();
    String content = _content.text;
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

    // Còn marker chưa chọn nghĩa → hỏi người dùng.
    final int remaining = countMarkers(content);
    if (remaining > 0) {
      final RemainingMarkersAction? choice = await showRemainingMarkersDialog(
        context,
        remaining: remaining,
      );
      if (choice == null || !mounted) return;
      if (choice == RemainingMarkersAction.resolveFirst) {
        content = resolveMarkers(content);
        _content.text = content;
      }
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
    // Toolbar chỉ hiện khi có marker hoặc đang sửa chương.
    final bool showTools = _isEdit || _markerCount > 0;

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
                if (showTools) ...<Widget>[
                  const SizedBox(height: 12),
                  // ---------- Thanh công cụ chọn nghĩa ----------
                  MarkerToolBar(
                    markerCount: _markerCount,
                    isEdit: _isEdit,
                    retranslating: _retranslating,
                    onBrowse: _browseMarkers,
                    onResolveAll: _resolveAllConfirm,
                    onRetranslate: _retranslate,
                  ),
                ],
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
                    helperText: _markerCount > 0
                        ? 'Chạm vào chỗ {nghĩa1|nghĩa2} để chọn nghĩa.'
                        : null,
                  ),
                  onTap: _handleContentTap,
                  onChanged: (_) {
                    if (_contentError) setState(() => _contentError = false);
                  },
                ),
              ],
            ),
    );
  }
}
