import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../services/prefs_service.dart';
import '../theme/app_theme.dart';

/// Nội dung chương trong màn đọc (tách từ `ReaderScreen`): tiêu đề + nội dung
/// + dòng "— Hết chương N —", theo cài đặt font/cỡ chữ/giãn dòng và màu mực
/// của nền đọc đang chọn.
class ReaderChapterBody extends StatelessWidget {
  const ReaderChapterBody({
    super.key,
    required this.chapter,
    required this.settings,
    required this.ink,
    required this.controller,
  });

  final Chapter chapter;

  /// Cài đặt đọc (font, cỡ chữ, giãn dòng).
  final ReaderSettings settings;

  /// Màu chữ theo nền đọc hiện tại.
  final Color ink;

  /// Controller do màn đọc giữ — màn nghe nó để tính % tiến độ và lưu.
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color mutedInk = ink.withValues(alpha: 0.65);
    final String fontFamily =
        settings.useSerif ? AppFonts.reading : AppFonts.ui;

    return SingleChildScrollView(
      controller: controller,
      // Lề đọc thoáng hơn hai bên, dễ chịu khi đọc dài (C7)
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapter.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: fontFamily,
              color: ink,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            chapter.content,
            style: (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
              fontFamily: fontFamily,
              fontSize: settings.fontSize,
              height: settings.lineHeight,
              color: ink,
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              '— Hết chương ${chapter.index} —',
              style: theme.textTheme.labelMedium?.copyWith(color: mutedInk),
            ),
          ),
        ],
      ),
    );
  }
}
