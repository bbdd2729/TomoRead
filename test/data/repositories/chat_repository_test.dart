import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/chat_repository.dart';
import 'package:tomoread/domain/models/chat_models.dart';

void main() {
  late AppDatabase database;
  late ChatRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = ChatRepository(database);
  });

  tearDown(() => database.close());

  test('persists threads, messages, citations, and cascade deletion', () async {
    final thread = await repository.createThread(
      scope: ChatScope.general,
      title: '阅读问题',
    );
    final now = DateTime.now();
    final message = ChatMessage(
      id: 'message-a',
      threadId: thread.id,
      role: ChatRole.assistant,
      content: '回答内容 [1]',
      status: ChatMessageStatus.complete,
      createdAt: now,
      completedAt: now,
      citations: const [
        ChatCitation(
          id: 'citation-a',
          messageId: 'message-a',
          ordinal: 1,
          bookId: 'missing-book',
          href: 'chapter.xhtml',
          locator: 'cfi:/6/2',
          quote: '引用内容',
        ),
      ],
    );

    await repository.insertMessage(message);
    await repository.renameThread(thread.id, '新的标题');

    final threads = await repository.listThreads();
    final messages = await repository.listMessages(thread.id);
    expect(threads.single.title, '新的标题');
    expect(messages.single.content, '回答内容 [1]');
    expect(messages.single.citations.single.quote, '引用内容');
    expect(
      messages.single.parts.whereType<ChatTextPart>().single.text,
      '回答内容 [1]',
    );
    expect(messages.single.parts.whereType<ChatCitationPart>(), hasLength(1));

    await repository.deleteThread(thread.id);
    expect(await repository.listMessages(thread.id), isEmpty);
  });
}
