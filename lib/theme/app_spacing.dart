/// FitForge 设计系统：8pt 栅格间距 token。
///
/// 所有 padding / margin / SizedBox 必须使用这些常量。
/// 禁止硬编码 `EdgeInsets.all(7)` 这种非 8 倍数的魔数。
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// 屏幕水平内边距（所有屏幕统一）
  static const double screenH = 20;

  /// 卡片内边距（标准）
  static const double cardPad = 16;

  /// 卡片间距
  static const double cardGap = 12;
}
