import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Dialog chọn phạm vi tải offline: toàn bộ hoặc một khoảng chương (A3.8).
///
/// [from] / [to] thuộc về State của màn chi tiết — KHÔNG dispose khi dialog
/// đóng (widget vẫn còn trong animation đóng → dùng controller đã dispose sẽ
/// lỗi). [onDownload] được gọi SAU khi dialog đã đóng.
Future<void> showDownloadRangeDialog(
  BuildContext context, {
  required int total,
  required TextEditingController from,
  required TextEditingController to,
  required void Function(int from, int? to) onDownload,
}) async {
  bool showRange = false;
  String? rangeError;

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter setDialogState) {
          Widget content;
          List<Widget> actions;
          if (!showRange) {
            content = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Truyện có $total chương. Chọn phạm vi muốn lưu vào máy '
                  'để đọc được khi mất mạng.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onDownload(1, null);
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text('Tải toàn bộ ($total chương)'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setDialogState(() => showRange = true),
                    icon: const Icon(Icons.toc_rounded, size: 18),
                    label: const Text('Chọn khoảng chương...'),
                  ),
                ),
              ],
            );
            actions = <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Huỷ'),
              ),
            ];
          } else {
            content = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: from,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Từ chương',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: to,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Đến chương',
                        ),
                      ),
                    ),
                  ],
                ),
                if (rangeError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    rangeError!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            );
            actions = <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Huỷ'),
              ),
              FilledButton(
                onPressed: () {
                  final int? start = int.tryParse(from.text.trim());
                  final int? end = int.tryParse(to.text.trim());
                  if (start == null ||
                      end == null ||
                      start < 1 ||
                      end > total ||
                      start > end) {
                    setDialogState(
                      () => rangeError =
                          'Nhập khoảng hợp lệ: 1 ≤ từ ≤ đến ≤ $total.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop();
                  onDownload(start, end);
                },
                child: const Text('Tải'),
              ),
            ];
          }

          return AlertDialog(
            title: const Text('Tải offline'),
            content: content,
            actions: actions,
          );
        },
      );
    },
  );
}

/// Dialog khi truyện đã tải: tải lại / xoá bản tải (A3.8).
Future<void> showDownloadedMenuDialog(
  BuildContext context, {
  required int downloadedCount,
  required VoidCallback onRemove,
  required VoidCallback onDownload,
}) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text('Đã tải $downloadedCount chương'),
      content: const Text(
        'Bạn có thể tải lại để lấy bản mới nhất, hoặc xoá để giải phóng bộ nhớ.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Huỷ'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onRemove();
          },
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Xoá bản tải'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onDownload();
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Tải lại'),
        ),
      ],
    ),
  );
}

/// Dialog tiến trình tải offline: thanh phần trăm + nhãn + nút Huỷ (A3.8).
///
/// Chỉ caller đóng dialog này (sau khi job chạy xong); phím Back của máy
/// gọi [onCancel] (không được dismiss lung tung khi đang tải dở).
class DownloadProgressDialog extends StatelessWidget {
  const DownloadProgressDialog({
    super.key,
    required this.progress,
    required this.status,
    required this.onCancel,
  });

  /// Tiến độ 0.0–1.0.
  final ValueListenable<double> progress;

  /// Nhãn hiện tại, ví dụ `Đang tải 3/128 chương...`.
  final ValueListenable<String> status;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) onCancel();
      },
      child: AlertDialog(
        title: const Text('Đang tải offline'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (BuildContext context, String value, _) =>
                  Text(value, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (BuildContext context, double value, _) =>
                  LinearProgressIndicator(value: value),
            ),
          ],
        ),
        actions: [TextButton(onPressed: onCancel, child: const Text('Huỷ'))],
      ),
    );
  }
}
