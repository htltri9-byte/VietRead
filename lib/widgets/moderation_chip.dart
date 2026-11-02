import 'package:flutter/material.dart';

import '../models/moderation.dart';

/// Chip trạng thái kiểm duyệt (`Nháp` / `Chờ duyệt` / `Đã duyệt` / `Bị từ chối`)
/// — dùng ở màn Truyện của tôi, màn Kiểm duyệt và chi tiết kiểm duyệt.
///
/// Màu đều lấy từ `ColorScheme` của theme nên sáng/tối đều đúng (không hard-code màu).
class ModerationChip extends StatelessWidget {
  const ModerationChip({super.key, required this.status, this.needsRecheck = false});

  /// `draft` | `pending` | `approved` | `rejected`.
  final String status;

  /// Truyện đã duyệt nhưng cần Admin xem lại → hiện thêm chip "Cần xem lại".
  final bool needsRecheck;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final Color color = switch (status) {
      'approved' => scheme.tertiary,
      'pending' => scheme.primary,
      'rejected' => scheme.error,
      _ => scheme.secondary, // draft (nháp)
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Label(label: moderationStatusLabel(status), color: color, theme: theme),
        if (needsRecheck) ...<Widget>[
          const SizedBox(width: 6),
          _Label(label: 'Cần xem lại', color: scheme.error, theme: theme),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.label, required this.color, required this.theme});

  final String label;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
