import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Chip thể loại bo tròn hoàn toàn, viền mảnh (A2: chip thể loại cuộn ngang).
class GenreChip extends StatelessWidget {
  const GenreChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.round),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.round),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? AppColors.white : scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
