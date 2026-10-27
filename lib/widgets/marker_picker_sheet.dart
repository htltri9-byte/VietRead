import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/alternatives.dart';

/// Bottom sheet chọn nghĩa — tiêu đề “Chọn nghĩa” + vị trí “3 / 14” + mũi tên
/// trước/sau (không đóng sheet), ngữ cảnh câu quanh chỗ đang chọn (cập nhật
/// theo nghĩa vừa chọn), thẻ nghĩa lớn dễ bấm, ô nhập nghĩa riêng và hàng
/// công tắc/nút phụ. KHÔNG hiển thị chữ Hán ở bất kỳ đâu.
///
/// Tách từ `chapter_form_screen.dart` (Bước 9) — toàn bộ callback do màn Sửa
/// chương tiêm vào, sheet chỉ lo phần hiển thị + chọn nghĩa.
class MarkerPickerSheet extends StatelessWidget {
  const MarkerPickerSheet({
    super.key,
    required this.current,
    required this.textOf,
    required this.positionOf,
    required this.boundsOf,
    required this.onPick,
    required this.onNavigate,
    required this.onClose,
  });

  /// Marker đang xem — đổi khi bấm mũi tên trước/sau (không đóng sheet).
  final ValueNotifier<Marker> current;

  /// Văn bản mới nhất trong ô nội dung.
  final String Function() textOf;

  /// Vị trí hiện tại (index 0-based, tổng số chỗ) — hiển thị “3 / 14”.
  final ({int index, int total})? Function(Marker) positionOf;

  /// Ranh giới marker trong văn bản LIVE (còn nguyên hoặc chỗ đã ghi nghĩa).
  final ({int start, int end}) Function(Marker) boundsOf;

  /// Chọn một nghĩa → áp dụng ngay; trả `true` nếu vẫn còn marker.
  final bool Function(Marker marker, String meaning, bool applyAll) onPick;

  /// Nhảy marker kế tiếp (`true`) / trước đó (`false`) — trả `false` nếu không
  /// có chỗ để nhảy.
  final bool Function(bool forward) onNavigate;

  /// Đóng sheet (hết marker hoặc người dùng bấm ✕).
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ValueListenableBuilder<Marker>(
          valueListenable: current,
          builder: (BuildContext context, Marker marker, _) {
            return _MarkerPickerBody(
              marker: marker,
              textOf: textOf,
              positionOf: positionOf,
              boundsOf: boundsOf,
              onPick: onPick,
              onNavigate: onNavigate,
              onClose: onClose,
            );
          },
        ),
      ),
    );
  }
}

class _MarkerPickerBody extends StatefulWidget {
  const _MarkerPickerBody({
    required this.marker,
    required this.textOf,
    required this.positionOf,
    required this.boundsOf,
    required this.onPick,
    required this.onNavigate,
    required this.onClose,
  });

  final Marker marker;
  final String Function() textOf;
  final ({int index, int total})? Function(Marker) positionOf;
  final ({int start, int end}) Function(Marker) boundsOf;
  final bool Function(Marker marker, String meaning, bool applyAll) onPick;
  final bool Function(bool forward) onNavigate;
  final VoidCallback onClose;

  @override
  State<_MarkerPickerBody> createState() => _MarkerPickerBodyState();
}

class _MarkerPickerBodyState extends State<_MarkerPickerBody> {
  final TextEditingController _custom = TextEditingController();

  /// Nghĩa đang chọn — dùng cho preview ngữ cảnh xem trước.
  String _selected = '';
  bool _applyAll = false;

  /// “Tự chuyển sang chỗ tiếp theo” — mặc định bật.
  bool _autoNext = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.marker.first;
  }

  @override
  void didUpdateWidget(covariant _MarkerPickerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool changed =
        oldWidget.marker.start != widget.marker.start ||
        oldWidget.marker.end != widget.marker.end ||
        !listEquals(oldWidget.marker.meanings, widget.marker.meanings);
    if (changed) {
      // Đổi sang chỗ khác: giữ lựa chọn nếu chỗ mới có đúng nghĩa đó
      // (vừa chọn ở chỗ trước rồi nhảy tiếp), không thì về nghĩa đầu.
      if (!widget.marker.meanings.contains(_selected)) {
        _selected = widget.marker.first;
      }
      _custom.clear();
    }
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  // ------------------------- Thao tác -------------------------

  /// Chọn một nghĩa: áp dụng NGAY vào ô nội dung (sheet không đóng).
  void _pick(String meaning) {
    HapticFeedback.selectionClick(); // rung nhẹ khi chọn
    setState(() => _selected = meaning);
    final bool remains = widget.onPick(widget.marker, meaning, _applyAll);
    _afterChange(remains);
  }

  /// Sau khi thay đổi: hết marker → đóng sheet; còn → tự chuyển tiếp (nếu bật).
  void _afterChange(bool remains) {
    if (!mounted) return;
    if (!remains) {
      widget.onClose();
      return;
    }
    if (_autoNext) widget.onNavigate(true);
  }

  void _navigate(bool forward) {
    widget.onNavigate(forward); // current đổi → didUpdateWidget cập nhật UI
  }

  /// Sạch hoá một đoạn ngữ cảnh: bỏ mẩu `{...}` dở dang ở hai đầu (do cắt
  /// khoảng 80 ký tự mỗi bên) rồi resolve marker còn lại thành nghĩa đầu.
  String _contextSegment(String segment) {
    String s = segment;
    final int strayClose = s.indexOf('}');
    final int strayOpen = s.indexOf('{');
    if (strayClose >= 0 && (strayOpen < 0 || strayClose < strayOpen)) {
      s = s.substring(strayClose + 1); // bắt đầu GIỮA marker → cắt đến hết `}`
    }
    final int open = s.lastIndexOf('{');
    final int close = s.lastIndexOf('}');
    if (open >= 0 && open > close) {
      s = s.substring(0, open); // kết thúc GIỮA marker → cắt bỏ từ `{`
    }
    return resolveMarkers(s);
  }

  // ------------------------- Giao diện -------------------------

  /// Thẻ một nghĩa — vùng chạm cả thẻ (≥ 48dp), nhãn Semantics riêng.
  Widget _meaningCard(ThemeData theme, ColorScheme scheme, int index) {
    final String meaning = widget.marker.meanings[index];
    final bool selected = meaning == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        container: true,
        selected: selected,
        label: index == 0
            ? 'Nghĩa ${index + 1}: $meaning, mặc định'
            : 'Nghĩa ${index + 1}: $meaning',
        excludeSemantics: true,
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: RadioListTile<String>(
            value: meaning,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            title: Row(
              children: <Widget>[
                if (index == 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Mặc định',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    meaning,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: index == 0
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String full = widget.textOf();
    final ({int start, int end}) bounds = widget.boundsOf(widget.marker);
    final int s = bounds.start.clamp(0, full.length);
    final int e = bounds.end.clamp(s, full.length);
    const int pad = 80; // ~60-80 ký tự mỗi bên theo yêu cầu
    // Ngữ cảnh phải SẠCH: bỏ mẩu marker dở dang (do cắt 80 ký tự) rồi resolve
    // mọi marker khác (dữ liệu cũ còn chữ Hán) — sheet không bao giờ hiển thị
    // chữ Hán ở bất kỳ đâu.
    final String before = _contextSegment(
      full.substring((s - pad).clamp(0, s), s),
    );
    final String after = _contextSegment(
      full.substring(e, (e + pad).clamp(e, full.length)),
    );
    final ({int index, int total})? pos = widget.positionOf(widget.marker);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ---------- Đầu sheet: tiêu đề + vị trí + mũi tên ----------
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Chọn nghĩa', style: theme.textTheme.titleLarge),
              ),
              if (pos != null)
                Text(
                  '${pos.index + 1} / ${pos.total}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              IconButton(
                tooltip: 'Chỗ trước',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: pos == null ? null : () => _navigate(false),
              ),
              IconButton(
                tooltip: 'Chỗ sau',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: pos == null ? null : () => _navigate(true),
              ),
              IconButton(
                tooltip: 'Đóng',
                icon: const Icon(Icons.close_rounded),
                onPressed: widget.onClose,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              visualDensity: VisualDensity.compact,
              label: const Text('Tự chuyển sang chỗ tiếp theo'),
              selected: _autoNext,
              onSelected: (bool v) => setState(() => _autoNext = v),
            ),
          ),
          const SizedBox(height: 8),
          // ---------- Ngữ cảnh: câu quanh chỗ đang chọn ----------
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Container(
              key: ValueKey<String>('ctx_${s}_${e}_$_selected'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: before),
                    TextSpan(
                      text: _selected,
                      style: TextStyle(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: after),
                  ],
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ---------- Danh sách thẻ nghĩa ----------
          Flexible(
            child: RadioGroup<String>(
              groupValue: _selected,
              onChanged: (String? v) {
                if (v != null) _pick(v);
              },
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (int i = 0; i < widget.marker.meanings.length; i++)
                    _meaningCard(theme, scheme, i),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ---------- Nhập nghĩa khác ----------
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _custom,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Nhập nghĩa khác',
                    border: OutlineInputBorder(),
                  ),
                  // Gõ xong phải rebuild để bật nút “Dùng”.
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _custom.text.trim().isEmpty
                    ? null
                    : () => _pick(_custom.text.trim()),
                child: const Text('Dùng'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ---------- Hàng công tắc + nút phụ ----------
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilterChip(
                label: const Text(
                  'Áp dụng cho mọi chỗ giống nhau trong chương',
                ),
                selected: _applyAll,
                onSelected: (bool v) => setState(() => _applyAll = v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Chọn nghĩa sẽ áp dụng ngay vào ô nội dung; bật công tắc trên để '
            'áp dụng cho mọi chỗ giống nhau trong chương.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
