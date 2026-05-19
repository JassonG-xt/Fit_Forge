import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../agent/agent_event_log.dart';
import '../../agent/agent_runtime.dart';
import '../../agent/agent_service.dart';
import '../../agent/models/agent_action.dart';
import '../../agent/models/agent_message.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import 'agent_action_card.dart';
import 'agent_message_bubble.dart';
import 'agent_privacy_banner.dart';
import 'agent_safety_banner.dart';
import 'suggested_prompt_bar.dart';
import 'widgets/coach_avatar.dart';
import 'widgets/coach_thinking_dots.dart';

const _suggestedPrompts = <String>[
  '帮我总结这周训练',
  '今天只有 30 分钟，帮我压缩训练',
  '我这周只能周二、周四、周日练，帮我重新安排',
  '没有杠铃，帮我替换深蹲',
  '我午餐吃多了，晚餐怎么安排',
  '帮我生成一份新训练计划',
];

/// FitForge Coach 主聊天页。
///
/// 顶栏 + 消息列表 + 输入栏。assistant 消息可附带 Action Card；
/// 当 AgentResponse.safety.shouldStopWorkout=true 时（暂存于
/// AgentService.lastSafetyConcern）顶部显示醒目 banner。
class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _privacyBannerDismissed = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _input.clear();
    final service = context.read<AgentService>();
    await service.sendUserMessage(trimmed);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = context.watch<AgentRuntime>();
    return Scaffold(
      appBar: _CoachAppBar(
        runtime: runtime,
        onShowPrivacy: () => _showPrivacyDialog(context, runtime),
      ),
      body: Consumer<AgentService>(
        builder: (context, service, _) {
          final messages = service.messages;
          final showSafetyBanner = messages.any(
            (m) =>
                m.actions.any((a) => a.type == AgentActionType.safetyResponse),
          );

          if (messages.isNotEmpty) _scrollToBottom();

          return Column(
            children: [
              if (showSafetyBanner)
                const AgentSafetyBanner(
                  disclaimer: '检测到潜在健康风险。请优先停止训练并咨询专业医疗人员。',
                ),
              if (!_privacyBannerDismissed)
                AgentPrivacyBanner(
                  runtime: runtime,
                  onDismiss: () =>
                      setState(() => _privacyBannerDismissed = true),
                  onClearLogs: () async {
                    final log = context.read<AgentEventLog>();
                    final messenger = ScaffoldMessenger.of(context);
                    await log.clear();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('本地 AI 教练日志已清除')),
                    );
                  },
                ),
              Expanded(
                child: messages.isEmpty
                    ? const _EmptyState()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return _MessageItem(
                            message: message,
                            isResolved: service.isActionResolved,
                            onConfirm: (action) =>
                                _confirmAction(service, action),
                            onCancel: service.cancelAction,
                          );
                        },
                      ),
              ),
              if (service.isSending) const CoachThinkingDots(),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              SuggestedPromptBar(
                prompts: _suggestedPrompts,
                enabled: !service.isSending,
                onTapPrompt: _send,
              ),
              const SizedBox(height: AppSpacing.sm),
              _InputBar(
                controller: _input,
                disabled: service.isSending,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAction(AgentService service, AgentAction action) async {
    final result = await service.confirmAction(action);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.title}: ${result.message}'),
        backgroundColor: result.success ? AppColors.primary : AppColors.danger,
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context, AgentRuntime runtime) {
    final modeLine = runtime.isHttp
        ? '当前是「在线」模式（HTTP 后端：${runtime.baseUrl}）。\n\n'
              '为了让 Coach 给出有依据的建议，App 会把以下必要上下文发送到后端：\n'
              '· 训练目标、经验级、周频率\n'
              '· 当前训练计划与今日训练\n'
              '· 最近 10 条已完成训练记录摘要\n'
              '· 最近 10 条身体指标摘要\n'
              '· 动作库的精简元数据（不含详细教学）'
        : '当前是「本地 Mock」模式：所有响应在客户端生成，不会发送任何数据到后端。';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('隐私和安全'),
        content: SingleChildScrollView(
          child: Text(
            '$modeLine\n\n'
            '所有训练计划修改都需要你点「应用修改」后才会写入本地数据。\n\n'
            'FitForge Coach 提供通用健身和营养建议，不构成医疗诊断或治疗。'
            '出现胸痛、晕厥、严重头晕、呼吸困难或急性损伤时，请停止训练并咨询专业医疗人员。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  AppBar —— Coach 头像 + 标题 + 模式徽章 + 隐私入口
// ════════════════════════════════════════════
class _CoachAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _CoachAppBar({required this.runtime, required this.onShowPrivacy});

  final AgentRuntime runtime;
  final VoidCallback onShowPrivacy;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isHttp = runtime.isHttp;
    final modeAccent = isHttp ? AppColors.accent : AppColors.primary;

    return AppBar(
      titleSpacing: AppSpacing.screenH,
      title: Row(
        children: [
          const CoachAvatar(size: 36),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FitForge Coach',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppColors.textPrimary
                        : AppColors.textPrimaryLight,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: modeAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: modeAccent.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isHttp ? 'AI 教练 · 在线' : 'AI 教练 · 本地',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark
                            ? AppColors.textTertiary
                            : AppColors.textTertiaryLight,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '隐私和安全提示',
          icon: const Icon(Icons.privacy_tip_outlined),
          onPressed: onShowPrivacy,
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}

class _MessageItem extends StatelessWidget {
  const _MessageItem({
    required this.message,
    required this.isResolved,
    required this.onConfirm,
    required this.onCancel,
  });

  final AgentMessage message;
  final bool Function(String) isResolved;
  final void Function(AgentAction) onConfirm;
  final void Function(AgentAction) onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AgentMessageBubble(message: message),
        for (final action in message.actions)
          AgentActionCard(
            action: action,
            isResolved: isResolved(action.id),
            onConfirm: () => onConfirm(action),
            onCancel: () => onCancel(action),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════
//  Empty state —— Coach 能力展示
// ════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedText = isDark
        ? AppColors.textSecondary
        : AppColors.textSecondaryLight;

    final capabilities = <_Capability>[
      const _Capability(
        icon: Icons.auto_awesome_rounded,
        title: '训练计划生成',
        color: AppColors.primary,
      ),
      const _Capability(
        icon: Icons.swap_horiz_rounded,
        title: '动作替换',
        color: AppColors.shoulders,
      ),
      const _Capability(
        icon: Icons.compress_rounded,
        title: '训练压缩',
        color: AppColors.cardio,
      ),
      const _Capability(
        icon: Icons.insights_rounded,
        title: '周训练复盘',
        color: AppColors.accent,
      ),
      const _Capability(
        icon: Icons.restaurant_rounded,
        title: '饮食建议',
        color: AppColors.legs,
      ),
      const _Capability(
        icon: Icons.health_and_safety_rounded,
        title: '安全提醒',
        color: AppColors.danger,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.xl,
        AppSpacing.screenH,
        AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    const CoachAvatar(size: 80, haloOpacity: 0.28),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'FitForge Coach',
                      style: GoogleFonts.manrope(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppColors.textPrimary
                            : AppColors.textPrimaryLight,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '和你的 FitForge Coach 聊聊',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '可以问训练计划、动作替换、压缩训练，或直接选下面的常用问题。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: mutedText,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '能帮你做什么',
                    style: GoogleFonts.notoSansSc(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimary
                          : AppColors.textPrimaryLight,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 460 ? 3 : 2;
                  const gap = AppSpacing.cardGap;
                  final itemWidth =
                      (constraints.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: capabilities
                        .map(
                          (c) => SizedBox(
                            width: itemWidth,
                            child: _CapabilityTile(capability: c),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Capability {
  const _Capability({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({required this.capability});
  final _Capability capability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgElevated : AppColors.bgElevatedLight,
        borderRadius: AppRadius.brMd,
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.borderLight,
          width: 0.5,
        ),
        boxShadow: isDark ? null : AppShadows.cardElevation,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: capability.color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(capability.icon, color: capability.color, size: 18),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            capability.title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════
//  Input bar
// ════════════════════════════════════════════
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.disabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool disabled;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgSurface : AppColors.bgSurfaceLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.md,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.brXl,
          border: Border.all(
            color: isDark ? AppColors.border : AppColors.borderLight,
            width: 0.6,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                enabled: !disabled,
                textInputAction: TextInputAction.send,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: '问 FitForge Coach…',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.textTertiary
                        : AppColors.textTertiaryLight,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: disabled ? null : onSend,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _SendButton(
              disabled: disabled,
              onTap: disabled ? null : () => onSend(controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.disabled, required this.onTap});

  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Tooltip(
          message: '发送',
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: disabled ? null : AppColors.missionGradient,
              color: disabled
                  ? AppColors.textTertiary.withValues(alpha: 0.3)
                  : null,
              shape: BoxShape.circle,
              boxShadow: disabled
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: const Icon(
              Icons.arrow_upward_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
