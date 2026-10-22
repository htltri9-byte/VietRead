import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Thanh điều khiển dưới cùng của màn đọc (tách từ `ReaderScreen`):
/// nút chương trước/sau + số chương hiện tại + % đã cuộn.
///
/// Nền bán trong suốt, mờ nhẹ nội dung phía sau (C7); màu lấy từ
/// [background]/[ink] mà màn đọc tính theo nền đọc đang chọn.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.background,
    required this.ink,
    required this.index,
    required this.progress,
    this.onPrev,
    required this.onNext,
  });

  /// Màu nền đọc hiện tại (sáng / tối / sepia).
  final Color background;

  /// Màu chữ theo nền đọc.
  final Color ink;

  /// Số chương đang đọc (bắt đầu từ 1).
  final int index;

  /// Tiến độ đọc trong chương (0.0–1.0).
  final double progress;

  /// Chương trước — `null` = đang ở chương 1 (nút bị tắt).
  final VoidCallback? onPrev;

  /// Chương sau.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final Color mutedInk = ink.withValues(alpha: 0.65);
    final String percent = '${(progress * 100).round()}%';

    return ClipRect(
      // Thanh điều khiển bán trong suốt: mờ nhẹ nội dung phía sau (C7)
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: background.withValues(alpha: 0.82),
            border: Border(
              top: BorderSide(color: mutedInk.withValues(alpha: 0.25)),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            8,
            6,
            8,
            6 + MediaQuery.of(context).padding.bottom,
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left_rounded),
                color: ink,
                disabledColor: mutedInk,
                tooltip: 'Chương trước',
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Chương $index',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      percent,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: mutedInk),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
                color: ink,
                disabledColor: mutedInk,
                tooltip: 'Chương sau',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
