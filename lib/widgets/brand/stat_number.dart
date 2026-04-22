import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 超大数字 + 细标签 —— 首页 Streak / 周统计 / 完成页汇总。
///
/// 数字使用 Manrope w800（tabular digits 对齐数据列），标签使用 theme body。
class StatNumber extends StatelessWidget {
  const StatNumber({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.fontSize = 32,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final double fontSize;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: valueColor ?? theme.colorScheme.primary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
