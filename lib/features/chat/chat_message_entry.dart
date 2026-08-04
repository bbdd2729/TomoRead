import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/chat_models.dart';
import 'widgets/chat_message_part_view.dart';

class ChatMessageEntry extends StatelessWidget {
  const ChatMessageEntry({
    super.key,
    required this.message,
    required this.onOpenCitation,
    required this.onRetry,
  });

  final ChatMessage message;
  final ValueChanged<ChatCitation> onOpenCitation;
  final ValueChanged<ChatMessage> onRetry;

  @override
  Widget build(BuildContext context) {
    final user = message.role == ChatRole.user;
    final colors = Theme.of(context).colorScheme;
    final parts = message.parts.isEmpty && message.content.isNotEmpty
        ? <ChatMessagePart>[
            ChatTextPart(
              id: 'display-${message.id}',
              messageId: message.id,
              ordinal: 0,
              status: ChatPartStatus.completed,
              createdAt: message.createdAt,
              updatedAt: message.completedAt ?? message.createdAt,
              text: message.content,
            ),
          ]
        : message.parts;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parts.isEmpty && message.status == ChatMessageStatus.streaming)
          const _StreamingIndicator(label: '正在组织回答')
        else
          ...parts.map(
            (part) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ChatMessagePartView(
                key: ValueKey(part.id),
                part: part,
                onOpenCitation: onOpenCitation,
              ),
            ),
          ),
        if (!user) _MessageMeta(message: message, onRetry: onRetry),
      ],
    );
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: user
              ? Material(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(15, 13, 15, 3),
                    child: body,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                      child: const Icon(Icons.auto_awesome, size: 17),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: body),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({required this.message, required this.onRetry});

  final ChatMessage message;
  final ValueChanged<ChatMessage> onRetry;

  @override
  Widget build(BuildContext context) {
    final usage = message.usage;
    final failed =
        message.status == ChatMessageStatus.failed ||
        message.status == ChatMessageStatus.cancelled;
    return Row(
      children: [
        if (message.status == ChatMessageStatus.streaming)
          const _StreamingIndicator(label: '正在生成')
        else ...[
          if (message.modelId != null)
            Flexible(
              child: Text(
                message.modelId!,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          if (usage != null && usage.totalTokens > 0) ...[
            const SizedBox(width: 8),
            Text(
              '${usage.totalTokens} tokens',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          const Spacer(),
          if (message.content.isNotEmpty)
            IconButton(
              tooltip: '复制回答',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: message.content)),
              icon: const Icon(Icons.copy_outlined, size: 17),
            ),
          if (failed)
            IconButton(
              tooltip: '重试',
              visualDensity: VisualDensity.compact,
              onPressed: () => onRetry(message),
              icon: const Icon(Icons.refresh, size: 18),
            ),
        ],
      ],
    );
  }
}

class _StreamingIndicator extends StatelessWidget {
  const _StreamingIndicator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 8),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}
