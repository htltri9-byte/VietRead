import 'package:flutter/material.dart';

import '../models/story.dart';
import '../theme/app_theme.dart';
import 'chip_genre.dart';
import 'story_card.dart';
import 'story_credits.dart';

/// Khối "bìa + thông tin" trên cùng của màn chi tiết truyện:
/// ảnh bìa, tên, tác giả, thể loại, điểm, số chương, trạng thái.
class StoryHeader extends StatelessWidget {
  const StoryHeader({super.key, required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          height: 160,
          child: StoryCover(story: story, radius: 14),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(story.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              // Hai dòng riêng: Tác giả (nguyên tác) và Người đăng.
              StoryCredits(story: story),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: story.genres
                    .map((String g) => GenreChip(label: g))
                    .toList(),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        story.ratingLabel,
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                  Text(
                    story.chapterLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  StatusPill(label: story.statusLabel),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Viên trạng thái "Đang ra" / "Hoàn thành" ở đầu trang chi tiết.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.round),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
