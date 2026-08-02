import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models/ai_agent_models.dart';
import '../../domain/models/chat_models.dart';
import '../../domain/models/content_chunk.dart';
import '../../domain/models/visual_artifact.dart';
import '../repositories/content_chunk_repository.dart';
import '../repositories/visual_artifact_repository.dart';
import 'ai_gateway.dart';

class MindMapGeneration {
  const MindMapGeneration({required this.artifact, required this.payload});

  final VisualArtifact artifact;
  final MindMapPayload payload;

  AiArtifactEvent toArtifactEvent() => AiArtifactEvent(
    artifactType: artifact.kind.name,
    title: artifact.title,
    payloadJson: artifact.payloadJson,
    artifactId: artifact.id,
    bookId: artifact.bookId,
  );
}

class MindMapValidationException implements Exception {
  const MindMapValidationException(this.message, this.rawResponse);

  final String message;
  final String rawResponse;

  @override
  String toString() => message;
}

class MindMapGenerationCancelledException implements Exception {
  const MindMapGenerationCancelledException();

  @override
  String toString() => '思维导图生成已取消。';
}

class MindMapGenerationService {
  MindMapGenerationService({
    required this.chunks,
    required this.artifacts,
    required this.gateway,
  });

  final ContentChunkRepository chunks;
  final VisualArtifactRepository artifacts;
  final AiGateway gateway;
  AiStreamHandle? _activeHandle;
  var _cancelRequested = false;
  var _isStarting = false;

  bool get isGenerating => _isStarting || _activeHandle != null;

  void cancel() {
    if (!isGenerating) return;
    _cancelRequested = true;
    _activeHandle?.cancel();
  }

  Future<MindMapGeneration> generate({
    required String bookId,
    required String bookTitle,
    required VisualArtifactScope scope,
    required int currentChapterIndex,
    required AiProviderProfile profile,
    required String apiKey,
  }) async {
    if (isGenerating) {
      throw const MindMapValidationException('已有思维导图正在生成。', '');
    }
    _cancelRequested = false;
    _isStarting = true;
    late final List<ContentChunk> selected;
    final sources = <String, ContentChunk>{};
    final context = StringBuffer();
    late final String contentHash;
    late final AiStreamHandle handle;
    try {
      selected = await _chunksForScope(
        bookId,
        scope,
        currentChapterIndex,
      );
      if (selected.isEmpty) {
        throw const MindMapValidationException('当前范围没有可用正文索引。', '');
      }
      if (_cancelRequested) {
        throw const MindMapGenerationCancelledException();
      }
      var used = 0;
      for (final chunk in selected) {
        if (used >= 16000) break;
        final sourceId = 's${sources.length + 1}';
        final remaining = 16000 - used;
        final text = chunk.text.length <= remaining
            ? chunk.text
            : chunk.text.substring(0, remaining);
        sources[sourceId] = chunk;
        context.writeln(
          '[$sourceId | ${chunk.chapterTitle} | ${chunk.locatorStart}]\n$text',
        );
        used += text.length;
      }
      contentHash = sha256
          .convert(
            utf8.encode(selected.map((chunk) => chunk.textHash).join(':')),
          )
          .toString();
      handle = await gateway.streamReply(
        profile: profile,
        apiKey: apiKey,
        messages: [
          const AiProviderMessage(
            role: 'system',
            content:
                '你是阅读结构化助手。只返回一个 JSON 对象，不返回 Markdown、HTML、'
                'JavaScript 或解释文字。不得编造 source id。',
          ),
          AiProviderMessage(
            role: 'user',
            content:
                '根据以下原文生成思维导图。JSON 结构必须是：'
                '{"title":"...","nodes":[{"id":"...","label":"...",'
                '"children":[],"citations":["s1"]}]}。'
                '最大深度 5，最多 80 个节点，每个 label 最多 80 字，'
                'citations 只能使用上下文中的 source id。\n\n$context',
          ),
        ],
      );
    } on Object {
      _isStarting = false;
      rethrow;
    }
    _isStarting = false;
    if (_cancelRequested) {
      handle.cancel();
      throw const MindMapGenerationCancelledException();
    }
    _activeHandle = handle;
    final response = StringBuffer();
    try {
      await for (final event in handle.events) {
        if (event is AiTextDeltaEvent) response.write(event.delta);
      }
    } on Object {
      if (_cancelRequested) {
        throw const MindMapGenerationCancelledException();
      }
      rethrow;
    } finally {
      _activeHandle = null;
    }
    if (_cancelRequested) {
      throw const MindMapGenerationCancelledException();
    }
    final raw = response.toString().trim();
    final payload = validateResponse(
      rawResponse: raw,
      sourceById: sources,
      bookId: bookId,
      scope: scope,
      contentHash: contentHash,
    );
    final artifact = await artifacts.save(
      bookId: bookId,
      kind: VisualArtifactKind.mindMap,
      scope: scope,
      title: payload.title.isEmpty ? '$bookTitle · 思维导图' : payload.title,
      contentHash: contentHash,
      payload: payload.toJson(),
    );
    return MindMapGeneration(artifact: artifact, payload: payload);
  }

  Future<List<ContentChunk>> _chunksForScope(
    String bookId,
    VisualArtifactScope scope,
    int currentChapterIndex,
  ) => switch (scope) {
    VisualArtifactScope.currentChapter => chunks.listChapter(
      bookId,
      currentChapterIndex,
    ),
    VisualArtifactScope.readChapters => chunks.listForBook(
      bookId,
      maxChapterIndex: currentChapterIndex,
    ),
    VisualArtifactScope.wholeBook => chunks.listForBook(bookId),
  };

  MindMapPayload validateResponse({
    required String rawResponse,
    required Map<String, ContentChunk> sourceById,
    required String bookId,
    required VisualArtifactScope scope,
    required String contentHash,
  }) {
    Map<String, Object?> root;
    try {
      root = jsonDecode(rawResponse) as Map<String, Object?>;
    } on Object {
      throw MindMapValidationException(
        '模型没有返回纯 JSON 思维导图。原始响应已按纯文本保留。',
        _safeRaw(rawResponse),
      );
    }
    final title = root['title'];
    final rawNodes = root['nodes'];
    if (title is! String || title.trim().isEmpty || title.length > 120) {
      throw MindMapValidationException(
        '思维导图标题无效。',
        _safeRaw(rawResponse),
      );
    }
    if (rawNodes is! List<Object?> || rawNodes.isEmpty) {
      throw MindMapValidationException(
        '思维导图没有有效节点。',
        _safeRaw(rawResponse),
      );
    }
    var count = 0;
    final ids = <String>{};
    MindMapNode parseNode(Object? value, int depth) {
      if (depth > 5 || value is! Map<String, Object?>) {
        throw MindMapValidationException(
          '思维导图深度或节点结构无效。',
          _safeRaw(rawResponse),
        );
      }
      count++;
      if (count > 80) {
        throw MindMapValidationException(
          '思维导图节点超过 80 个。',
          _safeRaw(rawResponse),
        );
      }
      final id = value['id'];
      final label = value['label'];
      if (id is! String ||
          id.isEmpty ||
          id.length > 64 ||
          !ids.add(id) ||
          label is! String ||
          label.trim().isEmpty ||
          label.length > 80) {
        throw MindMapValidationException(
          '思维导图节点 ID 或标签无效。',
          _safeRaw(rawResponse),
        );
      }
      final childValues = value['children'] ?? const <Object?>[];
      final citationValues = value['citations'] ?? const <Object?>[];
      if (childValues is! List<Object?> || citationValues is! List<Object?>) {
        throw MindMapValidationException(
          '节点 children 或 citations 无效。',
          _safeRaw(rawResponse),
        );
      }
      if (citationValues.length > 8 ||
          citationValues.any(
            (source) =>
                source is! String || !sourceById.containsKey(source),
          )) {
        throw MindMapValidationException(
          '节点引用了未授权的原文来源。',
          _safeRaw(rawResponse),
        );
      }
      return MindMapNode(
        id: id,
        label: label.trim(),
        children: childValues
            .map((child) => parseNode(child, depth + 1))
            .toList(),
        citations: citationValues.cast<String>().map((sourceId) {
          final source = sourceById[sourceId]!;
          return ArtifactCitation(
            bookId: bookId,
            href: source.href,
            locator: source.locatorStart,
            chapterIndex: source.chapterIndex,
            chapterTitle: source.chapterTitle,
            quote: source.text.substring(
              0,
              source.text.length.clamp(0, 220).toInt(),
            ),
          );
        }).toList(),
      );
    }

    return MindMapPayload(
      title: title.trim(),
      nodes: rawNodes.map((node) => parseNode(node, 1)).toList(),
      scope: scope,
      contentHash: contentHash,
      generatedAt: DateTime.now(),
    );
  }

  String _safeRaw(String raw) => raw.substring(
    0,
    raw.length.clamp(0, 20000).toInt(),
  );
}
