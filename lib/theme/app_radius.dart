import 'package:flutter/material.dart';

/// FitForge 设计系统：圆角 token。
class AppRadius {
  AppRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double full = 999;

  // 便捷 BorderRadius 常量
  static final BorderRadius brSm = BorderRadius.circular(sm);
  static final BorderRadius brMd = BorderRadius.circular(md);
  static final BorderRadius brLg = BorderRadius.circular(lg);
  static final BorderRadius brXl = BorderRadius.circular(xl);
  static final BorderRadius brXxl = BorderRadius.circular(xxl);
  static final BorderRadius brFull = BorderRadius.circular(full);
}
