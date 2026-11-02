import 'package:flutter/material.dart';

import 'alternatives.dart';

/// TextField controller highlight marker `{nghĩa1|nghĩa2}` — nền màu
/// tertiary của theme; ký tự `{`, `|`, `}` làm mờ (màu phụ nhạt), nghĩa đầu
/// in đậm, các nghĩa còn lại màu thường. Không đổi nội dung, chỉ đổi cách vẽ
/// (độ dài span khớp từng ký tự → caret/gõ không vỡ). Cache parse theo chuỗi
/// — chương vài trăm marker vẫn mượt khi gõ/cuộn.
class MarkerEditingController extends TextEditingController {
  String? _cachedText;
  List<Marker>? _cachedMarkers;

  /// Parse marker có cache — chỉ tính lại khi nội dung đổi.
  List<Marker> _markersOf(String text) {
    if (_cachedText == text) return _cachedMarkers ?? const <Marker>[];
    final List<Marker> parsed = parseMarkers(text);
    _cachedText = text;
    _cachedMarkers = parsed;
    return parsed;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final TextSpan base = super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
    // Đang gõ (IME có vùng soạn) → giữ nguyên cách vẽ mặc định.
    if (withComposing && value.isComposingRangeValid) return base;
    final String text = this.text;
    if (!text.contains('{')) return base;
    final List<Marker> markers = _markersOf(text);
    if (markers.isEmpty) return base;

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<InlineSpan> children = <InlineSpan>[];
    int pos = 0;
    for (final Marker marker in markers) {
      if (marker.start > pos) {
        children.add(TextSpan(text: text.substring(pos, marker.start)));
      }
      children.addAll(_markerSpans(marker.rawOf(text), scheme, style));
      pos = marker.end;
    }
    if (pos < text.length) children.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: children);
  }

  /// Vẽ MỘT marker thành từng đoạn: `{` `|` `}` làm mờ, nghĩa đầu in đậm,
  /// các nghĩa còn lại màu thường, nền tô nhẹ cả vùng.
  /// TỔNG độ dài các span phải đúng bằng [raw].length (giữ offset caret).
  List<TextSpan> _markerSpans(
    String raw,
    ColorScheme scheme,
    TextStyle? baseStyle,
  ) {
    final TextStyle bgBase = TextStyle(
      backgroundColor: scheme.tertiaryContainer,
      color: scheme.onTertiaryContainer,
    );
    if (raw.length < 2 || !raw.startsWith('{') || !raw.endsWith('}')) {
      return <TextSpan>[TextSpan(text: raw, style: bgBase)];
    }
    final String inner = raw.substring(1, raw.length - 1);
    final List<String> parts = inner.split('|');
    // Dữ liệu cũ có segment chữ Hán → vẽ mờ như dấu phân cách, không bao giờ
    // coi là “nghĩa đầu in đậm”.
    int firstMeaning = parts.indexWhere(
      (String p) => p.isNotEmpty && !hasCjk(p),
    );
    if (firstMeaning < 0) firstMeaning = 0;
    final TextStyle delim = TextStyle(
      backgroundColor: scheme.tertiaryContainer,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      fontWeight: FontWeight.w500,
    );
    final List<TextSpan> spans = <TextSpan>[TextSpan(text: '{', style: delim)];
    for (int i = 0; i < parts.length; i++) {
      if (i > 0) spans.add(TextSpan(text: '|', style: delim));
      final TextStyle partStyle = (i == firstMeaning)
          ? bgBase.merge(const TextStyle(fontWeight: FontWeight.w700))
          : hasCjk(parts[i])
          ? delim
          : bgBase;
      spans.add(TextSpan(text: parts[i], style: partStyle));
    }
    spans.add(TextSpan(text: '}', style: delim));
    return spans;
  }
}
