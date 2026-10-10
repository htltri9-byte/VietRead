import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Một mục của thanh điều hướng dưới (icon + nhãn tiếng Việt).
class NavItem {
  const NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Bottom navigation dạng **viên thuốc nổi** (Phần A2).
///
/// Mục đang chọn là pill màu xanh ngọc kèm nhãn; các mục còn lại chỉ hiện icon.
/// Màu/bo góc đều lấy từ theme, không hard-code trong widget.
class FloatingNav extends StatelessWidget {
  const FloatingNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill + 4),
          // viền mảnh thay vì đổ bóng nặng
          border: Border.all(color: scheme.outline, width: 1),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : AppColors.ink).withValues(
                alpha: isDark ? 0.45 : 0.10,
              ),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (int i = 0; i < items.length; i++)
                  if (i == currentIndex)
                    // mục đang chọn chiếm không gian còn lại để có pill đủ rộng
                    Expanded(
                      child: _NavItemButton(
                        item: items[i],
                        selected: true,
                        onTap: () => onChanged(i),
                      ),
                    )
                  else
                    SizedBox(
                      width: 48,
                      child: _NavItemButton(
                        item: items[i],
                        selected: false,
                        onTap: () => onChanged(i),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemButton extends StatelessWidget {
  const _NavItemButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 22,
                color: selected ? AppColors.white : scheme.onSurfaceVariant,
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
