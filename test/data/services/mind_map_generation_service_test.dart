import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/content_chunk_repository.dart';
import 'package:tomoread/data/repositories/visual_artifact_repository.dart';
import 'package:tomoread/data/services/ai_gateway.dart';
import 'package:tomoread/data/services/mind_map_generation_service.dart';
import 'package:tomoread/domain/models/ai_agent_models.dart';
import 'package:tomoread/domain/models/chat_models.dart';
import 'package:tomoread/domain/models/content_chunk.dart';
import 'package:tomoread/domain/models/visual_artifact.dart';

void main() {
  late AppDatabase database;
  late MindMapGenerationService service;
  const source = ContentChunk(
    id: 'chunk-a',
    bookId: 'book-a',
    chapterId: 'chapter-a',
    chapterIndex: 2,
    chapterTitle: '第二章',
    href: 'chapter-2.xhtml',
    locatorStart: 'ratio:0.250000',
    locatorEnd: 'ratio:0.500000',
    rawStart: 0,
    rawEnd: 8,
    ordinal: 0,
    text: '可信正文片段',
    textHash: 'chunk-hash',
    contentHash: 'book-hash',
    parserVersion: 1,
    indexVersion: 1,
  );

  setUp(() {
    database = AppDatabase.inMemory();
    service = MindMapGenerationService(
      chunks: ContentChunkRepository(database),
      artifacts: VisualArtifactRepository(database),
      gateway: const _UnusedGateway(),
    );
  });

  tearDown(() => database.close());

  MindMapPayload validate(Object value) => service.validateResponse(
    rawResponse: value is String ? value : jsonEncode(value),
    sourceById: const {'s1': source},
    bookId: 'book-a',
    scope: VisualArtifactScope.currentChapter,
    contentHash: 'book-hash',
  );

  test('validates JSON and maps source ids to trusted locators', () {
    final payload = validate({
      'title': '主题',
      'nodes': [
        {
          'id': 'root',
          'label': '核心概念',
          'citations': ['s1'],
          'children': <Object>[],
        },
      ],
    });

    final citation = payload.nodes.single.citations.single;
    expect(citation.bookId, 'book-a');
    expect(citation.href, 'chapter-2.xhtml');
    expect(citation.locator, 'ratio:0.250000');
    expect(citation.quote, '可信正文片段');
  });

  test('rejects duplicate ids and unauthorized citations', () {
    expect(
      () => validate({
        'title': '重复节点',
        'nodes': [
          {'id': 'same', 'label': '一', 'children': <Object>[]},
          {'id': 'same', 'label': '二', 'children': <Object>[]},
        ],
      }),
      throwsA(isA<MindMapValidationException>()),
    );
    expect(
      () => validate({
        'title': '非法引用',
        'nodes': [
          {
            'id': 'root',
            'label': '节点',
            'citations': ['invented'],
            'children': <Object>[],
          },
        ],
      }),
      throwsA(isA<MindMapValidationException>()),
    );
  });

  test('enforces depth and node-count limits', () {
    Map<String, Object?> nested(int depth) => {
      'id': 'node-$depth',
      'label': '节点 $depth',
      'children': depth == 6 ? <Object>[] : [nested(depth + 1)],
    };
    expect(
      () => validate({
        'title': '过深',
        'nodes': [nested(1)],
      }),
      throwsA(isA<MindMapValidationException>()),
    );
    expect(
      () => validate({
        'title': '过多',
        'nodes': [
          for (var index = 0; index < 81; index++)
            {'id': 'node-$index', 'label': '$index', 'children': <Object>[]},
        ],
      }),
      throwsA(isA<MindMapValidationException>()),
    );
  });

  test('requires a pure JSON response and preserves invalid raw text', () {
    const raw = '```json\n{"title":"主题","nodes":[]}\n```';
    expect(
      () => validate(raw),
      throwsA(
        isA<MindMapValidationException>().having(
          (error) => error.rawResponse,
          'rawResponse',
          raw,
        ),
      ),
    );
  });
}

class _UnusedGateway implements AiGateway {
  const _UnusedGateway();

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
