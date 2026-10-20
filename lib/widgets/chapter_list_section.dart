import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../services/api_service.dart';
import '../utils/date_label.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'skeleton.dart';

/// Tab **Chương** của màn chi tiết truyện: đang tải (skeleton) / lỗi (nút
/// Thử lại) / rỗng / danh sách chương có phân trang "Xem thêm" (A3.4).
class ChapterListSection extends StatelessWidget {
  const ChapterListSection({
    super.key,
    required this.loading,
    required this.error,
    required this.chapters,
    required this.hasMore,
    required this.loadingMore,
    required this.onRetry,
    required this.onLoadMore,
    required this.onSelect,
  });

  final bool loading;
  final Object? error;
  final List<ChapterSummary> chapters;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  /// Mở màn đọc tại chương có số thứ tự [index].
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(width: double.infinity, height: 56, radius: 12),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 56, radius: 12),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 56, radius: 12),
        ],
      );
    }

    if (error != null) {
      return ErrorState(
        message: error is ApiException
            ? (error as ApiException).message
            : 'Không tải được danh sách chương.',
        onRetry: onRetry,
      );
    }

    if (chapters.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Chưa có chương nào',
        message: 'Truyện này chưa đăng chương.',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ChapterSummary chapter in chapters)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                onTap: () => onSelect(chapter.index),
                leading: Text(
                  '${chapter.index}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                title: Text(
                  chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  formatDateLabel(chapter.updatedAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ),
          ),
        if (hasMore)
          Center(
            child: loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  )
                : TextButton.icon(
                    onPressed: onLoadMore,
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('Xem thêm chương'),
                  ),
          ),
      ],
    );
  }
}
