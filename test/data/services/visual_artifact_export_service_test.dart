import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/visual_artifact_export_service.dart';
import 'package:tomoread/domain/models/visual_artifact.dart';

void main() {
  const service = VisualArtifactExportService();
  final generatedAt = DateTime.utc(2026, 8, 2);

  VisualArtifact mindMapArtifact() {
    final payload = MindMapPayload(
      title: '人物关系',
      nodes: const [
        MindMapNode(
          id: 'root',
          label: '主角',
          citations: [
            ArtifactCitation(
              bookId: 'book-a',
              href: 'chapter.xhtml',
              locator: 'ratio:0.2',
              chapterIndex: 1,
              chapterTitle: '第一章',
              quote: '主角出场',
            ),
          ],
        ),
      ],
      scope: VisualArtifactScope.currentChapter,
      contentHash: 'hash-a',
      generatedAt: generatedAt,
    );
    return VisualArtifact(
      id: 'artifact-a',
      bookId: 'book-a',
      kind: VisualArtifactKind.mindMap,
      scope: VisualArtifactScope.currentChapter,
      title: '人物关系',
      contentHash: 'hash-a',
      payloadJson: jsonEncode(payload.toJson()),
      createdAt: generatedAt,
    );
  }

  VisualArtifact wordCloudArtifact() {
    final payload = WordCloudPayload(
      terms: const [WordCloudTerm(term: '<阅读>', frequency: 4)],
      scope: VisualArtifactScope.wholeBook,
      layoutSeed: 42,
      contentHash: 'hash-a',
      tokenizerVersion: 1,
      stopwordVersion: 1,
      generatedAt: generatedAt,
    );
    return VisualArtifact(
      id: 'artifact-b',
      bookId: 'book-a',
      kind: VisualArtifactKind.wordCloud,
      scope: VisualArtifactScope.wholeBook,
      title: '整书词云',
      contentHash: 'hash-a',
      payloadJson: jsonEncode(payload.toJson()),
      createdAt: generatedAt,
    );
  }

  test('exports metadata-rich JSON and a cited Markdown outline', () {
    final artifact = mindMapArtifact();
    final json = utf8.decode(service.jsonBytes(artifact));
    final markdown = utf8.decode(service.markdownBytes(artifact));

    expect(json, contains('"kind": "mindMap"'));
    expect(json, contains('"contentHash": "hash-a"'));
    expect(markdown, startsWith('# 人物关系'));
    expect(markdown, contains('引用：第一章 `ratio:0.2`'));
  });

  test('escapes word-cloud text in SVG exports', () {
    final svg = utf8.decode(service.svgBytes(wordCloudArtifact()));

    expect(svg, startsWith('<svg'));
    expect(svg, contains('&lt;阅读&gt;'));
    expect(svg, isNot(contains('<阅读>')));
  });

  testWidgets('encodes native PNG output', (tester) async {
    final png = await tester.runAsync(
      () => service.pngBytes(wordCloudArtifact(), width: 320, height: 220),
    );

    expect(png, isNotNull);
    expect(png!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
