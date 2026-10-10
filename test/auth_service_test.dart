import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/models/user.dart';
import 'package:vietread/services/api_service.dart';
import 'package:vietread/services/auth_service.dart';
import 'package:vietread/services/mock_api_service.dart';

/// Kiểm tra AuthService — đăng nhập / đăng ký / giữ đăng nhập bằng token
/// lưu trong `shared_preferences` (Bước 6).
void main() {
  MockApiService mock() =>
      MockApiService(latency: Duration.zero, useCoverImages: false);

  /// API luôn lỗi — test thông báo tiếng Việt khi mất mạng (A6).
  _OfflineApi offline() => _OfflineApi();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AuthService.resetForTest(api: mock());
  });

  group('đăng nhập / đăng xuất', () {
    test('đăng nhập lưu token + user vào shared_preferences', () async {
      final User user = await AuthService.instance.login(
        'docgia@vietread.vn',
        'VietRead@123',
      );

      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.user?.email, 'docgia@vietread.vn');
      expect(user.name, isNotEmpty);

      final SharedPreferences sp = await SharedPreferences.getInstance();
      expect(sp.getString(AuthService.tokenKey), isNotEmpty);
      expect(sp.getString(AuthService.userKey), contains('docgia@vietread.vn'));
    });

    test('sai mật khẩu → lỗi 401 tiếng Việt, chưa đăng nhập', () async {
      await expectLater(
        AuthService.instance.login('docgia@vietread.vn', 'sai-mat-khau'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 401)
              .having(
                (ApiException e) => e.message,
                'message',
                'Email hoặc mật khẩu không đúng',
              ),
        ),
      );
      expect(AuthService.instance.isLoggedIn, isFalse);

      final SharedPreferences sp = await SharedPreferences.getInstance();
      expect(sp.getString(AuthService.tokenKey), isNull);
    });

    test('mất mạng → ApiException thông báo thân thiện', () async {
      AuthService.resetForTest(api: offline());
      await expectLater(
        AuthService.instance.login('a@b.vn', '123456'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            contains('Không kết nối được máy chủ'),
          ),
        ),
      );
      expect(AuthService.instance.isLoggedIn, isFalse);
    });

    test('đăng xuất gỡ token khỏi bộ nhớ', () async {
      await AuthService.instance.login('docgia@vietread.vn', 'VietRead@123');
      await AuthService.instance.logout();

      expect(AuthService.instance.isLoggedIn, isFalse);
      expect(AuthService.instance.user, isNull);

      final SharedPreferences sp = await SharedPreferences.getInstance();
      expect(sp.getString(AuthService.tokenKey), isNull);
      expect(sp.getString(AuthService.userKey), isNull);
    });
  });

  group('đăng ký', () {
    test('tài khoản mới → tự đăng nhập và lưu token', () async {
      final User user = await AuthService.instance.register(
        name: 'Người Mới',
        email: 'moi@vietread.vn',
        password: '123456',
      );

      expect(user.name, 'Người Mới');
      expect(AuthService.instance.isLoggedIn, isTrue);
      expect(AuthService.instance.user?.email, 'moi@vietread.vn');
    });

    test('email trùng → lỗi 400, chưa đăng nhập', () async {
      await expectLater(
        AuthService.instance.register(
          name: 'Trùng',
          email: 'docgia@vietread.vn',
          password: '123456',
        ),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 400)
              .having(
                (ApiException e) => e.message,
                'message',
                'Email đã được sử dụng',
              ),
        ),
      );
      expect(AuthService.instance.isLoggedIn, isFalse);
    });
  });

  group('giữ đăng nhập bằng token', () {
    test('restore() đăng nhập lại bằng token đã lưu (mở lại app)', () async {
      await AuthService.instance.login('docgia@vietread.vn', 'VietRead@123');
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String token = sp.getString(AuthService.tokenKey)!;

      // Giả lập mở lại app: phiên mới, token đọc lại từ bộ nhớ.
      final MockApiService freshMock = mock()..setToken(token);
      final AuthService fresh = AuthService.resetForTest(api: freshMock);
      await fresh.restore();

      expect(fresh.isLoggedIn, isTrue);
      expect(fresh.user?.email, 'docgia@vietread.vn');
    });

    test('token hết hạn (401) → tự đăng xuất, xoá token', () async {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(AuthService.tokenKey, 'token-het-han');

      final AuthService fresh = AuthService.resetForTest(api: mock());
      await fresh.restore();

      expect(fresh.isLoggedIn, isFalse);
      expect(sp.getString(AuthService.tokenKey), isNull);
    });

    test('chưa từng đăng nhập → restore không lỗi', () async {
      final AuthService fresh = AuthService.resetForTest(api: mock());
      await fresh.restore();
      expect(fresh.isLoggedIn, isFalse);
    });
  });
}

/// Bản API luôn ném lỗi như khi mất mạng.
class _OfflineApi extends MockApiService {
  _OfflineApi() : super(latency: Duration.zero, useCoverImages: false);

  @override
  Future<AuthResult> login(String email, String password) async {
    throw const ApiException(
      'Không kết nối được máy chủ. Kiểm tra Wi-Fi và địa chỉ API.',
    );
  }
}
