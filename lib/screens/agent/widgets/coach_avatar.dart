import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

/// FitForge Coach 视觉身份的圆形头像。
///
/// 在四个位置反复出现，保持 Coach 是"一个东西"而不是散乱的 UI 片段：
///   1. AgentChatScreen AppBar 左侧
///   2. EmptyState 大 Hero
///   3. AgentMessageBubble 每条 Coach 消息的左侧
///   4. AgentActionCard 当 action.type 没有专属图标时回退
///
/// 默认使用 [AppColors.missionGradient]（与首页 Coach 入口卡 + 今日训练 header 一致）。
/// [icon] 默认 `auto_awesome`（"AI 闪光"），可被 action type icon 替换。
class CoachAvatar extends StatelessWidget {
  const CoachAvatar({
    super.key,
    this.size = 36,
    this.icon = Icons.auto_awesome_rounded,
    this.gradient,
    this.haloOpacity = 0.22,
  });

  final double size;
  final IconData icon;
  final Gradient? gradient;

  /// 外圈 halo 的最大透明度；0 时关闭 halo（用于紧凑的 AppBar 场景）。
  final double haloOpacity;

  @override
  Widget build(BuildContext context) {
    final hasHalo = haloOpacity > 0;
    final coreSize = hasHalo ? size * 0.78 : size;
    final iconSize = size * 0.5;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (hasHalo)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: haloOpacity),
                    AppColors.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          Container(
            width: coreSize,
            height: coreSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient ?? AppColors.missionGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ],
      ),
    );
  }
}
