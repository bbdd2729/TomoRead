import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/chat_models.dart';
import '../database/app_database.dart';

class ChatRepository {
  ChatRepository(this._database);

  final AppDatabase _database;

  Future<List<ChatThread>> listThreads() async {
    final database = await _database.database;
    final rows = await database.query(
      'chat_threads',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_threadFromRow).toList();
  }

  Future<ChatThread> createThread({
    required ChatScope scope,
    String? bookId,
    String title = '',
  }) async {
    final now = DateTime.now();
    final thread = ChatThread(
      id: 'thread-${now.microsecondsSinceEpoch}',
      scope: scope,
      bookId: bookId,
      title: title.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final database = await _database.database;
    await database.insert('chat_threads', {
      'id': thread.id,
      'scope': thread.scope.name,
      'book_id': thread.bookId,
      'title': thread.title,
      'created_at': thread.createdAt.millisecondsSinceEpoch,
      'updated_at': thread.updatedAt.millisecondsSinceEpoch,
    });
    return thread;
  }

  Future<void> renameThread(String id, String title) async {
    final database = await _database.database;
    await database.update(
      'chat_threads',
      {
        'title': title.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touchThread(String id) async {
    final database = await _database.database;
    await database.update(
      'chat_threads',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteThread(String id) async {
    final database = await _database.database;
    await database.delete('chat_threads', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChatMessage>> listMessages(String threadId) async {
    final database = await _database.database;
    final rows = await database.query(
      'chat_messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
    if (rows.isEmpty) return const [];
    final ids = rows.map((row) => row['id']! as String).toList();
    final citationRows = await database.rawQuery('''
        SELECT * FROM chat_message_citations
        WHERE message_id IN (${List.filled(ids.length, '?').join(', ')})
        ORDER BY ordinal ASC
      ''', ids);
    final citations = <String, List<ChatCitation>>{};
    for (final row in citationRows) {
      citations
          .putIfAbsent(row['message_id']! as String, () => <ChatCitation>[])
          .add(_citationFromRow(row));
    }
    return rows
        .map(
          (row) =>
              _messageFromRow(row, citations[row['id']! as String] ?? const []),
        )
        .toList();
  }

  Future<void> insertMessage(ChatMessage message) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await _insertOrUpdateMessage(transaction, message, insert: true);
      await _replaceCitations(transaction, message.id, message.citations);
      await transaction.update(
        'chat_threads',
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [message.threadId],
      );
    });
  }

  Future<void> updateMessage(ChatMessage message) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await _insertOrUpdateMessage(transaction, message, insert: false);
      await _replaceCitations(transaction, message.id, message.citations);
    });
  }

  Future<void> _insertOrUpdateMessage(
    DatabaseExecutor database,
    ChatMessage message, {
    required bool insert,
  }) async {
    final values = {
      'id': message.id,
      'thread_id': message.threadId,
      'role': message.role.name,
      'content': message.content,
      'status': message.status.name,
      'model_id': message.modelId,
      'error_code': message.errorCode,
      'created_at': message.createdAt.millisecondsSinceEpoch,
      'completed_at': message.completedAt?.millisecondsSinceEpoch,
    };
    if (insert) {
      await database.insert('chat_messages', values);
    } else {
      await database.update(
        'chat_messages',
        values,
        where: 'id = ?',
        whereArgs: [message.id],
      );
    }
  }

  Future<void> _replaceCitations(
    DatabaseExecutor database,
    String messageId,
    List<ChatCitation> citations,
  ) async {
    await database.delete(
      'chat_message_citations',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    for (final citation in citations) {
      await database.insert('chat_message_citations', {
        'id': citation.id,
        'message_id': messageId,
        'ordinal': citation.ordinal,
        'book_id': citation.bookId,
        'href': citation.href,
        'locator': citation.locator,
        'chapter_index': citation.chapterIndex,
        'chapter_title': citation.chapterTitle,
        'quote': citation.quote,
      });
    }
  }

  ChatThread _threadFromRow(Map<String, Object?> row) => ChatThread(
    id: row['id']! as String,
    scope: ChatScope.values.byName(row['scope']! as String),
    bookId: row['book_id'] as String?,
    title: row['title']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );

  ChatMessage _messageFromRow(
    Map<String, Object?> row,
    List<ChatCitation> citations,
  ) => ChatMessage(
    id: row['id']! as String,
    threadId: row['thread_id']! as String,
    role: ChatRole.values.byName(row['role']! as String),
    content: row['content']! as String,
    status: ChatMessageStatus.values.byName(row['status']! as String),
    modelId: row['model_id'] as String?,
    errorCode: row['error_code'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    completedAt: row['completed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['completed_at']! as int),
    citations: citations,
  );

  ChatCitation _citationFromRow(Map<String, Object?> row) => ChatCitation(
    id: row['id']! as String,
    messageId: row['message_id']! as String,
    ordinal: row['ordinal']! as int,
    bookId: row['book_id']! as String,
    href: row['href']! as String,
    locator: row['locator']! as String,
    chapterIndex: row['chapter_index'] as int?,
    chapterTitle: row['chapter_title'] as String?,
    quote: row['quote']! as String,
  );
}
