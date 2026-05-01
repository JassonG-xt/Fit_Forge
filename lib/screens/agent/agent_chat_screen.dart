import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../agent/agent_service.dart';
import '../../agent/models/agent_action.dart';
import '../../agent/models/agent_message.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'agent_action_card.dart';
import 'agent_message_bubble.dart';
import 'agent_safety_banner.dart';
import 'suggested_prompt_bar.dart';

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
  bool _showedDisclaimer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_showedDisclaimer && mounted) {
        _showedDisclaimer = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('FitForge Coach 提供通用健身建议，不构成医疗建议。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FitForge Coach'),
        actions: [
          IconButton(
            tooltip: '隐私和安全提示',
            icon: const Icon(Icons.privacy_tip_outlined),
            onPressed: () => _showPrivacyDialog(context),
          ),
        ],
      ),
      body: Consumer<AgentService>(
        builder: (context, service, _) {
          final messages = service.messages;
          final showBanner = messages.any(
            (m) =>
                m.actions.any(
                  (a) => a.type == AgentActionType.safetyResponse,
                ),
          );

          if (messages.isNotEmpty) _scrollToBottom();

          return Column(
            children: [
              if (showBanner)
                const AgentSafetyBanner(
                  disclaimer: '检测到潜在健康风险。请优先停止训练并咨询专业医疗人员。',
                ),
              Expanded(
                child: messages.isEmpty
                    ? _EmptyState(theme: theme)
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
              if (service.isSending)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: _ThinkingIndicator(),
                ),
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

  Future<void> _confirmAction(
    AgentService service,
    AgentAction action,
  ) async {
    final result = await service.confirmAction(action);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.title}: ${result.message}'),
        backgroundColor: result.success ? AppColors.primary : AppColors.danger,
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('隐私和安全'),
        content: const Text(
          'FitForge Coach 在云端基于你当前的训练计划、训练历史和动作库生成建议。\n\n'
          '所有修改都需要你点击「应用修改」后才会写入本地数据。\n\n'
          'FitForge 不提供医疗诊断或治疗建议。',
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fitness_center,
              size: 48,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('和你的 FitForge Coach 聊聊', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '可以问训练计划、动作替换、压缩训练，或直接选下面的常用问题。',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: AppSpacing.sm),
        Text('Coach 正在思考…'),
      ],
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        0,
        AppSpacing.screenH,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              enabled: !disabled,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: '问 FitForge Coach…',
                border: OutlineInputBorder(borderRadius: AppRadius.brMd),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              onSubmitted: disabled ? null : onSend,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            onPressed: disabled ? null : () => onSend(controller.text),
            icon: const Icon(Icons.send),
            tooltip: '发送',
          ),
        ],
      ),
    );
  }
}
