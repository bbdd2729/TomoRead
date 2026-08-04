import 'package:flutter/material.dart';

import '../../domain/models/chat_models.dart';
import '../../domain/models/library_book.dart';
import 'chat_controller.dart';

class ChatThreadList extends StatelessWidget {
  const ChatThreadList({
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
