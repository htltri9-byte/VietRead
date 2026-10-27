import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Khối "xương" (skeleton) đang tải — hiệu ứng shimmer quét ngang nhẹ (C4).
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  /// Shimmer quét ngang nhẹ 1.2s — màu lấy từ theme (sáng: vệt trắng,
  /// tối: vệt trắng mờ) để đúng ngôn ngữ "Mực & Giấy".
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color base = theme.colorScheme.outlineVariant;
    final BoxDecoration decoration = BoxDecoration(
      color: base,
      borderRadius: BorderRadius.circular(widget.radius),
    );

    // Hệ thống bật "giảm chuyển động" → skeleton đứng yên.
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: decoration,
      );
    }

    final Color highlight = Colors.white.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.06 : 0.75,
    );
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: Alignment(-1.0 - 2 * _controller.value, 0),
        end: Alignment(1.0 - 2 * _controller.value, 0),
        colors: <Color>[base, highlight, base],
      ).createShader(bounds),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: decoration,
      ),
    );
  }
}

/// Khung xương cho **danh sách thẻ** (Truyện của tôi, Quản lý chương…):/// vài khối tròn cao như Card đang tải (Bước 11).
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 5});

  /// Số khối "thẻ" cần dựng.
  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: <Widget>[
        for (int i = 0; i < rows; i++) ...<Widget>[
          SkeletonBox(
            width: double.infinity,
            height: 72,
            radius: AppRadius.card,
          ),
          if (i != rows - 1) const SizedBox(height: AppSpacing.md - 2),
        ],
      ],
    );
  }
}

/// Khung xương cho **Trang Khám phá**: header + ô tìm kiếm + thẻ lớn + chip + lưới.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: const [
        // Header + ô tìm kiếm
        Row(
          children: [
            Expanded(child: SkeletonBox(width: double.infinity, height: 22)),
            SizedBox(width: 12),
            SkeletonBox(width: 40, height: 40, radius: 20),
          ],
        ),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 48, radius: 24),
        SizedBox(height: 20),
        // Thẻ "Đọc tiếp"
        SkeletonBox(width: double.infinity, height: 132, radius: 16),
        SizedBox(height: 20),
        // Chip thể loại
        Row(
          children: [
            SkeletonBox(width: 88, height: 34, radius: 17),
            SizedBox(width: 8),
            SkeletonBox(width: 76, height: 34, radius: 17),
            SizedBox(width: 8),
            SkeletonBox(width: 96, height: 34, radius: 17),
            SizedBox(width: 8),
            SkeletonBox(width: 70, height: 34, radius: 17),
          ],
        ),
        SizedBox(height: 24),
        // Lưới "Đang hot"
        SkeletonBox(width: 140, height: 20),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SkeletonBox(width: double.infinity, height: 240)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(width: double.infinity, height: 240)),
          ],
        ),
        SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: SkeletonBox(width: double.infinity, height: 240)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(width: double.infinity, height: 240)),
          ],
        ),
        SizedBox(height: 24),
        // "Mới cập nhật"
        SkeletonBox(width: 170, height: 20),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 88, radius: 16),
        SizedBox(height: 10),
        SkeletonBox(width: double.infinity, height: 88, radius: 16),
      ],
    );
  }
}
