import 'package:flutter/material.dart';

/// FitForge 设计系统：语义色 token。
///
/// 原则：
/// - 所有屏幕禁止直接使用 `Colors.xxx`（除 `Colors.transparent`）。
/// - 深色模式是主门面，浅色模式作为跟随，两套 token 同名配对。
/// - 颜色用途由名字决定，不由色值决定——"bgElevated" 永远是卡片背景。
class AppColors {
  AppColors._();

  // ──── Surface 层次（深色）────
  static const bgBase = Color(0xFF0A0B0F); // 最底层 Scaffold 背景
  static const bgElevated = Color(0xFF14161C); // 卡片/面板
  static const bgSurface = Color(0xFF1C1F27); // 悬浮元素（modal / sticky bar）
  static const border = Color(0xFF2A2E38); // 分隔线 / 描边 / 非激活边框

  // ──── Surface 层次（浅色，跟随态）────
  static const bgBaseLight = Color(0xFFF7F8FA);
  static const bgElevatedLight = Color(0xFFFFFFFF);
  static const bgSurfaceLight = Color(0xFFFFFFFF);
  static const borderLight = Color(0xFFE4E7EC);

  // ──── 品牌色 ────
  static const primary = Color(0xFFFF6B1A); // 燃脂橙
  static const primaryGlow = Color(0xFFFF8A3D); // 橙色高光（渐变用）
  static const primaryDim = Color(0xFFCC5515); // 按下/禁用态
  static const accent = Color(0xFF00E5A8); // 电光绿（成功 / PR / 解锁）
  static const accentDim = Color(0xFF00B386);
  static const danger = Color(0xFFFF3D5A);
  static const warning = Color(0xFFFFB020);

  // ──── 文本色（深色模式）────
  static const textPrimary = Color(0xFFF5F6F8);
  static const textSecondary = Color(0xFFA1A6B3);
  static const textTertiary = Color(0xFF6B7184);
  static const textInverse = Color(0xFF0A0B0F); // 亮色按钮上的文字

  // ──── 文本色（浅色模式，跟随态）────
  static const textPrimaryLight = Color(0xFF0F1115);
  static const textSecondaryLight = Color(0xFF5B6273);
  static const textTertiaryLight = Color(0xFF8B92A3);

  // ──── 渐变 ────
  static const heatGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B1A), Color(0xFFFF3D5A)],
  );

  static const ringGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF8A3D), Color(0xFFFFD12B)],
  );

  static const coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00E5A8), Color(0xFF2B8CFF)],
  );

  // ──── 部位色（动作库/训练分类用）────
  static const chest = Color(0xFFFF6B1A);
  static const back = Color(0xFF2B8CFF);
  static const legs = Color(0xFF9B5CFF);
  static const shoulders = Color(0xFFFFB020);
  static const arms = Color(0xFF00E5A8);
  static const core = Color(0xFFFF3D5A);
  static const cardio = Color(0xFFFF6B1A);
}
