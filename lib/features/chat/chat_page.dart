import 'package:flutter/material.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final thread = _ChatThread(
        onShowHistory: compact
            ? () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => const SafeArea(
                  top: false,
                  child: SizedBox(height: 440, child: _ChatHistory()),
                ),
              )
            : null,
      );
      if (compact) return thread;

      return Row(
        children: [
          const SizedBox(width: 280, child: _ChatHistory()),
          const VerticalDivider(width: 1),
          Expanded(child: thread),
        ],
      );
    },
  );
}

class _ChatHistory extends StatelessWidget {
  const _ChatHistory();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Text('AI 对话', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('围绕你的书籍提问与整理。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('新建对话'),
            ),
          ),
          const SizedBox(height: 28),
          Text('最近', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.chat_bubble_outline),
            title: Text('关于阅读的几个问题'),
            subtitle: Text('刚刚'),
            selected: true,
          ),
          const ListTile(
            leading: Icon(Icons.chat_bubble_outline),
            title: Text('本周阅读计划'),
            subtitle: Text('昨天'),
          ),
        ],
      ),
    );
  }
}

class _ChatThread extends StatelessWidget {
  const _ChatThread({this.onShowHistory});

  final VoidCallback? onShowHistory;

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
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
            child: Row(
              children: [
                if (onShowHistory != null)
                  IconButton(
                    tooltip: '对话列表',
                    onPressed: onShowHistory,
                    icon: const Icon(Icons.history_outlined),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '关于阅读的几个问题',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '基于当前阅读上下文',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '更多操作',
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
        ),
        const Expanded(child: _ChatMessages()),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: TextField(
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '询问书中的内容、概念或想法',
                  suffixIcon: IconButton.filled(
                    tooltip: '发送',
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatMessages extends StatelessWidget {
  const _ChatMessages();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('这本书的核心观点是什么？'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('这里会展示基于当前书籍内容生成的回答，并附带可跳转的出处。'),
            ),
          ),
        ),
      ],
    );
  }
}
