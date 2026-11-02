import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Một mục của thanh điều hướng dưới (icon + nhãn tiếng Việt).
class NavItem {
  const NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  /// Icon **outline** — hiện khi mục CHƯA chọn.
  final IconData icon;

  /// Icon **filled** — hiện khi mục đang chọn (cùng [FloatingNav] kích thước,
  /// chỉ đổi hình dạng, không đổi layout).
  final IconData selectedIcon;

  final String label;
}

/// Bottom navigation dạng **viên thuốc nổi** — kích thước cố định tuyệt đối.
///
/// Bốn mục chia đều chiều rộng; mỗi mục LUÔN có icon (cố định 22dp) trên và
/// nhãn nhỏ bên dưới. Mục đang chọn: icon outline → filled, nhãn + icon đổi
/// sang xanh ngọc, xuất hiện nền tròn nhạt sau icon — tất cả chỉ đổi **màu**
/// qua fade ~180ms, không đổi width/padding/size nên thanh không bao giờ
/// co giãn hay làm icon dịch chỗ khi chuyển tab.
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
      // Chịu SafeArea + vùng cử chỉ Android: không che nội dung cuối trang.
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface, // nền đúng màu card của theme (sáng/tối)
          borderRadius: BorderRadius.circular(AppRadius.pill + AppSpacing.xs),
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
            padding: const EdgeInsets.all(AppSizes.navInset),
            child: Row(
              // 4 mục chia đều — mỗi mục luôn giữ nguyên kích thước.
              children: [
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavItemButton(
                      key: ValueKey<int>(i),
                      item: items[i],
                      selected: i == currentIndex,
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
    super.key,
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
    final bool isDark = theme.brightness == Brightness.dark;
    // Xanh ngọc khi chọn; nền tối dùng bản sáng hơn để nhãn 11dp vẫn rõ.
    final Color selectedColor = isDark
        ? AppColors.primarySoft
        : AppColors.primary;
    final Color unselectedColor = scheme.onSurfaceVariant;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        // ripple gọn, theo bo viên thuốc, không làm lệch layout
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: SizedBox(
          height: AppSizes.navItemHeight,
          // Một animation màu dùng chung cho badge, icon và nhãn: đổi tab chỉ
          // fade màu trong 180ms, kích thước không đổi.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            builder: (BuildContext context, double t, _) {
              final Color fg = Color.lerp(unselectedColor, selectedColor, t)!;
              final Color bg = Color.lerp(
                Colors.transparent,
                selectedColor.withValues(alpha: 0.14),
                t,
              )!;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Nền tròn sau icon — kích thước cố định, chỉ đổi màu.
                  Container(
                    width: AppSizes.navBadge,
                    height: AppSizes.navBadge,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      size: AppSizes.navIcon,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Nhãn LUÔN hiện, 1 dòng, cùng cỡ/font weight mọi trạng thái;
                  // cỡ chữ hệ thống lớn → tự thu nhỏ, không tràn.
                  SizedBox(
                    height: AppSizes.navLabelBox,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
