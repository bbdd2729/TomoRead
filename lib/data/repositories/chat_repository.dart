import 'dart:convert';

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

  Future<void> recoverInterruptedRuns() async {
    final database = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.transaction((transaction) async {
      await transaction.update(
        'chat_messages',
        {
          'status': ChatMessageStatus.cancelled.name,
          'error_code': 'app_interrupted',
          'completed_at': now,
        },
        where: 'status = ?',
        whereArgs: [ChatMessageStatus.streaming.name],
      );
      await transaction.update(
        'chat_message_parts',
        {'status': ChatPartStatus.error.name, 'updated_at': now},
        where: 'status IN (?, ?)',
        whereArgs: [ChatPartStatus.pending.name, ChatPartStatus.running.name],
      );
      await transaction.update(
        'ai_runs',
        {
          'status': AiRunStatus.cancelled.name,
          'error_code': 'app_interrupted',
          'completed_at': now,
        },
        where: 'status IN (?, ?, ?)',
        whereArgs: [
          AiRunStatus.queued.name,
          AiRunStatus.streaming.name,
          AiRunStatus.waitingForTool.name,
        ],
      );
    });
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
    final placeholders = List.filled(ids.length, '?').join(', ');
    final citationRows = await database.rawQuery('''
        SELECT * FROM chat_message_citations
        WHERE message_id IN ($placeholders)
        ORDER BY ordinal ASC
      ''', ids);
    final partRows = await database.rawQuery('''
        SELECT * FROM chat_message_parts
        WHERE message_id IN ($placeholders)
        ORDER BY message_id ASC, ordinal ASC
      ''', ids);
    final citations = <String, List<ChatCitation>>{};
    for (final row in citationRows) {
      citations
          .putIfAbsent(row['message_id']! as String, () => <ChatCitation>[])
          .add(_citationFromRow(row));
    }
    final parts = <String, List<ChatMessagePart>>{};
    for (final row in partRows) {
      parts
          .putIfAbsent(row['message_id']! as String, () => <ChatMessagePart>[])
          .add(_partFromRow(row));
    }
    return rows.map((row) {
      final messageId = row['id']! as String;
      return _messageFromRow(
        row,
        citations[messageId] ?? const [],
        parts[messageId] ?? const [],
      );
    }).toList();
  }

  Future<void> insertMessage(ChatMessage message) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await _insertOrUpdateMessage(transaction, message, insert: true);
      await _replaceCitations(transaction, message.id, message.citations);
      await _replaceParts(transaction, message);
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
      await _replaceParts(transaction, message);
    });
  }

  Future<void> insertRun({
    required String id,
    required String threadId,
    required String userMessageId,
    required String assistantMessageId,
    required String providerProfileId,
    required String modelId,
    required DateTime startedAt,
  }) async {
    final database = await _database.database;
    await database.insert('ai_runs', {
      'id': id,
      'thread_id': threadId,
      'user_message_id': userMessageId,
      'assistant_message_id': assistantMessageId,
      'provider_profile_id': providerProfileId,
      'model_id': modelId,
      'status': AiRunStatus.streaming.name,
      'started_at': startedAt.millisecondsSinceEpoch,
    });
  }

  Future<void> updateRun({
    required String id,
    required AiRunStatus status,
    AiUsage? usage,
    String? stopReason,
    String? errorCode,
    DateTime? completedAt,
  }) async {
    final database = await _database.database;
    await database.update(
      'ai_runs',
      {
        'status': status.name,
        'stop_reason': stopReason,
        'error_code': errorCode,
        'input_tokens': usage?.inputTokens,
        'output_tokens': usage?.outputTokens,
        'reasoning_tokens': usage?.reasoningTokens,
        'cached_tokens': usage?.cachedTokens,
        'completed_at': completedAt?.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertToolExecution({
    required String runId,
    required ChatMessagePart part,
  }) async {
    final values = switch (part) {
      ChatToolCallPart() => (
        callId: part.callId,
        name: part.toolName,
        kind: AiToolKind.read,
        arguments: part.argumentsJson,
        result: part.result,
        error: part.error,
        duration: part.durationMillis,
      ),
      ChatSkillCallPart() => (
        callId: part.callId,
        name: part.skillId,
        kind: AiToolKind.skill,
        arguments: part.argumentsJson,
        result: part.result,
        error: part.error,
        duration: part.durationMillis,
      ),
      _ => null,
    };
    if (values == null) return;
    final database = await _database.database;
    await database.insert('ai_tool_executions', {
      'id': 'tool-execution-$runId-${values.callId}',
      'run_id': runId,
      'part_id': part.id,
      'call_id': values.callId,
      'tool_name': values.name,
      'tool_kind': values.kind.name,
      'arguments_json': values.arguments,
      'result_text': values.result,
      'status': part.status.name,
      'error_message': values.error,
      'duration_ms': values.duration,
      'created_at': part.createdAt.millisecondsSinceEpoch,
      'updated_at': part.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      'input_tokens': message.usage?.inputTokens,
      'output_tokens': message.usage?.outputTokens,
      'reasoning_tokens': message.usage?.reasoningTokens,
      'cached_tokens': message.usage?.cachedTokens,
      'stop_reason': message.stopReason,
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

  Future<void> _replaceParts(
    DatabaseExecutor database,
    ChatMessage message,
  ) async {
    final parts = message.parts.isNotEmpty
        ? message.parts
        : message.content.isEmpty
        ? const <ChatMessagePart>[]
        : [
            ChatTextPart(
              id: 'text-${message.id}-0',
              messageId: message.id,
              ordinal: 0,
              status: message.status == ChatMessageStatus.streaming
                  ? ChatPartStatus.running
                  : ChatPartStatus.completed,
              createdAt: message.createdAt,
              updatedAt: message.completedAt ?? message.createdAt,
              text: message.content,
            ),
          ];
    if (parts.isEmpty) {
      await database.delete(
        'chat_message_parts',
        where: 'message_id = ?',
        whereArgs: [message.id],
      );
      return;
    }
    final ids = parts.map((part) => part.id).toList();
    await database.delete(
      'chat_message_parts',
      where:
          'message_id = ? AND id NOT IN (${List.filled(ids.length, '?').join(', ')})',
      whereArgs: [message.id, ...ids],
    );
    for (final part in parts) {
      final encoded = _partToRow(part);
      await database.insert(
        'chat_message_parts',
        encoded,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Map<String, Object?> _partToRow(ChatMessagePart part) {
    final (type, text, payload) = switch (part) {
      ChatTextPart() => ('text', part.text, <String, Object?>{}),
      ChatReasoningPart() => (
        'reasoning',
        part.text,
        <String, Object?>{'reasoningType': part.reasoningType},
      ),
      ChatQuotePart() => (
        'quote',
        part.quote,
        <String, Object?>{
          'bookId': part.bookId,
          'bookTitle': part.bookTitle,
          'href': part.href,
          'locator': part.locator,
          'chapterIndex': part.chapterIndex,
          'chapterTitle': part.chapterTitle,
        },
      ),
      ChatToolCallPart() => (
        'tool_call',
        null,
        <String, Object?>{
          'callId': part.callId,
          'toolName': part.toolName,
          'displayName': part.displayName,
          'argumentsJson': part.argumentsJson,
          'result': part.result,
          'error': part.error,
          'durationMillis': part.durationMillis,
        },
      ),
      ChatSkillCallPart() => (
        'skill_call',
        null,
        <String, Object?>{
          'callId': part.callId,
          'skillId': part.skillId,
          'skillName': part.skillName,
          'argumentsJson': part.argumentsJson,
          'result': part.result,
          'error': part.error,
          'durationMillis': part.durationMillis,
        },
      ),
      ChatCitationPart() => (
        'citation',
        part.citation.quote,
        <String, Object?>{
          'citationId': part.citation.id,
          'citationOrdinal': part.citation.ordinal,
          'bookId': part.citation.bookId,
          'href': part.citation.href,
          'locator': part.citation.locator,
          'chapterIndex': part.citation.chapterIndex,
          'chapterTitle': part.citation.chapterTitle,
        },
      ),
      ChatNoticePart() => (
        'notice',
        part.message,
        <String, Object?>{'level': part.level.name, 'code': part.code},
      ),
      ChatAbortedPart() => ('aborted', part.reason, <String, Object?>{}),
    };
    return {
      'id': part.id,
      'message_id': part.messageId,
      'ordinal': part.ordinal,
      'type': type,
      'status': part.status.name,
      'text_content': text,
      'payload_json': payload.isEmpty ? null : jsonEncode(payload),
      'provider_item_id': null,
      'created_at': part.createdAt.millisecondsSinceEpoch,
      'updated_at': part.updatedAt.millisecondsSinceEpoch,
    };
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
    List<ChatMessagePart> storedParts,
  ) {
    final messageId = row['id']! as String;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      row['created_at']! as int,
    );
    final content = row['content']! as String;
    final parts = [...storedParts];
    if (parts.isEmpty && content.isNotEmpty) {
      parts.add(
        ChatTextPart(
          id: 'legacy-text-$messageId',
          messageId: messageId,
          ordinal: 0,
          status: ChatPartStatus.completed,
          createdAt: createdAt,
          updatedAt: createdAt,
          text: content,
        ),
      );
    }
    final partCitationIds = parts
        .whereType<ChatCitationPart>()
        .map((part) => part.citation.id)
        .toSet();
    var nextOrdinal = parts.isEmpty
        ? 0
        : parts.map((part) => part.ordinal).reduce((a, b) => a > b ? a : b) + 1;
    for (final citation in citations) {
      if (partCitationIds.contains(citation.id)) continue;
      parts.add(
        ChatCitationPart(
          id: 'citation-part-${citation.id}',
          messageId: messageId,
          ordinal: nextOrdinal++,
          status: ChatPartStatus.completed,
          createdAt: createdAt,
          updatedAt: createdAt,
          citation: citation,
        ),
      );
    }
    final hasUsage =
        row['input_tokens'] != null || row['output_tokens'] != null;
    return ChatMessage(
      id: messageId,
      threadId: row['thread_id']! as String,
      role: ChatRole.values.byName(row['role']! as String),
      content: content,
      status: ChatMessageStatus.values.byName(row['status']! as String),
      modelId: row['model_id'] as String?,
      errorCode: row['error_code'] as String?,
      createdAt: createdAt,
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['completed_at']! as int),
      citations: citations,
      parts: parts,
      usage: hasUsage
          ? AiUsage(
              inputTokens: row['input_tokens'] as int? ?? 0,
              outputTokens: row['output_tokens'] as int? ?? 0,
              reasoningTokens: row['reasoning_tokens'] as int? ?? 0,
              cachedTokens: row['cached_tokens'] as int? ?? 0,
            )
          : null,
      stopReason: row['stop_reason'] as String?,
    );
  }

  ChatMessagePart _partFromRow(Map<String, Object?> row) {
    final id = row['id']! as String;
    final messageId = row['message_id']! as String;
    final ordinal = row['ordinal']! as int;
    final status = ChatPartStatus.values.byName(row['status']! as String);
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      row['created_at']! as int,
    );
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(
      row['updated_at']! as int,
    );
    final text = row['text_content'] as String? ?? '';
    Map<String, Object?> payload = const {};
    final encodedPayload = row['payload_json'] as String?;
    if (encodedPayload != null && encodedPayload.isNotEmpty) {
      try {
        payload = jsonDecode(encodedPayload) as Map<String, Object?>;
      } on FormatException {
        payload = const {};
      }
    }
    return switch (row['type']! as String) {
      'text' => ChatTextPart(
        id: id,
        messageId: messageId,
        ordinal: ordinal,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        text: text,
      ),
      'reasoning' => ChatReasoningPart(
        id: id,
        messageId: messageId,
        ordinal: ordinal,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        text: text,
        reasoningType: payload['reasoningType'] as String? ?? 'thinking',
      ),
      'quote' => ChatQuotePart(
        id: id,
        messageId: messageId,
        ordinal: ordinal,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        bookId: payload['bookId'] as String? ?? '',
        bookTitle: payload['bookTitle'] as String? ?? '',
        href: payload['href'] as String? ?? '',
        locator: payload['locator'] as String? ?? '',
        chapterIndex: payload['chapterIndex'] as int?,
        chapterTitle: payload['chapterTitle'] as String?,
        quote: text,
      ),
      'tool_call' => ChatToolCallPart(
        id: id,
        messageId: messageId,
        ordinal: ordinal,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        callId: payload['callId'] as String? ?? id,
        toolName: payload['toolName'] as String? ?? 'unknown_tool',
        displayName: payload['displayName'] as String? ?? '工具调用',
        argumentsJson: payload['argumentsJson'] as String? ?? '',
        result: payload['result'] as String?,
        error: payload['error'] as String?,
        durationMillis: payload['durationMillis'] as int?,
      ),
      'skill_call' => ChatSkillCallPart(
        id: id,
        messageId: messageId,
        ordinal: ordinal,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        callId: payload['callId'] as String? ?? id,
        skillId: payload['skillId'] as String? ?? 'unknown_skill',
        skillName: payload['skillName'] as String? ?? '技能',
        argumentsJson: payload['argumentsJson'] as String? ?? '',
        result: payload['result'] as String?,
        error: payload['error'] as String?,
        durationMillis: payload['durationMillis'] as int?,
      ),
      'citation' => ChatCitationPart(
        id: id,
        messageId: messageId,
        ordinal: ordinal,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        citation: ChatCitation(
          id: payload['citationId'] as String? ?? 'citation-$id',
          messageId: messageId,
          ordinal: payload['citationOrdinal'] as int? ?? 1,
          bookId: payload['bookId'] as String? ?? '',
          href: payload['href'] as String? ?? '',
          locator: payload['locator'] as String? ?? '',
          chapterIndex: payload['chapterIndex'] as int?,
          chapterTitle: payload['chapterTitle'] as String?,
          quote: text,
        ),
      ),
      'aborted' => ChatAbortedPart(
        id: id,
        messageId: messageId,
        ordinal: ordinal,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        reason: text,
      ),
      _ => ChatNoticePart(
        id: id,
        messageId: messageId,
        ordinal: ordinal,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        message: text.isEmpty ? '无法读取此消息片段。' : text,
        level: ChatNoticeLevel.values.byName(
          payload['level'] as String? ?? ChatNoticeLevel.warning.name,
        ),
        code: payload['code'] as String?,
      ),
    };
  }

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
