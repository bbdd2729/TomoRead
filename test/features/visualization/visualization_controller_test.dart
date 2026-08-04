import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/ai_provider_repository.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/repositories/visual_artifact_repository.dart';
import 'package:tomoread/data/services/ai_gateway.dart';
import 'package:tomoread/data/services/ai_secret_store.dart';
import 'package:tomoread/data/services/mind_map_generation_service.dart';
import 'package:tomoread/data/services/visual_artifact_export_service.dart';
import 'package:tomoread/data/services/word_frequency_service.dart';
import 'package:tomoread/domain/models/ai_agent_models.dart';
import 'package:tomoread/domain/models/chat_models.dart';
import 'package:tomoread/domain/models/visual_artifact.dart';
import 'package:tomoread/features/visualization/visualization_controller.dart';

void main() {
  late AppDatabase database;
  late VisualArtifactRepository artifacts;
  late AiProviderRepository providers;
  late _FakeWordFrequency wordFrequency;
  late _FakeMindMaps mindMaps;

  setUp(() async {
    database = AppDatabase.inMemory();
    artifacts = VisualArtifactRepository(database);
    providers = AiProviderRepository(database);
    wordFrequency = _FakeWordFrequency(database);
    mindMaps = _FakeMindMaps(database);
    final raw = await database.database;
    await raw.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'progress': 0,
      'chapter_index': 0,
      'chapter_count': 0,
      'read_direction': 'ltr',
      'created_at': 1,
      'updated_at': 1,
    });
    addTearDown(database.close);
  });

  VisualizationController build({required void Function() onChanged}) =>
      VisualizationController(
        wordFrequency: wordFrequency,
        mindMaps: mindMaps,
        artifacts: artifacts,
        providers: providers,
        secrets: _FakeSecrets(),
        exporter: const VisualArtifactExportService(),
        onChanged: onChanged,
      );

  test('generateMindMap requires an active provider profile', () async {
    final controller = build(onChanged: () {});

    await expectLater(
      controller.generateMindMap(
        bookId: 'book-a',
        bookTitle: 'Book',
        scope: VisualArtifactScope.currentChapter,
        currentChapterIndex: 0,
      ),
      throwsA(isA<VisualizationException>()),
    );
  });

  test('generateWordCloud delegates to the word frequency service', () async {
    var notified = 0;
    final controller = build(onChanged: () => notified++);
    final generation = await controller.generateWordCloud(
      bookId: 'book-a',
      bookTitle: 'Book',
      scope: VisualArtifactScope.wholeBook,
      currentChapterIndex: 0,
    );

    expect(notified, 1);
    expect(generation.payload.terms, hasLength(2));
  });

  test('reseedWordCloud rejects non word-cloud artifacts', () async {
    final controller = build(onChanged: () {});
    final mindMap = VisualArtifact(
      id: 'a',
      bookId: 'book-a',
      kind: VisualArtifactKind.mindMap,
      scope: VisualArtifactScope.wholeBook,
      title: 't',
      contentHash: 'h',
      payloadJson: '{}',
      createdAt: DateTime(2026),
    );

    await expectLater(
      controller.reseedWordCloud(mindMap),
      throwsA(isA<VisualizationException>()),
    );
  });

  test('reseedWordCloud saves a new seed and notifies change', () async {
    var notified = 0;
    final controller = build(onChanged: () => notified++);
    final wordCloud = VisualArtifact(
      id: 'wc',
      bookId: 'book-a',
      kind: VisualArtifactKind.wordCloud,
      scope: VisualArtifactScope.wholeBook,
      title: '词云',
      contentHash: 'h',
      payloadJson: jsonEncode(
        WordCloudPayload(
          terms: const [WordCloudTerm(term: '阅读', frequency: 5)],
          scope: VisualArtifactScope.wholeBook,
          layoutSeed: 1,
          contentHash: 'h',
          tokenizerVersion: 1,
          stopwordVersion: 1,
          generatedAt: DateTime(2026),
        ).toJson(),
      ),
      createdAt: DateTime(2026),
    );

    final saved = await controller.reseedWordCloud(wordCloud);

    expect(notified, 1);
    expect(saved.id, isNot('wc'));
    final savedPayload = WordCloudPayload.fromJson(
      jsonDecode(saved.payloadJson) as Map<String, Object?>,
    );
    expect(savedPayload.layoutSeed, isNot(1));
  });

  test('delete removes the artifact and notifies change', () async {
    var notified = 0;
    final controller = build(onChanged: () => notified++);
    final saved = await artifacts.save(
      bookId: 'book-a',
      kind: VisualArtifactKind.wordCloud,
      scope: VisualArtifactScope.wholeBook,
      title: 't',
      contentHash: 'h',
      payload: const {'terms': []},
    );

    await controller.delete(saved);

    expect(notified, 1);
    expect(await artifacts.listForBook('book-a'), isEmpty);
  });
}

class _FakeWordFrequency extends WordFrequencyService {
  _FakeWordFrequency(AppDatabase database)
    : super(
        chunks: ContentChunkRepository(database),
        artifacts: VisualArtifactRepository(database),
      );

  @override
  Future<WordCloudGeneration> generate({
    required String bookId,
    required String bookTitle,
    required VisualArtifactScope scope,
    required int currentChapterIndex,
    int minimumLength = 2,
    int maximumTerms = 100,
    int layoutSeed = 1,
  }) async {
    final payload = WordCloudPayload(
      terms: const [
        WordCloudTerm(term: '阅读', frequency: 4),
        WordCloudTerm(term: '思考', frequency: 3),
      ],
      scope: scope,
      layoutSeed: layoutSeed,
      contentHash: 'h',
      tokenizerVersion: 1,
      stopwordVersion: 1,
      generatedAt: DateTime(2026),
    );
    final artifact = VisualArtifact(
      id: 'wc-$bookId',
      bookId: bookId,
      kind: VisualArtifactKind.wordCloud,
      scope: scope,
      title: bookTitle,
      contentHash: 'h',
      payloadJson: jsonEncode(payload.toJson()),
      createdAt: DateTime(2026),
    );
    return WordCloudGeneration(artifact: artifact, payload: payload);
  }
}

class _FakeMindMaps extends MindMapGenerationService {
  _FakeMindMaps(AppDatabase database)
    : super(
        chunks: ContentChunkRepository(database),
        artifacts: VisualArtifactRepository(database),
        gateway: _NeverGateway(),
      );

  @override
  Future<MindMapGeneration> generate({
    required String bookId,
    required String bookTitle,
    required VisualArtifactScope scope,
    required int currentChapterIndex,
    required AiProviderProfile profile,
    required String apiKey,
  }) async => throw UnimplementedError();
}

class _FakeSecrets extends AiSecretStore {
  @override
  Future<String?> read(String id) async => null;
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
