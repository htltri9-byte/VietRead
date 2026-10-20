import 'package:flutter/material.dart';

/// Khối nút hành động của màn chi tiết truyện:
/// **Đọc / Đọc tiếp** (dày hết chiều ngang) + hàng **Theo dõi** / **Tải offline**.
class StoryActionButtons extends StatelessWidget {
  const StoryActionButtons({
    super.key,
    required this.onRead,
    required this.hasProgress,
    required this.following,
    required this.followBusy,
    required this.onFollow,
    required this.downloaded,
    required this.downloadedCount,
    required this.onOffline,
  });

  /// `null` = chưa có chương → nút Đọc bị tắt.
  final VoidCallback? onRead;

  /// true = có tiến độ đọc → nhãn "Đọc tiếp".
  final bool hasProgress;

  final bool following;
  final bool followBusy;
  final VoidCallback onFollow;

  final bool downloaded;
  final int downloadedCount;
  final VoidCallback onOffline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onRead,
          icon: const Icon(Icons.menu_book_rounded),
          label: Text(hasProgress ? 'Đọc tiếp' : 'Đọc'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: following
                  ? FilledButton.icon(
                      onPressed: followBusy ? null : onFollow,
                      icon: const Icon(Icons.favorite_rounded, size: 18),
                      label: const Text('Đã theo dõi'),
                    )
                  : OutlinedButton.icon(
                      onPressed: followBusy ? null : onFollow,
                      icon: const Icon(
                        Icons.favorite_border_rounded,
                        size: 18,
                      ),
                      label: const Text('Theo dõi'),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOffline,
                icon: Icon(
                  downloaded
                      ? Icons.download_done_rounded
                      : Icons.download_rounded,
                  size: 18,
                ),
                label: Text(
                  downloaded ? 'Đã tải ($downloadedCount)' : 'Tải offline',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
