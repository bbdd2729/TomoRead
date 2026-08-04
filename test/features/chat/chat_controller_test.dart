import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/ai_provider_repository.dart';
import 'package:tomoread/data/repositories/annotation_repository.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/data/repositories/chat_repository.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/repositories/content_embedding_repository.dart';
import 'package:tomoread/data/repositories/embedding_provider_repository.dart';
import 'package:tomoread/data/repositories/skill_repository.dart';
import 'package:tomoread/data/services/ai_gateway.dart';
import 'package:tomoread/data/services/ai_provider_probe_service.dart';
import 'package:tomoread/data/services/ai_secret_store.dart';
import 'package:tomoread/data/services/ai_tool_registry.dart';
import 'package:tomoread/data/services/embedding_provider_service.dart';
import 'package:tomoread/data/services/hybrid_search_service.dart';
import 'package:tomoread/domain/models/ai_agent_models.dart';
import 'package:tomoread/domain/models/ai_provider_preset.dart';
import 'package:tomoread/domain/models/chat_models.dart';
import 'package:tomoread/features/chat/ai_agent_runner.dart';
import 'package:tomoread/features/chat/chat_controller.dart';

void main() {
  late AppDatabase database;
  late ChatRepository chatRepository;
  late AiProviderRepository providerRepository;
  late FakeAiAgentRunner runner;
  late FakeAiSecretStore secrets;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.inMemory();
    chatRepository = ChatRepository(database);
    providerRepository = AiProviderRepository(database);
    runner = FakeAiAgentRunner();
    secrets = FakeAiSecretStore();
    container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(chatRepository),
        aiProviderRepositoryProvider.overrideWithValue(providerRepository),
        aiAgentRunnerProvider.overrideWithValue(runner),
        aiSecretStoreProvider.overrideWithValue(secrets),
        aiProviderProbeServiceProvider.overrideWithValue(
          FakeProbeService(),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
  });

  AiProviderProfile sampleProfile() => AiProviderProfile(
    id: 'provider-a',
    name: 'Test Provider',
    baseUrl: 'https://example.com/v1',
    modelId: 'model-a',
    secretKeyId: 'secret-a',
    temperature: 0.3,
    maxOutputTokens: 2048,
    isActive: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test('build loads threads and the active profile', () async {
    await providerRepository.save(
      name: 'Test Provider',
      baseUrl: 'https://example.com/v1',
      modelId: 'model-a',
      secretKeyId: 'secret-a',
    );
    final thread = await chatRepository.createThread(scope: ChatScope.general);

    final state = await container.read(chatControllerProvider.future);
    expect(state.threads.single.id, thread.id);
    expect(state.profile, isNotNull);
  });

  test('selectThread loads messages and tracks loading state', () async {
    final thread = await chatRepository.createThread(scope: ChatScope.general);
    await container.read(chatControllerProvider.future);
    final notifier = container.read(chatControllerProvider.notifier);

    await notifier.selectThread(thread.id);

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.activeThreadId, thread.id);
    expect(state.isLoadingMessages, isFalse);
    expect(state.messages, isEmpty);
  });

  test('createThread prepends a general thread and activates it', () async {
    final notifier = container.read(chatControllerProvider.notifier);
    await container.read(chatControllerProvider.future);

    final thread = await notifier.createThread(title: 'New');

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.threads.first.id, thread.id);
    expect(state.activeThreadId, thread.id);
    expect(thread.scope, ChatScope.general);
  });

  test('deleteThread removes the active thread and selects the next', () async {
    final first = await chatRepository.createThread(scope: ChatScope.general);
    final second = await chatRepository.createThread(scope: ChatScope.general);
    await container.read(chatControllerProvider.future);
    final notifier = container.read(chatControllerProvider.notifier);
    await notifier.selectThread(first.id);

    await notifier.deleteThread(first);

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.threads.any((thread) => thread.id == first.id), isFalse);
    expect(state.activeThreadId, second.id);
  });

  test('attach fills the draft attachment and prompt', () async {
    await container.read(chatControllerProvider.future);
    final notifier = container.read(chatControllerProvider.notifier);

    notifier.attach(
      const PendingChatDraft(
        prompt: '解释这句话',
        attachment: ChatContextAttachment(
          bookId: 'book-a',
          bookTitle: 'Book',
          href: 'chapter.xhtml',
          locator: 'ratio:0.5',
          quote: '原文',
        ),
      ),
    );

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.suggestedPrompt, '解释这句话');
    expect(state.attachment?.bookId, 'book-a');
  });

  test('send without a profile reports a configuration error', () async {
    await container.read(chatControllerProvider.future);
    final notifier = container.read(chatControllerProvider.notifier);

    await notifier.send('你好');

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.errorMessage, '请先配置模型服务。');
    expect(state.messages, isEmpty);
  });

  test('send with a missing key reports an API key error', () async {
    final profile = sampleProfile();
    await providerRepository.save(
      name: profile.name,
      baseUrl: profile.baseUrl,
      modelId: profile.modelId,
      secretKeyId: profile.secretKeyId,
      authType: AiProviderAuthType.bearer,
    );
    await container.read(chatControllerProvider.future);
    final notifier = container.read(chatControllerProvider.notifier);

    await notifier.send('你好');

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.errorMessage, contains('API Key'));
  });

  test('send streams a reply and marks the assistant message complete', () async {
    final profile = sampleProfile();
    await providerRepository.save(
      name: profile.name,
      baseUrl: profile.baseUrl,
      modelId: profile.modelId,
      secretKeyId: profile.secretKeyId,
      authType: AiProviderAuthType.bearer,
    );
    secrets.set('secret-a', 'key-123');
    runner.eventsForRun = [
      const AiRunStartedEvent(runId: 'run-a', modelId: 'model-a'),
      const AiTextDeltaEvent('你好，'),
      const AiTextDeltaEvent('我是助手。'),
      const AiRunCompletedEvent(stopReason: 'stop'),
    ];
    await container.read(chatControllerProvider.future);
    final notifier = container.read(chatControllerProvider.notifier);

    await notifier.send('你好');

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.messages, hasLength(2));
    final assistant = state.messages.last;
    expect(assistant.role, ChatRole.assistant);
    expect(assistant.status, ChatMessageStatus.complete);
    expect(assistant.content, '你好，我是助手。');
    expect(state.isStreaming, isFalse);
  });

  test('retry resends the previous user message after a failure', () async {
    final profile = sampleProfile();
    await providerRepository.save(
      name: profile.name,
      baseUrl: profile.baseUrl,
      modelId: profile.modelId,
      secretKeyId: profile.secretKeyId,
      authType: AiProviderAuthType.bearer,
    );
    secrets.set('secret-a', 'key-123');
    runner.eventsForRun = [
      const AiRunStartedEvent(runId: 'run-a', modelId: 'model-a'),
      const AiTextDeltaEvent('重试回答。'),
      const AiRunCompletedEvent(stopReason: 'stop'),
    ];
    await container.read(chatControllerProvider.future);
    final notifier = container.read(chatControllerProvider.notifier);

    await notifier.send('第一次提问');
    final first = container.read(chatControllerProvider).requireValue;
    final assistant = first.messages.last;

    await notifier.retry(assistant);

    final state = container.read(chatControllerProvider).requireValue;
    expect(state.messages, hasLength(4));
    expect(state.messages[2].role, ChatRole.user);
    expect(state.messages[2].content, '第一次提问');
  });
}

class FakeAiAgentRunner extends AiAgentRunner {
  FakeAiAgentRunner()
    : super(
        const _NeverGateway(),
        AiToolRegistry(
          BookRepository(_toolDatabase),
          AnnotationRepository(_toolDatabase),
          SkillRepository(_toolDatabase),
          ContentChunkRepository(_toolDatabase),
          HybridSearchService(
            chunks: ContentChunkRepository(_toolDatabase),
            embeddings: ContentEmbeddingRepository(_toolDatabase),
            profiles: EmbeddingProviderRepository(_toolDatabase),
            provider: const _NeverEmbeddingProvider(),
            secrets: AiSecretStore(),
          ),
        ),
      );

  List<AiStreamEvent> eventsForRun = const [];

  @override
  AiAgentRunHandle run({
    required String runId,
    required AiProviderProfile profile,
    required String apiKey,
    required List<ChatMessage> history,
    required String systemPrompt,
    required ChatThread thread,
    ChatContextAttachment? attachment,
    String? preferredSkillId,
  }) {
    return AiAgentRunHandle(
      events: Stream.fromIterable(eventsForRun),
      cancel: () {},
    );
  }
}

/// Shared in-memory database used only to satisfy the never-invoked tool
/// registry; the runner's [run] is always overridden.
final _toolDatabase = AppDatabase.inMemory();

class FakeAiSecretStore extends AiSecretStore {
  final _values = <String, String>{};

  void set(String id, String value) => _values[id] = value;

  @override
  Future<String?> read(String id) async => _values[id];

  @override
  Future<void> write(String id, String value) async => _values[id] = value;

  @override
  Future<void> delete(String id) async => _values.remove(id);
}

class FakeProbeService extends AiProviderProbeService {
  const FakeProbeService();

  @override
  Future<AiProviderProbeResult> probe(
    AiProviderProfile profile, {
    required String apiKey,
  }) async => const AiProviderProbeResult(
    providerId: 'provider-a',
    statusCode: 200,
    latencyMillis: 10,
    models: ['model-a'],
  );
}

class _NeverGateway implements AiGateway {
  const _NeverGateway();

  @override
  AiCapabilities capabilities(AiProviderProfile profile) =>
      throw UnimplementedError();

  @override
  Future<AiStreamHandle> streamReply({
    required AiProviderProfile profile,
    required String apiKey,
    required List<AiProviderMessage> messages,
    List<AiToolDeclaration> tools = const [],
  }) => throw UnimplementedError();
}

class _NeverEmbeddingProvider extends OpenAiCompatibleEmbeddingService {
  const _NeverEmbeddingProvider();
}
