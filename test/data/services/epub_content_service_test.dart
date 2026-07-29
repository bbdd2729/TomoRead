import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/epub_content_service.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';

void main() {
  const service = EpubContentService();
  const manifest = EpubManifest(
    opfPath: 'OPS/content.opf',
    version: '3.0',
    direction: ReadingDirection.ltr,
    spine: [
      EpubSpineItem(id: 'chapter-1', href: 'OPS/chapter-1.xhtml', linear: true),
    ],
    toc: [],
  );

  test('extracts readable XHTML chapter blocks from the EPUB archive', () {
    final chapter = service.loadChapterFromBytes(
      epubBytes: _buildEpub(),
      manifest: manifest,
      chapterIndex: 0,
    );

    expect(chapter.title, '第一章 真实内容');
    expect(chapter.href, 'OPS/chapter-1.xhtml');
    expect(chapter.blocks.map((block) => block.text), [
      '第一章 真实内容',
      '这是第一段文字。',
      '列表项目',
      '引用内容。',
    ]);
    expect(chapter.blocks.first.isHeading, isTrue);
  });

  test('rejects an unavailable spine resource', () {
    expect(
      () => service.loadChapterFromBytes(
        epubBytes: _buildEpub(),
        manifest: const EpubManifest(
          opfPath: 'OPS/content.opf',
          version: '3.0',
          direction: ReadingDirection.ltr,
          spine: [
            EpubSpineItem(
              id: 'missing',
              href: 'OPS/missing.xhtml',
              linear: true,
            ),
          ],
          toc: [],
        ),
        chapterIndex: 0,
      ),
      throwsA(isA<EpubContentException>()),
    );
  });

  test('finds EPUB text and returns a chapter-aware result', () {
    final results = service.searchFromBytes(
      epubBytes: _buildEpub(),
      manifest: manifest,
      query: '第一段',
    );

    expect(results, hasLength(1));
    expect(results.single.chapterIndex, 0);
    expect(results.single.chapterTitle, '第一章 真实内容');
    expect(results.single.excerpt, contains('这是第一段文字。'));
    expect(results.single.chapterRatio, greaterThan(0));
  });
}

List<int> _buildEpub() {
  final archive = Archive();
  final content = utf8.encode('''<html><body>
    <h1>第一章 真实内容</h1>
    <p>这是第一段文字。</p>
    <ul><li>列表项目</li></ul>
    <blockquote>引用内容。</blockquote>
  </body></html>''');
  archive.addFile(ArchiveFile('OPS/chapter-1.xhtml', content.length, content));
  return ZipEncoder().encode(archive);
}
