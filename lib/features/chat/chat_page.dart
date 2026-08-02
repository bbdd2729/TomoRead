import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/ai_provider_catalog.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/epub_location.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/visual_artifact.dart';
import '../visualization/visual_artifact_widgets.dart';
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
    final followsOutput = useState(true);

    useEffect(() {
      void trackScrollPosition() {
        if (!scrollController.hasClients) return;
        final distance =
            scrollController.position.maxScrollExtent -
            scrollController.position.pixels;
        final shouldFollow = distance < 120;
        if (followsOutput.value != shouldFollow) {
          followsOutput.value = shouldFollow;
        }
      }

      scrollController.addListener(trackScrollPosition);
      return () => scrollController.removeListener(trackScrollPosition);
    }, [scrollController]);

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
    final streamingRevision = state.value?.messages.lastOrNull == null
        ? 0
        : state.value!.messages.last.content.length +
              (state
                      .value!
                      .messages
                      .last
                      .parts
                      .lastOrNull
                      ?.updatedAt
                      .microsecondsSinceEpoch ??
                  0);
    useEffect(() {
      if (!followsOutput.value) return null;
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
    }, [messageCount, streamingRevision, followsOutput.value]);

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
      if (book.format == 'txt' || book.format == 'markdown') {
        await ref
            .read(bookRepositoryProvider)
            .updateReadingPosition(
              bookId: book.id,
              chapterIndex: index,
              progress: book.chapterCount <= 1
                  ? 0
                  : index / (book.chapterCount - 1),
              locator: citation.locator,
            );
        ref.invalidate(readerBookProvider(book.id));
        ref.invalidate(libraryBooksProvider);
        if (context.mounted) onOpenReader!(book);
        return;
      }
      final cfi = citation.locator.startsWith('cfi:')
          ? citation.locator.substring(4)
          : null;
      final sourceRatio = citation.locator.startsWith('ratio:')
          ? double.tryParse(citation.locator.substring(6))
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
              scrollRatio: sourceRatio?.clamp(0, 1) ?? 0,
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
            onRetry: (message) =>
                ref.read(chatControllerProvider.notifier).retry(message),
            onClearAttachment: () =>
                ref.read(chatControllerProvider.notifier).clearAttachment(),
            onClearSkill: () =>
                ref.read(chatControllerProvider.notifier).clearSelectedSkill(),
            onOpenCitation: openCitation,
            followsOutput: followsOutput.value,
            onScrollToBottom: () {
              followsOutput.value = true;
              if (scrollController.hasClients) {
                scrollController.animateTo(
                  scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                );
              }
            },
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
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (chat.runningThreadId == thread.id)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            PopupMenuButton<String>(
                              tooltip: '会话操作',
                              onSelected: (value) => value == 'rename'
                                  ? onRename(thread)
                                  : onDelete(thread),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('重命名'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                              ],
                            ),
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
                        itemBuilder: (context, index) => _MessageEntry(
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

class _MessageEntry extends StatelessWidget {
  const _MessageEntry({
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
              child: _MessagePartView(
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

class _MessagePartView extends StatelessWidget {
  const _MessagePartView({
    super.key,
    required this.part,
    required this.onOpenCitation,
  });

  final ChatMessagePart part;
  final ValueChanged<ChatCitation> onOpenCitation;

  @override
  Widget build(BuildContext context) {
    final value = part;
    return switch (value) {
      ChatTextPart() => SelectionArea(child: MarkdownBody(data: value.text)),
      ChatReasoningPart() => _ReasoningPartView(part: value),
      ChatQuotePart() => _QuotePartView(part: value),
      ChatToolCallPart() => _ToolPartView(
        title: value.displayName,
        icon: Icons.build_outlined,
        status: value.status,
        argumentsJson: value.argumentsJson,
        result: value.result,
        error: value.error,
        durationMillis: value.durationMillis,
      ),
      ChatSkillCallPart() => _ToolPartView(
        title: value.skillName,
        icon: Icons.auto_awesome_outlined,
        status: value.status,
        argumentsJson: value.argumentsJson,
        result: value.result,
        error: value.error,
        durationMillis: value.durationMillis,
        skill: true,
      ),
      ChatCitationPart() => _CitationPartView(
        citation: value.citation,
        onOpen: onOpenCitation,
      ),
      ChatArtifactPart() => _ArtifactPartView(
        part: value,
        onOpenCitation: onOpenCitation,
      ),
      ChatNoticePart() => _NoticePartView(part: value),
      ChatAbortedPart() => _AbortedPartView(part: value),
    };
  }
}

class _ArtifactPartView extends StatelessWidget {
  const _ArtifactPartView({
    required this.part,
    required this.onOpenCitation,
  });

  final ChatArtifactPart part;
  final ValueChanged<ChatCitation> onOpenCitation;

  @override
  Widget build(BuildContext context) {
    VisualArtifactKind? kind;
    for (final value in VisualArtifactKind.values) {
      if (value.name == part.artifactType) kind = value;
    }
    if (kind == null) {
      return ListTile(
        leading: const Icon(Icons.data_object),
        title: Text(part.title),
        subtitle: Text('暂不支持的 Artifact 类型：${part.artifactType}'),
      );
    }
    final artifact = VisualArtifact(
      id: part.artifactId ?? part.id,
      bookId: part.bookId ?? '',
      kind: kind,
      scope: VisualArtifactScope.currentChapter,
      title: part.title,
      contentHash: '',
      payloadJson: part.payloadJson,
      createdAt: part.createdAt,
    );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(part.title),
        subtitle: Text(
          kind == VisualArtifactKind.wordCloud ? '词云 Artifact' : '思维导图 Artifact',
        ),
        children: [
          SizedBox(
            height: 420,
            child: VisualArtifactView(
              artifact: artifact,
              onOpenCitation: (citation) => onOpenCitation(
                ChatCitation(
                  id: 'artifact-${part.id}-${citation.locator}',
                  messageId: part.messageId,
                  ordinal: 1,
                  bookId: citation.bookId,
                  href: citation.href,
                  locator: citation.locator,
                  chapterIndex: citation.chapterIndex,
                  chapterTitle: citation.chapterTitle,
                  quote: citation.quote,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningPartView extends StatelessWidget {
  const _ReasoningPartView({required this.part});

  final ChatReasoningPart part;

  @override
  Widget build(BuildContext context) {
    final running = part.status == ChatPartStatus.running;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('${part.id}-${part.status.name}'),
        initiallyExpanded: running,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.psychology_outlined, size: 20),
        title: Text(running ? '思考中' : '思考摘要'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectionArea(child: MarkdownBody(data: part.text)),
          ),
        ],
      ),
    );
  }
}

class _QuotePartView extends StatelessWidget {
  const _QuotePartView({required this.part});

  final ChatQuotePart part;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: .55),
        border: Border(left: BorderSide(color: colors.secondary, width: 3)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${part.bookTitle} · ${part.chapterTitle ?? '当前章节'}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(part.quote, maxLines: 6, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _ToolPartView extends StatelessWidget {
  const _ToolPartView({
    required this.title,
    required this.icon,
    required this.status,
    required this.argumentsJson,
    this.result,
    this.error,
    this.durationMillis,
    this.skill = false,
  });

  final String title;
  final IconData icon;
  final ChatPartStatus status;
  final String argumentsJson;
  final String? result;
  final String? error;
  final int? durationMillis;
  final bool skill;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final running =
        status == ChatPartStatus.pending || status == ChatPartStatus.running;
    final failed = status == ChatPartStatus.error;
    final detail = error ?? result;
    return Material(
      color: skill
          ? colors.tertiaryContainer.withValues(alpha: .35)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: failed ? colors.error : colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('$title-${status.name}'),
        initiallyExpanded: failed,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(failed ? Icons.error_outline : icon, size: 20),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(switch (status) {
          ChatPartStatus.pending => '等待执行',
          ChatPartStatus.running => '正在执行',
          ChatPartStatus.completed =>
            durationMillis == null ? '已完成' : '已完成 · ${durationMillis}ms',
          ChatPartStatus.error => '执行失败',
        }),
        children: [
          if (argumentsJson.trim().isNotEmpty) ...[
            _TechnicalDetail(label: '参数', value: argumentsJson),
            if (detail != null) const SizedBox(height: 8),
          ],
          if (detail != null)
            _TechnicalDetail(label: failed ? '错误' : '结果', value: detail),
        ],
      ),
    );
  }
}

class _TechnicalDetail extends StatelessWidget {
  const _TechnicalDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectionArea(
          child: Text(
            value,
            maxLines: 12,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );
}

class _CitationPartView extends StatelessWidget {
  const _CitationPartView({required this.citation, required this.onOpen});

  final ChatCitation citation;
  final ValueChanged<ChatCitation> onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: CircleAvatar(radius: 12, child: Text('${citation.ordinal}')),
    title: Text(citation.chapterTitle ?? '引用原文'),
    subtitle: Text(
      citation.quote,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.open_in_new, size: 17),
    onTap: () => onOpen(citation),
  );
}

class _NoticePartView extends StatelessWidget {
  const _NoticePartView({required this.part});

  final ChatNoticePart part;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: part.level == ChatNoticeLevel.error
            ? colors.errorContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              part.level == ChatNoticeLevel.error
                  ? Icons.error_outline
                  : Icons.info_outline,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(part.message)),
          ],
        ),
      ),
    );
  }
}

class _AbortedPartView extends StatelessWidget {
  const _AbortedPartView({required this.part});

  final ChatAbortedPart part;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.stop_circle_outlined, size: 18),
      const SizedBox(width: 7),
      Text(part.reason, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
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

Future<void> _configureProvider(
  BuildContext context,
  WidgetRef ref,
  AiProviderProfile? profile,
) async {
  final catalog = ref.read(aiProviderCatalogProvider);
  final profiles = await ref.read(aiProviderRepositoryProvider).listProfiles();
  if (!context.mounted) return;
  var editing = profile;
  var preset = catalog.byId(profile?.presetId ?? 'openai');
  final name = TextEditingController(text: profile?.name ?? preset.displayName);
  final baseUrl = TextEditingController(
    text: profile?.baseUrl ?? preset.baseUrl,
  );
  final model = TextEditingController(text: profile?.modelId ?? '');
  final key = TextEditingController();
  var selectedProfileId = profile?.id;
  var selectedPresetId = preset.id;
  var toolsEnabled = profile?.toolsEnabled ?? preset.toolsByDefault;
  var reasoningEnabled =
      profile?.reasoningEnabled ?? preset.reasoningByDefault;
  var probeStatus = '';
  var fetchedModels = const <String>[];
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('AI 服务商与模型'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: selectedProfileId,
                  decoration: const InputDecoration(labelText: '配置方案'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('新建配置'),
                    ),
                    ...profiles.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item.id,
                        child: Text(
                          '${item.name}${item.isActive ? '（当前）' : ''}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (id) {
                    final next = id == null
                        ? null
                        : profiles.where((item) => item.id == id).firstOrNull;
                    setState(() {
                      editing = next;
                      selectedProfileId = next?.id;
                      preset = catalog.byId(next?.presetId ?? 'openai');
                      selectedPresetId = preset.id;
                      name.text = next?.name ?? preset.displayName;
                      baseUrl.text = next?.baseUrl ?? preset.baseUrl;
                      model.text = next?.modelId ?? '';
                      toolsEnabled =
                          next?.toolsEnabled ?? preset.toolsByDefault;
                      reasoningEnabled =
                          next?.reasoningEnabled ?? preset.reasoningByDefault;
                      key.clear();
                      probeStatus = '';
                      fetchedModels = const [];
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('provider-preset-$selectedPresetId'),
                  initialValue: selectedPresetId,
                  decoration: const InputDecoration(labelText: '服务商预设'),
                  items: AiProviderCatalog.presets
                      .where((item) => !item.deprecated)
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() {
                      final previousName = preset.displayName;
                      final previousUrl = preset.baseUrl;
                      preset = catalog.byId(id);
                      selectedPresetId = id;
                      if (name.text.trim().isEmpty ||
                          name.text == editing?.name ||
                          name.text == previousName) {
                        name.text = preset.displayName;
                      }
                      if (baseUrl.text.trim().isEmpty ||
                          baseUrl.text == previousUrl) {
                        baseUrl.text = preset.baseUrl;
                      }
                      toolsEnabled = preset.toolsByDefault;
                      reasoningEnabled = preset.reasoningByDefault;
                      probeStatus = '';
                      fetchedModels = const [];
                    });
                  },
                ),
                const SizedBox(height: 12),
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
                  decoration: const InputDecoration(
                    labelText: '模型',
                    hintText: '可手动输入，或从服务拉取',
                  ),
                ),
                if (fetchedModels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: fetchedModels
                          .take(12)
                          .map(
                            (id) => ActionChip(
                              label: Text(id),
                              onPressed: () => setState(() => model.text = id),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: preset.authType == AiProviderAuthType.none
                        ? 'API Key（本地服务通常不需要）'
                        : editing == null
                        ? 'API Key'
                        : 'API Key（留空保持不变）',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Agent 工具'),
                  subtitle: const Text('允许模型读取目录、标注和书中原文'),
                  value: toolsEnabled,
                  onChanged: (value) => setState(() => toolsEnabled = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('思考摘要'),
                  subtitle: const Text('显示服务返回的可见 reasoning 内容'),
                  value: reasoningEnabled,
                  onChanged: (value) =>
                      setState(() => reasoningEnabled = value),
                ),
                if (probeStatus.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(probeStatus),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (editing != null)
            TextButton.icon(
              onPressed: () async {
                setState(() => probeStatus = '正在测试连接…');
                try {
                  final result = await ref
                      .read(chatControllerProvider.notifier)
                      .probeProvider(editing!.id);
                  if (!context.mounted) return;
                  setState(() {
                    fetchedModels = result.models;
                    probeStatus = result.succeeded
                        ? '连接成功 · HTTP ${result.statusCode} · ${result.latencyMillis} ms${result.models.isEmpty ? '' : ' · ${result.models.length} 个模型'}'
                        : '连接失败：${result.errorCode} · HTTP ${result.statusCode ?? '-'}';
                  });
                } on Object catch (error) {
                  if (context.mounted) {
                    setState(() => probeStatus = '连接失败：$error');
                  }
                }
              },
              icon: const Icon(Icons.network_check),
              label: const Text('测试并拉取模型'),
            ),
          if (editing != null && !editing!.isActive)
            TextButton(
              onPressed: () async {
                await ref
                    .read(chatControllerProvider.notifier)
                    .activateProvider(editing!.id);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: const Text('设为当前'),
            ),
          if (editing != null)
            TextButton(
              onPressed: () async {
                await ref
                    .read(chatControllerProvider.notifier)
                    .setProviderEnabled(editing!.id, !editing!.isEnabled);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: Text(editing!.isEnabled ? '停用' : '启用'),
            ),
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
    ),
  );
  if (saved != true) {
    name.dispose();
    baseUrl.dispose();
    model.dispose();
    key.dispose();
    return;
  }
  try {
    await ref
        .read(chatControllerProvider.notifier)
        .configureProvider(
          profileId: selectedProfileId,
          presetId:
              selectedPresetId == 'custom' ||
                  baseUrl.text.trim() != preset.baseUrl
              ? 'custom'
              : selectedPresetId,
          authType: preset.authType,
          supportsModelList: preset.supportsModelList,
          name: name.text,
          baseUrl: baseUrl.text,
          modelId: model.text,
          apiKey: key.text,
          toolsEnabled: toolsEnabled,
          reasoningEnabled: reasoningEnabled,
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
