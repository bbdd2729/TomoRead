import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/epub_location.dart';
import '../../domain/models/library_book.dart';
import 'ai_provider_configuration_dialog.dart';
import 'chat_conversation_pane.dart';
import 'chat_controller.dart';
import 'chat_thread_list.dart';

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
          ).showSnackBar(const SnackBar(content: Text('تمت إزالة الكتاب المقابل للمرجع.')));
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
          label: Text('إعادة تحميل المحادثة: $error'),
        ),
      ),
      data: (chat) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 800;
          final threadList = ChatThreadList(
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
          final conversation = ChatConversationPane(
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
            onConfigure: () => configureAiProvider(context, ref, chat.profile),
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

Future<void> _createBookThread(
  BuildContext context,
  WidgetRef ref,
  List<LibraryBook> books,
) async {
  if (books.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('لا توجد كتب في المكتبة حتى الآن.')));
    return;
  }
  String? selectedId = books.first.id;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('محادثة كتاب جديد'),
        content: DropdownButtonFormField<String>(
          initialValue: selectedId,
          decoration: const InputDecoration(labelText: 'الكتب'),
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
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, selectedId),
            child: const Text('أنشئ'),
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
      title: const Text('إعادة تسمية المحادثة'),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('حفظ'),
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
      title: const Text('هل تريد حذف هذه المحادثة ؟'),
      content: const Text('سيتم حذف الرسائل والمراجع المحفوظة محليًا معًا.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(chatControllerProvider.notifier).deleteThread(thread);
  }
}
