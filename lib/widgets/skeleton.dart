import 'package:flutter/material.dart';

/// Khối "xương" (skeleton) đang tải — hiệu ứng nhấp nháy nhẹ theo A2.
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = Theme.of(context).colorScheme.outlineVariant;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 0.85).animate(_controller),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        for (int i = 0; i < rows; i++) ...<Widget>[
          SkeletonBox(width: double.infinity, height: 72, radius: 16),
          if (i != rows - 1) const SizedBox(height: 10),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
