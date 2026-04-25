import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// FitForge 设计系统：字体 + TextTheme。
///
/// 中文 body → Noto Sans SC（思源黑体）
/// 数字/英文 → Manrope（geometric sans，tabular digits 对齐训练数据）
///
/// 字号节律基于 8pt 栅格：12 / 14 / 16 / 18 / 24 / 32
class AppTypography {
  AppTypography._();

  /// 组装完整 TextTheme（供 ThemeData.textTheme 使用）。
  /// [brightness] 决定默认文字颜色。
  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? AppColors.textPrimary
        : AppColors.textPrimaryLight;
    final secondary = brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.textSecondaryLight;

    // Noto Sans SC 基底
    final noto = GoogleFonts.notoSansScTextTheme(const TextTheme());

    return noto.copyWith(
      // Hero 数字（连续天数、总容量）
      displayLarge: _manrope(32, FontWeight.w800, base),
      displayMedium: _manrope(28, FontWeight.w700, base),
      displaySmall: _manrope(24, FontWeight.w700, base),

      // 屏幕标题
      headlineLarge: _noto(24, FontWeight.w700, base),
      headlineMedium: _noto(20, FontWeight.w600, base),
      headlineSmall: _noto(18, FontWeight.w600, base),

      // 卡片标题
      titleLarge: _noto(18, FontWeight.w600, base),
      titleMedium: _noto(16, FontWeight.w600, base),
      titleSmall: _noto(14, FontWeight.w600, base),

      // 正文
      bodyLarge: _noto(16, FontWeight.w400, base),
      bodyMedium: _noto(14, FontWeight.w400, base),
      bodySmall: _noto(12, FontWeight.w400, secondary),

      // 按钮 / 标签
      labelLarge: _manrope(14, FontWeight.w600, base),
      labelMedium: _manrope(12, FontWeight.w500, base),
      labelSmall: _manrope(11, FontWeight.w500, secondary),
    );
  }

  // ──── 帮助方法 ────

  static TextStyle _manrope(double size, FontWeight weight, Color color) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.3,
    );
  }

  static TextStyle _noto(double size, FontWeight weight, Color color) {
    return GoogleFonts.notoSansSc(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.4,
    );
  }
}
