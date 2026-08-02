import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../../domain/models/ai_agent_models.dart';
import '../../domain/models/content_chunk.dart';
import '../../domain/models/visual_artifact.dart';
import '../repositories/content_chunk_repository.dart';
import '../repositories/visual_artifact_repository.dart';

class WordCloudGeneration {
  const WordCloudGeneration({required this.artifact, required this.payload});

  final VisualArtifact artifact;
  final WordCloudPayload payload;

  AiArtifactEvent toArtifactEvent() => AiArtifactEvent(
    artifactType: artifact.kind.name,
    title: artifact.title,
    payloadJson: artifact.payloadJson,
    artifactId: artifact.id,
    bookId: artifact.bookId,
  );
}

class WordFrequencyService {
  WordFrequencyService({required this.chunks, required this.artifacts});

  static const tokenizerVersion = 1;
  static const stopwordVersion = 1;

  final ContentChunkRepository chunks;
  final VisualArtifactRepository artifacts;
  WordFrequencyJob? _activeJob;
  var _cancelRequested = false;

  bool get isGenerating => _activeJob != null;

  Future<void> cancel() async {
    _cancelRequested = true;
    final job = _activeJob;
    if (job != null) await job.cancel();
  }

  Future<WordCloudGeneration> generate({
    required String bookId,
    required String bookTitle,
    required VisualArtifactScope scope,
    required int currentChapterIndex,
    int minimumLength = 2,
    int maximumTerms = 100,
    int layoutSeed = 1,
  }) async {
    _cancelRequested = false;
    final selected = await _chunksForScope(
      bookId,
      scope,
      currentChapterIndex,
    );
    if (selected.isEmpty) {
      throw const WordFrequencyException('当前范围没有可用于词云的正文索引。');
    }
    if (_cancelRequested) {
      throw const WordFrequencyException('词云计算已取消。');
    }
    final contentHash = sha256
        .convert(utf8.encode(selected.map((chunk) => chunk.textHash).join(':')))
        .toString();
    final cacheKey = buildWordCloudCacheKey(
      bookId: bookId,
      contentHash: contentHash,
      scope: scope,
      currentChapterIndex: currentChapterIndex,
      minimumLength: minimumLength,
      maximumTerms: maximumTerms,
    );
    var payload = await artifacts.loadWordCloudCache(cacheKey);
    if (payload == null) {
      if (_activeJob != null) {
        throw const WordFrequencyException('已有词云正在计算。');
      }
      final job = WordFrequencyJob.start(
        texts: selected.map((chunk) => chunk.text).toList(),
        minimumLength: minimumLength,
        maximumTerms: maximumTerms,
      );
      _activeJob = job;
      late final List<WordCloudTerm> terms;
      try {
        terms = await job.result;
      } finally {
        if (identical(_activeJob, job)) _activeJob = null;
      }
      if (terms.isEmpty) {
        throw const WordFrequencyException('当前范围没有可显示的有效词项。');
      }
      payload = WordCloudPayload(
        terms: terms,
        scope: scope,
        layoutSeed: layoutSeed,
        contentHash: contentHash,
        tokenizerVersion: tokenizerVersion,
        stopwordVersion: stopwordVersion,
        generatedAt: DateTime.now(),
      );
      await artifacts.saveWordCloudCache(
        cacheKey: cacheKey,
        bookId: bookId,
        payload: payload,
      );
    } else if (payload.layoutSeed != layoutSeed) {
      payload = payload.copyWith(layoutSeed: layoutSeed);
    }
    if (_cancelRequested) {
      throw const WordFrequencyException('词云计算已取消。');
    }
    final artifact = await artifacts.save(
      bookId: bookId,
      kind: VisualArtifactKind.wordCloud,
      scope: scope,
      title: '$bookTitle · 词云',
      contentHash: contentHash,
      payload: payload.toJson(),
    );
    return WordCloudGeneration(artifact: artifact, payload: payload);
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
}

String buildWordCloudCacheKey({
  required String bookId,
  required String contentHash,
  required VisualArtifactScope scope,
  required int currentChapterIndex,
  required int minimumLength,
  required int maximumTerms,
}) => sha256
    .convert(
      utf8.encode(
        '$bookId:$contentHash:${scope.name}:'
        '${switch (scope) {
          VisualArtifactScope.currentChapter => 'chapter-$currentChapterIndex',
          VisualArtifactScope.readChapters => 'read-through-$currentChapterIndex',
          VisualArtifactScope.wholeBook => 'whole-book',
        }}:'
        '${WordFrequencyService.tokenizerVersion}:'
        '${WordFrequencyService.stopwordVersion}:$minimumLength:$maximumTerms',
      ),
    )
    .toString();

class WordFrequencyJob {
  WordFrequencyJob._(this._completer, this._isolate, this._port);

  final Completer<List<WordCloudTerm>> _completer;
  final Future<Isolate> _isolate;
  final ReceivePort _port;
  var _cancelled = false;

  Future<List<WordCloudTerm>> get result => _completer.future;

  static WordFrequencyJob start({
    required List<String> texts,
    int minimumLength = 2,
    int maximumTerms = 100,
  }) {
    final port = ReceivePort();
    final completer = Completer<List<WordCloudTerm>>();
    late final WordFrequencyJob job;
    port.listen((message) {
      if (job._cancelled || completer.isCompleted) return;
      if (message is List) {
        completer.complete(
          message
              .whereType<Map>()
              .map(
                (value) => WordCloudTerm(
                  term: value['term']! as String,
                  frequency: value['frequency']! as int,
                ),
              )
              .toList(),
        );
      } else if (message is Map && message['error'] is String) {
        completer.completeError(
          WordFrequencyException(message['error']! as String),
        );
      }
      port.close();
    });
    final isolate = Isolate.spawn<
      (SendPort, List<String>, int, int)
    >(
      _countWords,
      (
        port.sendPort,
        texts,
        minimumLength.clamp(1, 12).toInt(),
        maximumTerms.clamp(10, 500).toInt(),
      ),
    );
    job = WordFrequencyJob._(completer, isolate, port);
    unawaited(
      isolate.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          port.close();
        },
      ),
    );
    return job;
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    (await _isolate).kill(priority: Isolate.immediate);
    _port.close();
    if (!_completer.isCompleted) {
      _completer.completeError(const WordFrequencyException('词云计算已取消。'));
    }
  }
}

class WordFrequencyException implements Exception {
  const WordFrequencyException(this.message);

  final String message;

  @override
  String toString() => message;
}

void _countWords((SendPort, List<String>, int, int) request) {
  try {
    request.$1.send(
      countWordFrequencies(
        request.$2,
        minimumLength: request.$3,
        maximumTerms: request.$4,
      )
          .map(
            (term) => <String, Object>{
              'term': term.term,
              'frequency': term.frequency,
            },
          )
          .toList(),
    );
  } on Object catch (error) {
    request.$1.send({'error': error.toString()});
  }
}

List<WordCloudTerm> countWordFrequencies(
  List<String> texts, {
  int minimumLength = 2,
  int maximumTerms = 100,
}) {
  final safeMinimum = minimumLength.clamp(1, 12).toInt();
  final safeMaximum = maximumTerms.clamp(10, 500).toInt();
  final counts = <String, int>{};
  for (final text in texts) {
    for (final match in RegExp(r"[A-Za-z][A-Za-z0-9'-]*").allMatches(text)) {
      _addToken(counts, match.group(0)!.toLowerCase(), safeMinimum);
    }
    for (final match in RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF]+').allMatches(text)) {
      final sequence = match.group(0)!;
      if (sequence.length == 1) {
        _addToken(counts, sequence, safeMinimum);
        continue;
      }
      for (var index = 0; index + 1 < sequence.length; index++) {
        _addToken(counts, sequence.substring(index, index + 2), safeMinimum);
      }
    }
  }
  final terms = counts.entries
      .map((entry) => WordCloudTerm(term: entry.key, frequency: entry.value))
      .toList()
    ..sort((left, right) {
      final frequency = right.frequency.compareTo(left.frequency);
      return frequency != 0 ? frequency : left.term.compareTo(right.term);
    });
  return terms.take(safeMaximum).toList();
}

void _addToken(Map<String, int> counts, String token, int minimumLength) {
  if (token.length < minimumLength || _stopwords.contains(token)) return;
  counts[token] = (counts[token] ?? 0) + 1;
}

const _stopwords = <String>{
  'the', 'and', 'that', 'with', 'from', 'this', 'have', 'were', 'been',
  'are', 'for', 'not', 'but', 'you', 'your', 'their', 'they', 'them',
  '一个', '这个', '那个', '我们', '他们', '以及', '因为', '所以', '但是',
  '如果', '就是', '可以', '进行', '已经', '没有', '自己', '什么', '这样',
};
