import 'package:flutter/material.dart';

import '../models/glossary.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Màn "Tìm & thay thế" theo truyện (A3.11).
///
/// Chỉ chủ truyện dùng được (backend trả 403 nếu không phải tác giả).
/// Thay trong bản dịch của MỌI chương thuộc truyện — không đụng bản gốc
/// `OriginalContent`, không đụng truyện khác hay từ điển chung.
///
/// Flow: nhập A/B → **Xem trước** (dryRun) → xác nhận → thay thật →
/// báo số chỗ/chương + nút **Hoàn tác** (undo batch gần nhất).
/// Quy tắc "Áp dụng cho chương thêm sau này" được lưu trong `StoryGlossary`.
class ReplaceScreen extends StatefulWidget {
  const ReplaceScreen({super.key, this.api, required this.storyId});

  /// Tiêm nguồn dữ liệu (test dùng mock, app thật dùng HTTP).
  final ApiService? api;

  final int storyId;

  @override
  State<ReplaceScreen> createState() => _ReplaceScreenState();
}

class _ReplaceScreenState extends State<ReplaceScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();

  bool _matchCase = false;
  bool _wholeWord = false;
  bool _includeTitles = false;
  bool _applyToFuture = false;

  bool _previewing = false;
  bool _busy = false;

  /// Kết quả xem trước (dryRun) — nút "Thay ngay" chỉ bật khi có.
  ReplaceResult? _preview;

  /// Kết quả thay thật gần nhất — kèm batchId cho undo.
  ReplaceResult? _lastRun;

  /// Kết quả hoàn tác gần nhất.
  UndoResult? _lastUndo;

  List<GlossaryRule> _rules = <GlossaryRule>[];
  bool _loadingRules = true;
  Object? _rulesError;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Nhập liệu đổi → kết quả xem trước cũ không còn đúng.
  void _invalidate() {
    if (_preview != null || _lastRun != null) {
      setState(() {
        _preview = null;
        _lastRun = null;
        _lastUndo = null;
      });
    }
  }

  Future<void> _loadRules() async {
    setState(() {
      _loadingRules = true;
      _rulesError = null;
    });
    try {
      _api.setToken(AuthService.instance.session?.token);
      final List<GlossaryRule> rules = await _api.fetchGlossary(widget.storyId);
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loadingRules = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rulesError = e;
        _loadingRules = false;
      });
    }
  }

  /// Gọi backend — `?dryRun` chỉ đếm, không ghi.
  Future<ReplaceResult> _call({required bool dryRun}) {
    _api.setToken(AuthService.instance.session?.token);
    return _api.replaceInStory(
      widget.storyId,
      find: _find.text,
      replace: _replace.text,
      matchCase: _matchCase,
      wholeWord: _wholeWord,
      includeTitles: _includeTitles,
      applyToFuture: _applyToFuture,
      dryRun: dryRun,
    );
  }

  /// Xem trước — dryRun, hiện "Tìm thấy N chỗ trong M chương".
  Future<void> _previewRun() async {
    if (_previewing || _busy) return;
    if (_find.text.trim().isEmpty) {
      _showMessage('Vui lòng nhập tên cần thay.');
      return;
    }
    setState(() => _previewing = true);
    try {
      final ReplaceResult result = await _call(dryRun: true);
      if (!mounted) return;
      setState(() {
        _preview = result;
        _lastRun = null;
        _lastUndo = null;
      });
    } catch (e) {
      _showMessage(e is ApiException ? e.message : 'Không xem trước được.');
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  /// Thay thật — chỉ sau khi người dùng xác nhận hộp thoại.
  Future<void> _run() async {
    final ReplaceResult? preview = _preview;
    if (preview == null || _busy || _previewing) return;
    if (preview.totalMatches == 0) {
      _showMessage('Không có chỗ nào để thay.');
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          'Thay ${preview.totalMatches} chỗ trong '
          '${preview.chapters.length} chương?',
        ),
        content: Text(
          'A = "${_find.text}" → B = "${_replace.text}". '
          '${_applyToFuture ? 'Quy tắc được lưu và áp dụng cho chương thêm sau này. ' : ''}'
          'Có thể hoàn tác batch này ngay sau khi thay.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Thay thật'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final ReplaceResult result = await _call(dryRun: false);
      if (!mounted) return;
      setState(() {
        _lastRun = result;
        _preview = null;
        _lastUndo = null;
      });
      _showMessage(
        'Đã thay ${result.totalMatches} chỗ '
        'trong ${result.chaptersChanged ?? result.chapters.length} chương.',
      );
      if (_applyToFuture) _loadRules();
    } catch (e) {
      _showMessage(e is ApiException ? e.message : 'Không thay được.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hoàn tác batch gần nhất — có hỏi xác nhận.
  Future<void> _undo() async {
    if (_busy) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Hoàn tác lần thay thế gần nhất?'),
        content: const Text(
          'Nội dung các chương sẽ được khôi phục như trước khi thay. '
          'Chương đã bị sửa tiếp sau đó sẽ được bỏ qua.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hoàn tác'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      _api.setToken(AuthService.instance.session?.token);
      final UndoResult result = await _api.undoReplace(widget.storyId);
      if (!mounted) return;
      setState(() {
        _lastUndo = result;
        _lastRun = null;
        _preview = null;
      });
      _showMessage(result.message);
    } catch (e) {
      _showMessage(e is ApiException ? e.message : 'Không hoàn tác được.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRule(GlossaryRule rule) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Xoá quy tắc?'),
        content: Text(
          '"${rule.findText}" → "${rule.replaceText}" sẽ không còn áp dụng '
          'cho chương thêm sau này. Nội dung đã thay trước đó giữ nguyên.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      _api.setToken(AuthService.instance.session?.token);
      await _api.deleteGlossaryRule(widget.storyId, rule.id);
      _showMessage('Đã xoá quy tắc.');
      _loadRules();
    } catch (e) {
      _showMessage(e is ApiException ? e.message : 'Không xoá được quy tắc.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ReplaceResult? preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Tìm & thay thế')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          // ---------- Ô nhập + công tắc ----------
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _find,
                    decoration: const InputDecoration(
                      labelText: 'Tên cần thay (A)',
                      helperText: 'Chuỗi cần tìm trong bản dịch',
                    ),
                    onChanged: (_) => setState(_invalidate),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _replace,
                    decoration: const InputDecoration(
                      labelText: 'Thay bằng (B)',
                      helperText: 'Để trống nếu muốn xoá chuỗi A',
                    ),
                    onChanged: (_) => setState(_invalidate),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Phân biệt hoa thường'),
                    value: _matchCase,
                    onChanged: (bool v) => setState(() {
                      _matchCase = v;
                      _invalidate();
                    }),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chỉ khớp từ nguyên vẹn'),
                    value: _wholeWord,
                    onChanged: (bool v) => setState(() {
                      _wholeWord = v;
                      _invalidate();
                    }),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cả tên chương'),
                    value: _includeTitles,
                    onChanged: (bool v) => setState(() {
                      _includeTitles = v;
                      _invalidate();
                    }),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Áp dụng cho chương thêm sau này'),
                    subtitle: const Text('Lưu thành quy tắc của truyện'),
                    value: _applyToFuture,
                    onChanged: (bool v) => setState(() => _applyToFuture = v),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: (_previewing || _busy) ? null : _previewRun,
                        icon: _previewing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search_rounded, size: 18),
                        label: const Text('Xem trước'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed:
                            (preview != null &&
                                preview.totalMatches > 0 &&
                                !_busy &&
                                !_previewing)
                            ? _run
                            : null,
                        icon: const Icon(Icons.find_replace_rounded, size: 18),
                        label: const Text('Thay ngay'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ---------- Kết quả xem trước ----------
          if (preview != null) ...<Widget>[
            Card(
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      preview.totalMatches == 0
                          ? 'Không tìm thấy chỗ nào'
                          : 'Tìm thấy ${preview.totalMatches} chỗ trong '
                                '${preview.chapters.length} chương',
                      style: theme.textTheme.titleSmall,
                    ),
                    if (preview.chapters.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView(
                          shrinkWrap: true,
                          children: <Widget>[
                            for (final ReplaceChapterHit hit
                                in preview.chapters)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  'Chương ${hit.chapterNo} — ${hit.matches} chỗ',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ---------- Kết quả thay thật ----------
          if (_lastRun != null) ...<Widget>[
            Card(
              margin: EdgeInsets.zero,
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Đã thay ${_lastRun!.totalMatches} chỗ trong '
                      '${_lastRun!.chaptersChanged ?? _lastRun!.chapters.length} chương',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _undo,
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Hoàn tác'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ---------- Kết quả hoàn tác ----------
          if (_lastUndo != null) ...<Widget>[
            Card(
              margin: EdgeInsets.zero,
              color: scheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _lastUndo!.message,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ---------- Quy tắc đã lưu ----------
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Quy tắc đã lưu',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nạp lại danh sách quy tắc',
                        onPressed: _loadingRules ? null : _loadRules,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      ),
                    ],
                  ),
                  if (_loadingRules)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_rulesError != null)
                    Text(
                      'Không tải được quy tắc.',
                      style: theme.textTheme.bodySmall,
                    )
                  else if (_rules.isEmpty)
                    Text(
                      'Chưa có quy tắc nào — chọn "Áp dụng cho chương thêm '
                      'sau này" khi thay để lưu.',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    for (final GlossaryRule rule in _rules)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${rule.findText} → ${rule.replaceText}'),
                        subtitle: Text(
                          <String>[
                            if (rule.matchCase) 'phân biệt hoa thường',
                            if (rule.wholeWord) 'từ nguyên vẹn',
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Xoá quy tắc',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _deleteRule(rule),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
