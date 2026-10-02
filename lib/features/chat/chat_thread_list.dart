import 'package:flutter/material.dart';

import '../../domain/models/chat_models.dart';
import '../../domain/models/library_book.dart';
import 'chat_controller.dart';

class ChatThreadList extends StatelessWidget {
  const ChatThreadList({
    super.key,
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
                    'محادثة الذكاء الاصطناعي',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'محادثة جديدة',
                  onSelected: (value) =>
                      value == 'general' ? onCreateGeneral() : onCreateBook(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'general', child: Text('المحادثات العامة')),
                    PopupMenuItem(value: 'book', child: Text('محادثات الكتاب')),
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
                        'لا توجد محادثات حتى الآن. أنشئ محادثة جديدة، أو اسأل الذكاء الاصطناعي بعد تحديد النص في القارئ.',
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
                          thread.title.isEmpty ? 'محادثة جديدة' : thread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          thread.scope == ChatScope.general
                              ? 'المحادثات العامة'
                              : book?.title ?? 'تمت إزالة الحجز',
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
                              tooltip: 'إجراءات الجلسة',
                              onSelected: (value) => value == 'rename'
                                  ? onRename(thread)
                                  : onDelete(thread),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('أعد التسمية'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('حذف'),
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
