import 'package:flutter/material.dart';

/// Bảng màu "Mực & Giấy" — ánh xạ đúng theo Phần A2 của đề bài.
class AppColors {
  const AppColors._();

  // ----- Chủ đề sáng (nền kem giấy) -----
  static const Color paper = Color(0xFFFAF6EE); // nền kem giấy
  static const Color card = Color(0xFFFFFDF6); // card trắng ngà
  static const Color ink = Color(0xFF23201C); // màu chữ
  static const Color inkMuted = Color(0xFF6F6A5E); // chữ phụ
  static const Color border = Color(0xFFE7E0D2); // viền mảnh

  // ----- Chủ đề tối -----
  static const Color night = Color(0xFF14181A); // nền tối
  static const Color cardNight = Color(0xFF1C2225);
  static const Color inkNight = Color(0xFFF1EEE7);
  static const Color inkMutedNight = Color(0xFF9BA4A6);
  static const Color borderNight = Color(0xFF2C3336);

  // ----- Dùng chung cho cả 2 chế độ -----
  static const Color primary = Color(0xFF1F6F6B); // xanh ngọc đậm

  /// Bản sáng của xanh ngọc — dùng trên nền tối (thanh điều hướng, nhấn
  /// nhạt…) để chữ nhỏ vẫn đạt tương phản dễ đọc.
  static const Color primarySoft = Color(0xFF57BFB6);
  static const Color accent = Color(0xFFFF6B57); // san hô
  static const Color white = Color(0xFFFFFFFF);

  // ----- Nền đọc sepia (A3.5: sáng / tối / sepia) -----
  static const Color sepia = Color(0xFFF3E7D3);
  static const Color sepiaInk = Color(0xFF40372A);
}

/// Tên 2 font bundle trong pubspec.yaml.
class AppFonts {
  const AppFonts._();

  /// Sans-serif cho tiêu đề / UI.
  static const String ui = 'BeVietnamPro';

  /// Serif cho nội dung chương (dễ đọc khi đọc truyện dài).
  static const String reading = 'NotoSerif';
}

/// Số bo góc dùng trong app — không hard-code trong widget.
class AppRadius {
  const AppRadius._();

  static const double card = 16; // card bo 16px
  static const double control = 12; // nút / ô nhập
  static const double sheet = 24; // bottom sheet / dialog bo góc trên
  static const double pill = 24; // viên thuốc của bottom nav
  static const double round = 999; // chip bo tròn hoàn toàn
}

class AppTheme {
  const AppTheme._();

  /// Chủ đề sáng.
  static ThemeData light() => _build(Brightness.light);

  /// Chủ đề tối.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color background = isDark ? AppColors.night : AppColors.paper;
    final Color surface = isDark ? AppColors.cardNight : AppColors.card;
    final Color textColor = isDark ? AppColors.inkNight : AppColors.ink;
    final Color mutedColor = isDark
        ? AppColors.inkMutedNight
        : AppColors.inkMuted;
    final Color borderColor = isDark ? AppColors.borderNight : AppColors.border;

    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.white,
          secondary: AppColors.accent,
          onSecondary: AppColors.white,
          surface: surface,
          onSurface: textColor,
          onSurfaceVariant: mutedColor, // chữ phụ lấy từ theme
          outline: borderColor, // viền mảnh
          outlineVariant: borderColor,
          error: AppColors.accent,
          onError: AppColors.white,
        );

    final TextTheme textTheme = _textTheme(textColor);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      // Card: bo góc 16, viền mảnh, không đổ bóng nặng
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      // Dialog: bo góc 20, viền mảnh, cùng font/chữ với theme
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          side: BorderSide(color: borderColor),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      // BottomSheet: bo góc trên 24 + tay cầm kéo nhỏ ở trên (C6)
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: borderColor,
        dragHandleSize: const Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          side: BorderSide(color: borderColor),
        ),
      ),
      // Chuyển trang: fade + trượt lên nhẹ (~300ms chuẩn Material), không zoom nặng
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.primary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: mutedColor),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: BorderSide(color: borderColor),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.round),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? surface : AppColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? AppColors.inkNight : AppColors.white,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: mutedColor,
        textColor: textColor,
        titleTextStyle: textTheme.bodyLarge,
      ),
    );
  }

  /// Thang chữ của app: UI dùng font sans-serif Be Vietnam Pro.
  static TextTheme _textTheme(Color color) {
    const String font = AppFonts.ui;
    return TextTheme(
      displaySmall: TextStyle(
        fontFamily: font,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: color,
      ),
      headlineSmall: TextStyle(
        fontFamily: font,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: color,
      ),
      titleLarge: TextStyle(
        fontFamily: font,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: color,
      ),
      titleMedium: TextStyle(
        fontFamily: font,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: color,
      ),
      titleSmall: TextStyle(
        fontFamily: font,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: color,
      ),
      bodyLarge: TextStyle(
        fontFamily: font,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      ),
      bodyMedium: TextStyle(
        fontFamily: font,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      ),
      bodySmall: TextStyle(
        fontFamily: font,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      ),
      labelLarge: TextStyle(
        fontFamily: font,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      ),
      labelMedium: TextStyle(
        fontFamily: font,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      ),
      labelSmall: TextStyle(
        fontFamily: font,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: color,
      ),
    );
  }
}

/// Style cho nội dung chương truyện: font serif Noto Serif, giãn dòng để dễ đọc.
/// Dùng ở màn hình đọc (Bước 5), không hard-code màu trong widget.
TextStyle chapterStyle(
  BuildContext context, {
  double fontSize = 18,
  double height = 1.7,
}) {
  final TextTheme text = Theme.of(context).textTheme;
  return (text.bodyLarge ?? const TextStyle()).copyWith(
    fontFamily: AppFonts.reading,
    fontSize: fontSize,
    height: height,
    fontWeight: FontWeight.w400,
  );
}
