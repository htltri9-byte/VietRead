import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietread/main.dart';
import 'package:vietread/services/mock_api_service.dart';
import 'package:vietread/theme/app_theme.dart';
import 'package:vietread/widgets/floating_nav.dart';

void main() {
  // Trang Khám phá đọc tiến độ từ shared_preferences (Bước 5) → cần mock trong test
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// Nguồn dữ liệu giả lập cho app (Bước 6: mặc định đã là API thật).
  MockApiService mockApi() => MockApiService(
    latency: const Duration(milliseconds: 400),
    useCoverImages: false,
  );

  /// Tìm chữ **bên trong thanh điều hướng** — tránh trùng với tiêu đề AppBar.
  Finder navLabel(String label) =>
      find.descendant(of: find.byType(FloatingNav), matching: find.text(label));

  test('chủ đề "Mực & Giấy" đúng màu và font theo Phần A2', () {
    final ThemeData light = AppTheme.light();
    expect(
      light.scaffoldBackgroundColor,
      const Color(0xFFFAF6EE),
    ); // nền kem giấy
    expect(light.colorScheme.primary, const Color(0xFF1F6F6B)); // xanh ngọc đậm
    expect(light.colorScheme.secondary, const Color(0xFFFF6B57)); // san hô
    expect(
      light.textTheme.bodyMedium?.fontFamily,
      AppFonts.ui,
    ); // Be Vietnam Pro
    expect(light.cardTheme.shape, isA<RoundedRectangleBorder>()); // bo góc 16

    final ThemeData dark = AppTheme.dark();
    expect(dark.scaffoldBackgroundColor, const Color(0xFF14181A)); // nền tối
    expect(dark.colorScheme.secondary, const Color(0xFFFF6B57)); // giữ màu nhấn
    expect(dark.textTheme.bodyMedium?.fontFamily, AppFonts.ui);
  });

  test('font nội dung chương là serif Noto Serif', () {
    expect(AppFonts.reading, 'NotoSerif');
    expect(AppFonts.ui, 'BeVietnamPro');
  });  testWidgets('thanh điều hướng 4 mục, mọi mục luôn có nhãn, chuyển tab đúng', (tester) async {
    await tester.pumpWidget(VietReadApp(api: mockApi()));
    await tester.pumpAndSettle();

    // Mọi mục LUÔN hiển thị nhãn (không còn chỉ tab đang chọn)
    expect(navLabel('Khám phá'), findsOneWidget);
    expect(navLabel('Tủ sách'), findsOneWidget);
    expect(navLabel('Đăng truyện'), findsOneWidget);
    expect(navLabel('Tài khoản'), findsOneWidget);

    // Kích thước thanh + từng mục trước khi chuyển tab — để so sánh bên dưới
    final Size barBefore = tester.getSize(find.byType(FloatingNav));
    final List<Size> itemBefore = <Size>[
      for (int i = 0; i < 4; i++)
        tester.getSize(find.byKey(ValueKey<int>(i))),
    ];

    // Sang tab Tủ sách
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNav),
        matching: find.byIcon(Icons.library_books_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tủ sách'), findsWidgets); // tiêu đề AppBar của tab

    // Sang tab Đăng truyện
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNav),
        matching: find.byIcon(Icons.edit_note_outlined),
      ),
    );
    await tester.pumpAndSettle();

    // Sang tab Tài khoản
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNav),
        matching: find.byIcon(Icons.person_outline),
      ),
    );
    await tester.pumpAndSettle();

    // Quay lại tab đầu
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNav),
        matching: find.byIcon(Icons.explore_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(navLabel('Khám phá'), findsOneWidget);

    // THANH VÀ TỪNG MỤC KHÔNG ĐỔI KÍCH THƯỚC sau 4 lần chuyển tab
    expect(tester.getSize(find.byType(FloatingNav)), barBefore);
    for (int i = 0; i < 4; i++) {
      expect(
        tester.getSize(find.byKey(ValueKey<int>(i))),
        itemBefore[i],
        reason: 'mục $i đổi kích thước khi chuyển tab',
      );
    }
  });

  testWidgets('tab Khám phá hiện nội dung thật (dữ liệu mock)', (tester) async {
    // Màn hình cao để toàn bộ khối trang chủ được dựng (ListView dựng theo yêu cầu)
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(VietReadApp(api: mockApi()));
    // Khung xương có animation lặp + mock delay 400ms
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Đang hot'), findsOneWidget);
    expect(find.text('Mới cập nhật'), findsOneWidget);
    expect(navLabel('Khám phá'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
