import 'package:flutter/material.dart';

/// FitForge 设计系统：语义色 token。
///
/// 视觉方向：浅色优先、清爽运动感、低饱和数据色。页面应通过语义色取色，
/// 不直接依赖具体色值。
class AppColors {
  AppColors._();

  // ──── Surface 层次（深色）────
  static const bgBase = Color(0xFF111817);
  static const bgElevated = Color(0xFF18211F);
  static const bgSurface = Color(0xFF202C29);
  static const border = Color(0xFF30413D);

  // ──── Surface 层次（浅色，跟随态）────
  static const bgBaseLight = Color(0xFFF5F8F6);
  static const bgElevatedLight = Color(0xFFFFFFFF);
  static const bgSurfaceLight = Color(0xFFEEF5F1);
  static const borderLight = Color(0xFFDDE8E2);

  // ──── 品牌色 ────
  static const primary = Color(0xFF18C787);
  static const primaryGlow = Color(0xFF75E8B6);
  static const primaryDim = Color(0xFF0E9564);
  static const accent = Color(0xFF3E7BFA);
  static const accentDim = Color(0xFF2F63D4);
  static const danger = Color(0xFFE85D75);
  static const warning = Color(0xFFF4B84A);

  // ──── 文本色（深色模式）────
  static const textPrimary = Color(0xFFF3F7F5);
  static const textSecondary = Color(0xFFB1BDB8);
  static const textTertiary = Color(0xFF7F8C87);
  static const textInverse = Color(0xFFFFFFFF);

  // ──── 文本色（浅色模式，跟随态）────
  static const textPrimaryLight = Color(0xFF17211E);
  static const textSecondaryLight = Color(0xFF5D6B66);
  static const textTertiaryLight = Color(0xFF91A09A);

  // ──── 渐变 ────
  static const heatGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF18C787), Color(0xFF54DCA6)],
  );

  static const ringGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF18C787), Color(0xFF7BE7B9)],
  );

  static const coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF18C787), Color(0xFF3E7BFA)],
  );

  static const freshGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE9FFF5), Color(0xFFFFFFFF)],
  );

  // ──── 部位色（动作库/训练分类用）────
  static const chest = Color(0xFF18C787);
  static const back = Color(0xFF3E7BFA);
  static const legs = Color(0xFF7C6DF2);
  static const shoulders = Color(0xFFF4B84A);
  static const arms = Color(0xFF0DAE75);
  static const core = Color(0xFFE85D75);
  static const cardio = Color(0xFF1CB6B0);
}
