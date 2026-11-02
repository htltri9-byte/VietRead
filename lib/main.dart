import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/main_shell.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VietReadApp());
  // Tự đăng nhập lại bằng token đã lưu — không chặn khung hình đầu tiên (Bước 6).
  AuthService.instance.restore();
}

/// App VietRead — chủ đề "Mực & Giấy", giao diện tiếng Việt (Phần A).
class VietReadApp extends StatelessWidget {
  const VietReadApp({super.key, this.api});

  /// Tiêm nguồn dữ liệu (test dùng mock) — mặc định theo cờ `ApiConfig.useMock`.
  final ApiService? api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VietRead',
      debugShowCheckedModeBanner: false,
      // Ngôn ngữ giao diện: Tiếng Việt
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Sáng/tối theo hệ thống; Bước 11 sẽ đọc cài đặt từ shared_preferences
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: MainShell(api: api),
    );
  }
}
