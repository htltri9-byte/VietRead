/// Khoảng cách & kích thước dùng lại trong app (design tokens).
///
/// Mọi số trong file này là bội số của 4dp; widget KHÔNG tự hard-code
/// khoảng cách — lấy từ đây để giao diện nhất quán (Phần C).
class AppSpacing {
  const AppSpacing._();

  /// 4 — khe nhỏ nhất (icon ↔ nhãn, trong chip).
  static const double xs = 4;

  /// 8 — khoảng cách chặt (giữa các item trong một khối).
  static const double sm = 8;

  /// 12 — khoảng cách chuẩn (giữa các card/dòng).
  static const double md = 12;

  /// 16 — lề trong card / khoảng cách khối (padding mặc định).
  static const double lg = 16;

  /// 24 — khoảng cách lớn (giữa các phần của trang).
  static const double xl = 24;

  /// 32 — khoảng cách rất lớn (trên tiêu đề trang lớn).
  static const double xxl = 32;
}

/// Kích thước cố định của điều khiển — dùng để layout KHÔNG nhảy khi đổi
/// trạng thái (yêu cầu của thanh điều hướng Phần A).
class AppSizes {
  const AppSizes._();

  /// Vùng chạm tối thiểu theo Material (48dp).
  static const double touchTarget = 48;

  /// Chiều cao cố định mỗi mục thanh điều hướng dưới.
  static const double navItemHeight = 56;

  /// Nền tròn sau icon mục đang chọn (cố định mọi trạng thái).
  static const double navBadge = 36;

  /// Kích thước icon thanh điều hướng (không đổi khi chọn/bỏ chọn).
  static const double navIcon = 22;

  /// Khung cao cố định cho nhãn mục nav — nhãn tự thu nhỏ nếu tràn.
  static const double navLabelBox = 16;

  /// Đệm bên trong thanh điều hướng.
  static const double navInset = 6;
}
