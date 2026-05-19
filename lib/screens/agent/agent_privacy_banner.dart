import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../agent/agent_runtime.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// Coach 页面顶部的隐私 + 安全说明横幅。
///
/// 文案根据 [AgentRuntime.mode] 区分本地 mock 与在线 HTTP 后端。
/// 用户可点击「我知道了」隐藏，状态由父级传入的 `onDismiss` 控制。
///
/// 视觉职责：紧凑、信息密度高，但 mode 状态徽章 + 隐私 icon 让"我们尊重数据"的
/// 含义不被弱化；不要让用户因为"看着不重要"而忽略。
class AgentPrivacyBanner extends StatelessWidget {
  const AgentPrivacyBanner({
    super.key,
    required this.runtime,
    required this.onDismiss,
    this.onClearLogs,
  });

  final AgentRuntime runtime;
  final VoidCallback onDismiss;
  final VoidCallback? onClearLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isHttp = runtime.isHttp;

    // 保留原文本字符串，测试依赖 `'本地 Mock 模式：不会向任何后端发送数据'` /
    // `'在线模式'` / `displayHost(baseUrl)` 这几条 textContaining 断言。
    final modeLine = isHttp
        ? '在线模式：会把你的训练目标、当前计划、今日训练、最近记录摘要发送到 ${_displayHost(runtime.baseUrl)}。'
        : '本地 Mock 模式：不会向任何后端发送数据。';

    final modeAccent = isHttp ? AppColors.accent : AppColors.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.sm,
        AppSpacing.screenH,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.bgSurface.withValues(alpha: 0.6)
            : AppColors.bgSurfaceLight,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: modeAccent.withValues(alpha: 0.30),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: modeAccent.withValues(alpha: 0.16),
                  borderRadius: AppRadius.brSm,
                ),
                child: Icon(
                  isHttp ? Icons.cloud_outlined : Icons.shield_outlined,
                  color: modeAccent,
                  size: 16,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: modeAccent.withValues(alpha: 0.16),
                  borderRadius: AppRadius.brSm,
                ),
                child: Text(
                  isHttp ? 'ONLINE' : 'LOCAL',
                  style: GoogleFonts.manrope(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: modeAccent,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            modeLine,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '所有训练计划修改都需要你点「应用修改」后才会生效。Coach 不构成医疗建议；'
            '出现胸痛、晕厥、严重头晕、呼吸困难或急性损伤时请停止训练并咨询专业医疗人员。',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (onClearLogs != null)
                TextButton.icon(
                  onPressed: onClearLogs,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('清除本地 AI 教练日志'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                )
              else
                const SizedBox.shrink(),
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(foregroundColor: modeAccent),
                child: const Text('我知道了'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _displayHost(String baseUrl) {
    if (baseUrl.isEmpty) return '后端';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return baseUrl;
    return uri.host;
  }
}
