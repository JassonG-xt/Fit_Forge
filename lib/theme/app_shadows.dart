import 'package:flutter/material.dart';
import 'app_colors.dart';

/// FitForge 设计系统：浅色卡片阴影 + 低饱和品牌阴影。
class AppShadows {
  AppShadows._();

  // ──── 深色模式用 ────

  /// 卡片悬浮：底部微弱边缘光
  static List<BoxShadow> cardGlow = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  /// 品牌高亮：CTA 按钮 / 当前组卡片
  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.18),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  /// 成功/解锁发光
  static List<BoxShadow> accentGlow = [
    BoxShadow(
      color: AppColors.accent.withValues(alpha: 0.25),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  // ──── 浅色模式用 ────

  /// 卡片标准阴影
  static List<BoxShadow> cardElevation = [
    BoxShadow(
      color: const Color(0xFF12352A).withValues(alpha: 0.08),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}
