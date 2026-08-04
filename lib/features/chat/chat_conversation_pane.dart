import 'package:flutter/material.dart';

import '../../domain/models/chat_models.dart';
import 'chat_controller.dart';
import 'chat_message_entry.dart';

class ChatConversationPane extends StatelessWidget {
  const ChatConversationPane({
    super.key,
    required this.chat,
    required this.promptController,
    required this.scrollController,
    required this.onConfigure,
    required this.onSend,
    required this.onStop,
    required this.onRetry,
    required this.onClearAttachment,
    required this.onClearSkill,
    required this.onOpenCitation,
    required this.followsOutput,
    required this.onScrollToBottom,
    this.onShowThreads,
  });

  final ChatPageState chat;
  final TextEditingController promptController;
  final ScrollController scrollController;
  final VoidCallback? onShowThreads;
  final VoidCallback onConfigure;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<ChatMessage> onRetry;
  final VoidCallback onClearAttachment;
  final VoidCallback onClearSkill;
  final ValueChanged<ChatCitation> onOpenCitation;
  final bool followsOutput;
  final VoidCallback onScrollToBottom;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
            child: Row(
              children: [
                if (onShowThreads != null)
                  IconButton(
                    tooltip: '对话列表',
                    onPressed: onShowThreads,
                    icon: const Icon(Icons.history),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.activeThread?.title.isNotEmpty == true
                            ? chat.activeThread!.title
                            : '新对话',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        chat.profile == null
                            ? '尚未配置模型'
                            : '${chat.profile!.name} · ${chat.profile!.modelId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '模型设置',
                  onPressed: onConfigure,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
          ),
        ),
        if (chat.profile == null)
          MaterialBanner(
            content: const Text('配置一个 OpenAI 兼容模型后即可开始对话。API Key 只保存在系统安全存储中。'),
            actions: [
              TextButton(onPressed: onConfigure, child: const Text('配置模型')),
            ],
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: chat.isLoadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : chat.messages.isEmpty
                    ? const _EmptyConversation()
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 64),
                        itemCount: chat.messages.length,
                        itemBuilder: (context, index) => ChatMessageEntry(
                          key: ValueKey(chat.messages[index].id),
                          message: chat.messages[index],
                          onOpenCitation: onOpenCitation,
                          onRetry: onRetry,
                        ),
                      ),
              ),
              if (!followsOutput && chat.messages.isNotEmpty)
                Positioned(
                  right: 20,
                  bottom: 14,
                  child: IconButton.filledTonal(
                    tooltip: '回到底部',
                    onPressed: onScrollToBottom,
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ),
            ],
          ),
        ),
        if (chat.errorMessage != null)
          Container(
            width: double.infinity,
            color: colors.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              chat.errorMessage!,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                children: [
                  if (chat.attachment != null)
                    _AttachedQuote(
                      attachment: chat.attachment!,
                      onRemove: onClearAttachment,
                    ),
                  if (chat.attachment != null && chat.selectedSkillId != null)
                    const SizedBox(height: 6),
                  if (chat.selectedSkillId != null)
                    _AttachedSkill(
                      skillId: chat.selectedSkillId!,
                      onRemove: onClearSkill,
                    ),
                  if (chat.attachment != null || chat.selectedSkillId != null)
                    const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('chat-composer'),
                          controller: promptController,
                          minLines: 1,
                          maxLines: 6,
                          enabled: !chat.isStreaming,
                          decoration: const InputDecoration(
                            hintText: '询问书中内容、概念或想法',
                          ),
                          onSubmitted: (_) {
                            if (!chat.isStreaming) onSend();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: chat.isStreaming ? '停止生成' : '发送',
                        onPressed: chat.isStreaming ? onStop : onSend,
                        icon: Icon(
                          chat.isStreaming ? Icons.stop : Icons.arrow_upward,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachedQuote extends StatelessWidget {
  const _AttachedQuote({required this.attachment, required this.onRemove});

  final ChatContextAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.format_quote, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${attachment.bookTitle} · ${attachment.chapterTitle ?? '当前章节'}\n${attachment.quote.replaceAll(RegExp(r'\s+'), ' ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: '移除引用',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    ),
  );
}

class _AttachedSkill extends StatelessWidget {
  const _AttachedSkill({required this.skillId, required this.onRemove});

  final String skillId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('已选择技能：${_skillDisplayName(skillId)}')),
          IconButton(
            tooltip: '移除技能',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    ),
  );
}

String _skillDisplayName(String id) => switch (id) {
  'chapter-summary' => '章节总结',
  'concept-explainer' => '概念解释',
  'structure-analysis' => '结构梳理',
  _ => id,
};

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 48),
          const SizedBox(height: 14),
          Text('从一个具体问题开始', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('在阅读器中选择原文后提问，可以得到带出处的回答。', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
