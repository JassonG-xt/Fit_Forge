import 'package:flutter/material.dart';

import '../../agent/agent_runtime.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

/// Coach 页面顶部的隐私 + 安全说明横幅。
///
/// 文案根据 [AgentRuntime.mode] 区分本地 mock 与在线 HTTP 后端。
/// 用户可点击「我知道了」隐藏，状态由父级传入的 `onDismiss` 控制。
class AgentPrivacyBanner extends StatelessWidget {
  const AgentPrivacyBanner({
    super.key,
    required this.runtime,
    required this.onDismiss,
  });

  final AgentRuntime runtime;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHttp = runtime.isHttp;

    final modeLine = isHttp
        ? '在线模式：会把你的训练目标、当前计划、今日训练、最近记录摘要发送到 ${_displayHost(runtime.baseUrl)}。'
        : '本地 Mock 模式：不会向任何后端发送数据。';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.sm,
        AppSpacing.screenH,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.privacy_tip_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  modeLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '所有训练计划修改都需要你点「应用修改」后才会生效。Coach 不构成医疗建议；'
            '出现胸痛、晕厥、严重头晕、呼吸困难或急性损伤时请停止训练并咨询专业医疗人员。',
            style: theme.textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onDismiss, child: const Text('我知道了')),
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
