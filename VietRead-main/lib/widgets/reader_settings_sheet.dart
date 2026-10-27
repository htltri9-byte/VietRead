import 'package:flutter/material.dart';

import '../services/prefs_service.dart';

/// Bottom sheet **Cài đặt đọc** (tách từ `ReaderScreen`): nền sáng/tối/sepia,
/// font, cỡ chữ, giãn dòng.
///
/// Mỗi chỉnh sửa gọi ngay [onChanged] để màn đọc áp dụng + lưu prefs;
/// bấm "Xong" để đóng.
class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  /// Cài đặt hiện tại — sheet bắt đầu từ đây.
  final ReaderSettings initial;

  /// Gọi mỗi khi người dùng đổi một lựa chọn (áp dụng ngay, không chờ đóng).
  final ValueChanged<ReaderSettings> onChanged;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _draft = widget.initial;

  static const List<(String, String)> _backgrounds = <(String, String)>[
    ('Sáng', ReaderSettings.bgLight),
    ('Tối', ReaderSettings.bgDark),
    ('Sepia', ReaderSettings.bgSepia),
  ];

  void _change(ReaderSettings value) {
    setState(() => _draft = value);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReaderSettings draft = _draft;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      // Cuộn được khi cỡ chữ hệ thống lớn hoặc màn hình thấp
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cài đặt đọc', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text('Nền', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final (String label, String value) in _backgrounds)
                  ChoiceChip(
                    label: Text(label),
                    selected: draft.background == value,
                    onSelected: (_) =>
                        _change(draft.copyWith(background: value)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Font chữ', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Serif (Noto Serif)'),
                  selected: draft.useSerif,
                  onSelected: (_) => _change(draft.copyWith(useSerif: true)),
                ),
                ChoiceChip(
                  label: const Text('Sans (Be Vietnam Pro)'),
                  selected: !draft.useSerif,
                  onSelected: (_) => _change(draft.copyWith(useSerif: false)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Cỡ chữ: ${draft.fontSize.round()}',
              style: theme.textTheme.labelLarge,
            ),
            Slider(
              value: draft.fontSize,
              min: 14,
              max: 28,
              divisions: 14,
              label: draft.fontSize.round().toString(),
              onChanged: (double v) => _change(draft.copyWith(fontSize: v)),
            ),
            Text(
              'Giãn dòng: ${draft.lineHeight.toStringAsFixed(1)}',
              style: theme.textTheme.labelLarge,
            ),
            Slider(
              value: draft.lineHeight,
              min: 1.3,
              max: 2.1,
              divisions: 8,
              label: draft.lineHeight.toStringAsFixed(1),
              onChanged: (double v) => _change(draft.copyWith(lineHeight: v)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Xong'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
