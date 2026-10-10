import 'dart:io' show Platform;

/// Cấu hình API — đúng yêu cầu A6: *"Dùng dữ liệu mock trước (MockApiService)
/// rồi dễ chuyển sang API thật bằng đổi 1 cờ cấu hình"*.
class ApiConfig {
  const ApiConfig._();

  /// `true` = dùng dữ liệu mock (không cần backend), `false` = gọi API thật.
  ///
  /// **Bước 6** đã chuyển sang API thật (`false`) — muốn chạy không cần backend
  /// thì đổi lại thành `true`, không phải sửa code ở nơi khác.
  static const bool useMock = false;

  /// Địa chỉ backend.
  ///
  /// - Emulator Android: `http://10.0.2.2:8000` (mặc định)
  /// - Máy thật: IP LAN của máy chạy backend, ví dụ `http://192.168.1.10:8000`
  ///
  /// Ghi đè khi build:
  /// `flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000`
  /// hoặc đặt biến môi trường `API_BASE_URL` (dùng cho `dart run`).
  static final String baseUrl = _resolveBaseUrl();

  static String _resolveBaseUrl() {
    const String fromDefine = String.fromEnvironment('API_BASE_URL');
    if (fromDefine.isNotEmpty) return fromDefine;
    final String? fromEnv = Platform.environment['API_BASE_URL'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return 'http://10.0.2.2:8000'; // emulator Android
  }

  /// Chế độ mock có "giả mạng" để thấy skeleton loading không.
  static const Duration mockLatency = Duration(milliseconds: 400);

  /// Timeout cho request thật (A6: bắt lỗi mạng, có timeout).
  static const Duration requestTimeout = Duration(seconds: 10);
}
