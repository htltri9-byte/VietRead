/// Định dạng ngày ngắn `dd/MM/yyyy` — dùng chung ở màn chi tiết truyện
/// (ngày cập nhật chương, ngày gửi bình luận).
String formatDateLabel(DateTime time) {
  final String dd = time.day.toString().padLeft(2, '0');
  final String mm = time.month.toString().padLeft(2, '0');
  return '$dd/$mm/${time.year}';
}
