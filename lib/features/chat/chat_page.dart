import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/epub_location.dart';
import '../../domain/models/library_book.dart';
import 'chat_controller.dart';

class ChatPage extends HookConsumerWidget {
  const ChatPage({super.key, this.onOpenReader});

  final ValueChanged<LibraryBook>? onOpenReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final pending = ref.watch(pendingChatDraftProvider);
    final books =
        ref.watch(libraryBooksProvider).value ?? const <LibraryBook>[];
    final promptController = useTextEditingController();
    final scrollController = useScrollController();

    useEffect(() {
      if (pending != null) {
        Future<void>.microtask(() {
          ref.read(chatControllerProvider.notifier).attach(pending);
          ref.read(pendingChatDraftProvider.notifier).clear();
        });
      }
      return null;
    }, [pending]);

    final suggestedPrompt = state.value?.suggestedPrompt;
    useEffect(() {
      if (suggestedPrompt != null && suggestedPrompt.isNotEmpty) {
        promptController.text = suggestedPrompt;
        promptController.selection = TextSelection.collapsed(
          offset: promptController.text.length,
        );
      }
      return null;
    }, [suggestedPrompt]);

    final messageCount = state.value?.messages.length ?? 0;
    final streamingContentLength =
        state.value?.messages.lastOrNull?.content.length ?? 0;
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      });
      return null;
    }, [messageCount, streamingContentLength]);

    Future<void> openCitation(ChatCitation citation) async {
      final book = books
          .where((item) => item.id == citation.bookId)
          .firstOrNull;
      if (book == null || onOpenReader == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('引用对应的书籍已移除。')));
        }
        return;
      }
      final index = citation.chapterIndex ?? book.chapterIndex;
      final cfi = citation.locator.startsWith('cfi:')
          ? citation.locator.substring(4)
          : null;
      await ref
          .read(bookRepositoryProvider)
          .updateReadingPosition(
            bookId: book.id,
            chapterIndex: index,
            progress: book.chapterCount <= 1
                ? 0
                : index / (book.chapterCount - 1),
            locator: EpubLocation(
              chapterIndex: index,
              scrollRatio: 0,
              cfi: cfi,
            ).toLocator(),
          );
      ref.invalidate(readerBookProvider(book.id));
      ref.invalidate(libraryBooksProvider);
      if (context.mounted) onOpenReader!(book);
    }

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: FilledButton.icon(
          onPressed: () => ref.invalidate(chatControllerProvider),
          icon: const Icon(Icons.refresh),
          label: Text('重新加载对话：$error'),
        ),
      ),
      data: (chat) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 800;
          final threadList = _ChatThreadList(
            chat: chat,
            books: books,
            onSelected: (thread) => ref
                .read(chatControllerProvider.notifier)
                .selectThread(thread.id),
            onCreateGeneral: () =>
                ref.read(chatControllerProvider.notifier).createThread(),
            onCreateBook: () => _createBookThread(context, ref, books),
            onRename: (thread) => _renameThread(context, ref, thread),
            onDelete: (thread) => _deleteThread(context, ref, thread),
          );
          final conversation = _ConversationPane(
            chat: chat,
            promptController: promptController,
            scrollController: scrollController,
            onShowThreads: compact
                ? () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (context) => FractionallySizedBox(
                      heightFactor: .82,
                      child: threadList,
                    ),
                  )
                : null,
            onConfigure: () => _configureProvider(context, ref, chat.profile),
            onSend: () {
              final value = promptController.text;
              if (value.trim().isEmpty) return;
              promptController.clear();
              unawaited(ref.read(chatControllerProvider.notifier).send(value));
            },
            onStop: () => ref.read(chatControllerProvider.notifier).stop(),
            onClearAttachment: () =>
                ref.read(chatControllerProvider.notifier).clearAttachment(),
            onOpenCitation: openCitation,
          );
          if (compact) return conversation;
          return Row(
            children: [
              SizedBox(width: 288, child: threadList),
              const VerticalDivider(width: 1),
              Expanded(child: conversation),
            ],
          );
        },
      ),
    );
  }
}

class _ChatThreadList extends StatelessWidget {
  const _ChatThreadList({
    required this.chat,
    required this.books,
    required this.onSelected,
    required this.onCreateGeneral,
    required this.onCreateBook,
    required this.onRename,
    required this.onDelete,
  });

  final ChatPageState chat;
  final List<LibraryBook> books;
  final ValueChanged<ChatThread> onSelected;
  final VoidCallback onCreateGeneral;
  final VoidCallback onCreateBook;
  final ValueChanged<ChatThread> onRename;
  final ValueChanged<ChatThread> onDelete;

  @override
  Widget build(BuildContext context) {
    final bookMap = {for (final book in books) book.id: book};
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'AI 对话',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '新建对话',
                  onSelected: (value) =>
                      value == 'general' ? onCreateGeneral() : onCreateBook(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'general', child: Text('通用对话')),
                    PopupMenuItem(value: 'book', child: Text('书籍对话')),
                  ],
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: chat.threads.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '还没有对话。新建对话，或在阅读器中选择文字后询问 AI。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: chat.threads.length,
                    itemBuilder: (context, index) {
                      final thread = chat.threads[index];
                      final book = thread.bookId == null
                          ? null
                          : bookMap[thread.bookId];
                      return ListTile(
                        selected: thread.id == chat.activeThreadId,
                        leading: Icon(
                          thread.scope == ChatScope.book
                              ? Icons.auto_stories_outlined
                              : Icons.forum_outlined,
                        ),
                        title: Text(
                          thread.title.isEmpty ? '新对话' : thread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          thread.scope == ChatScope.general
                              ? '通用对话'
                              : book?.title ?? '书籍已移除',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: '会话操作',
                          onSelected: (value) => value == 'rename'
                              ? onRename(thread)
                              : onDelete(thread),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'rename', child: Text('重命名')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                        onTap: () => onSelected(thread),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.chat,
    required this.promptController,
    required this.scrollController,
    required this.onConfigure,
    required this.onSend,
    required this.onStop,
    required this.onClearAttachment,
    required this.onOpenCitation,
    this.onShowThreads,
  });

  final ChatPageState chat;
  final TextEditingController promptController;
  final ScrollController scrollController;
  final VoidCallback? onShowThreads;
  final VoidCallback onConfigure;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onClearAttachment;
  final ValueChanged<ChatCitation> onOpenCitation;

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
          child: chat.isLoadingMessages
              ? const Center(child: CircularProgressIndicator())
              : chat.messages.isEmpty
              ? const _EmptyConversation()
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                  itemCount: chat.messages.length,
                  itemBuilder: (context, index) => _MessageBubble(
                    message: chat.messages[index],
                    onOpenCitation: onOpenCitation,
                  ),
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
                  if (chat.attachment != null) const SizedBox(height: 8),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onOpenCitation});

  final ChatMessage message;
  final ValueChanged<ChatCitation> onOpenCitation;

  @override
  Widget build(BuildContext context) {
    final user = message.role == ChatRole.user;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Material(
            color: user ? colors.primaryContainer : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.content.isEmpty &&
                      message.status == ChatMessageStatus.streaming)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    SelectionArea(child: MarkdownBody(data: message.content)),
                  if (message.citations.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    ...message.citations.map(
                      (citation) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 12,
                          child: Text('${citation.ordinal}'),
                        ),
                        title: Text(citation.chapterTitle ?? '引用原文'),
                        subtitle: Text(
                          citation.quote,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.open_in_new, size: 17),
                        onTap: () => onOpenCitation(citation),
                      ),
                    ),
                  ],
                  if (message.status == ChatMessageStatus.failed ||
                      message.status == ChatMessageStatus.cancelled) ...[
                    const SizedBox(height: 8),
                    Text(
                      message.status == ChatMessageStatus.cancelled
                          ? '已停止生成'
                          : '生成失败',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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

Future<void> _configureProvider(
  BuildContext context,
  WidgetRef ref,
  AiProviderProfile? profile,
) async {
  final name = TextEditingController(
    text: profile?.name ?? 'OpenAI Compatible',
  );
  final baseUrl = TextEditingController(
    text: profile?.baseUrl ?? 'https://api.openai.com/v1',
  );
  final model = TextEditingController(text: profile?.modelId ?? 'gpt-4.1-mini');
  final key = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('模型设置'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: baseUrl,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: model,
              decoration: const InputDecoration(labelText: '模型'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: key,
              obscureText: true,
              decoration: InputDecoration(
                labelText: profile == null ? 'API Key' : 'API Key（留空保持不变）',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (saved != true) return;
  try {
    await ref
        .read(chatControllerProvider.notifier)
        .configureProvider(
          name: name.text,
          baseUrl: baseUrl.text,
          modelId: model.text,
          apiKey: key.text,
        );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存模型配置失败：$error')));
    }
  } finally {
    name.dispose();
    baseUrl.dispose();
    model.dispose();
    key.dispose();
  }
}

Future<void> _createBookThread(
  BuildContext context,
  WidgetRef ref,
  List<LibraryBook> books,
) async {
  if (books.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('书库中还没有书籍。')));
    return;
  }
  String? selectedId = books.first.id;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('新建书籍对话'),
        content: DropdownButtonFormField<String>(
          initialValue: selectedId,
          decoration: const InputDecoration(labelText: '书籍'),
          items: books
              .map(
                (book) =>
                    DropdownMenuItem(value: book.id, child: Text(book.title)),
              )
              .toList(),
          onChanged: (value) => setState(() => selectedId = value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, selectedId),
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
  if (result != null) {
    await ref
        .read(chatControllerProvider.notifier)
        .createThread(bookId: result);
  }
}

Future<void> _renameThread(
  BuildContext context,
  WidgetRef ref,
  ChatThread thread,
) async {
  final controller = TextEditingController(text: thread.title);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('重命名对话'),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result != null) {
    await ref
        .read(chatControllerProvider.notifier)
        .renameThread(thread, result);
  }
}

Future<void> _deleteThread(
  BuildContext context,
  WidgetRef ref,
  ChatThread thread,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除这段对话？'),
      content: const Text('本地保存的消息和引用将一并删除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(chatControllerProvider.notifier).deleteThread(thread);
  }
}
