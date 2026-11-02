import 'package:flutter/material.dart';

/// Thanh công cụ chọn nghĩa của màn **Sửa chương**: nút "Còn N chỗ" /
/// "Đã chọn hết nghĩa" (duyệt marker), "Lấy nghĩa đầu cho tất cả" và
/// "Dịch lại" (chỉ hiện khi đang sửa chương).
///
/// Nút nào liên quan marker đều tắt (`onPressed: null`) khi hết chỗ cần chọn.
class MarkerToolBar extends StatelessWidget {
  const MarkerToolBar({
    super.key,
    required this.markerCount,
    required this.isEdit,
    required this.retranslating,
    required this.onBrowse,
    required this.onResolveAll,
    required this.onRetranslate,
  });

  /// Số chỗ nhiều nghĩa còn lại trong ô nội dung.
  final int markerCount;

  /// true = đang sửa chương → hiện nút "Dịch lại".
  final bool isEdit;

  /// Đang gọi /retranslate → nút Dịch lại hiển thị vòng quay và tắt bấm.
  final bool retranslating;

  final VoidCallback onBrowse;
  final VoidCallback onResolveAll;
  final VoidCallback onRetranslate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: markerCount > 0 ? onBrowse : null,
          icon: const Icon(Icons.format_list_numbered_rounded, size: 18),
          label: Text(
            markerCount > 0 ? 'Còn $markerCount chỗ' : 'Đã chọn hết nghĩa',
          ),
        ),
        OutlinedButton.icon(
          onPressed: markerCount > 0 ? onResolveAll : null,
          icon: const Icon(Icons.done_all_rounded, size: 18),
          label: const Text('Lấy nghĩa đầu cho tất cả'),
        ),
        if (isEdit)
          OutlinedButton.icon(
            onPressed: retranslating ? null : onRetranslate,
            icon: retranslating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Dịch lại'),
          ),
      ],
    );
  }
}
