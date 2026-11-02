import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vietread/services/db_helper.dart';

/// Bật SQLite thật (FFI, không isolate) cho **test thuần** (`test(...)`)
/// trên máy tính.
///
/// Sqflite mặc định chỉ chạy trên thiết bị; trong `flutter test` thì
/// `databaseFactory` chưa khởi tạo nên [DbHelper] tự fail-fast bằng
/// StateError và các tầng quanh nó đã bắt sẵn. Vì vậy:
/// - Test `testWidgets` KHÔNG gọi hàm này (await db trong fake-async sẽ treo).
/// - Test thuần muốn kiểm tra SQLite thật thì gọi trong `setUpAll` và
///   [resetDbForTest] trong `setUp` để mỗi test có db in-memory sạch.
void setUpSqfliteFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
}

/// Đóng db cũ (nếu có) và mở lại bản in-memory rỗng cho test hiện tại.
Future<void> resetDbForTest() async {
  try {
    await DbHelper.instance.close();
  } catch (_) {
    // db cũ chưa mở được hoặc đã đóng — bỏ qua.
  }
  DbHelper.resetForTest(path: inMemoryDatabasePath);
}
