import 'package:flutter/material.dart';

/// Dialog xác nhận "Lấy nghĩa đầu cho tất cả" (màn Sửa chương) —
/// trả `true` nếu người dùng xác nhận thay toàn bộ marker bằng nghĩa đầu.
Future<bool> showResolveAllConfirmDialog(
  BuildContext context, {
  required int markerCount,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Lấy nghĩa đầu cho tất cả?'),
      content: Text(
        '$markerCount chỗ nhiều nghĩa sẽ được thay bằng nghĩa đầu tiên '
        '(người đọc đang thấy đúng nghĩa này). Hành động này chỉ tác động '
        'đến ô nội dung — muốn hoàn tác thì bấm Huỷ và đừng Lưu.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Lấy nghĩa đầu'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Dialog "Dịch lại có gợi ý nghĩa?" — chọn mức gợi ý (Ít / Vừa / Nhiều);
/// trả về mức đã chọn (`'low' | 'medium' | 'high'`) hoặc `null` nếu huỷ.
///
/// Mặc định `'low'` — khớp `MARK_LEVEL` của backend.
Future<String?> showRetranslateDialog(BuildContext context) async {
  String level = 'low';
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext bctx, void Function(void Function()) setLocal) {
        return AlertDialog(
          title: const Text('Dịch lại có gợi ý nghĩa?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Sẽ thay nội dung đang sửa bằng bản dịch lại từ bản gốc bằng '
                'từ điển hiện tại (kèm gợi ý nghĩa). Bấm Lưu để lưu thay đổi này.',
              ),
              const SizedBox(height: 14),
              Text(
                'Mức gợi ý nhiều nghĩa',
                style: Theme.of(bctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'low', label: Text('Ít')),
                  ButtonSegment<String>(value: 'medium', label: Text('Vừa')),
                  ButtonSegment<String>(value: 'high', label: Text('Nhiều')),
                ],
                selected: <String>{level},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> values) =>
                    setLocal(() => level = values.first),
              ),
              const SizedBox(height: 8),
              const Text(
                'Số chỗ được gợi ý mỗi chương: Ít = 15, Vừa = 40, '
                'Nhiều = không giới hạn.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(bctx).pop(false),
              child: const Text('Huỷ'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(bctx).pop(true),
              child: const Text('Dịch lại'),
            ),
          ],
        );
      },
    ),
  );
  return ok == true ? level : null;
}

/// Kết quả dialog "Còn N chỗ chưa chọn nghĩa" khi bấm Lưu.
enum RemainingMarkersAction {
  /// Đóng form, giữ nguyên các marker (lưu sau).
  saveAsIs,

  /// Đóng form, thay mọi marker bằng nghĩa đầu rồi lưu.
  resolveFirst,
}

/// Hỏi người dùng khi bấm Lưu mà nội dung còn marker nhiều nghĩa;
/// trả `null` nếu huỷ (không lưu).
Future<RemainingMarkersAction?> showRemainingMarkersDialog(
  BuildContext context, {
  required int remaining,
}) async {
  final int? choice = await showDialog<int>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text('Còn $remaining chỗ chưa chọn nghĩa'),
      content: const Text(
        'Bạn vẫn lưu được — các chỗ nhiều nghĩa giữ nguyên để chọn sau, '
        'người đọc chỉ thấy nghĩa đầu tiên.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(0),
          child: const Text('Huỷ'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(1),
          child: const Text('Lưu và làm tiếp sau'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(2),
          child: const Text('Lấy nghĩa đầu rồi lưu'),
        ),
      ],
    ),
  );
  if (choice == 1) return RemainingMarkersAction.saveAsIs;
  if (choice == 2) return RemainingMarkersAction.resolveFirst;
  return null; // huỷ / bấm ngoài
}
