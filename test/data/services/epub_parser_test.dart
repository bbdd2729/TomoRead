import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/epub_parser.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';

void main() {
  const parser = EpubParser();

  test('parses EPUB metadata, navigation, spine, and cover', () {
    final result = parser.parseBytes(_buildEpub(), fallbackTitle: 'fallback');

    expect(result.title, 'Example title');
    expect(result.author, 'Example author');
    expect(result.description, 'Example description');
    expect(result.manifest.version, '3.0');
    expect(result.manifest.direction, ReadingDirection.rtl);
    expect(result.manifest.spine, hasLength(2));
    expect(result.manifest.toc, hasLength(2));
    expect(result.manifest.toc.first.href, 'OPS/chapter-1.xhtml');
    expect(result.manifest.toc.first.spineIndex, 0);
    expect(result.coverExtension, '.jpg');
    expect(result.coverBytes, [1, 2, 3, 4]);
  });

  test('rejects encrypted EPUB archives', () {
    final archive = Archive()
      ..addFile(ArchiveFile('META-INF/encryption.xml', 2, utf8.encode('<x/>')));
    final bytes = ZipEncoder().encode(archive);

    expect(() => parser.parseBytes(bytes), throwsA(isA<EpubParseException>()));
  });
}

List<int> _buildEpub() {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addText(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container><rootfiles><rootfile full-path="OPS/content.opf"/></rootfiles></container>''',
  );
  addText('OPS/content.opf', '''<?xml version="1.0"?>
<package version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata>
    <dc:title>Example title</dc:title>
    <dc:creator>Example author</dc:creator>
    <dc:description>Example description</dc:description>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter1" href="chapter-1.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter2" href="chapter-2.xhtml" media-type="application/xhtml+xml"/>
    <item id="cover" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
  </manifest>
  <spine page-progression-direction="rtl"><itemref idref="chapter1"/><itemref idref="chapter2"/></spine>
</package>''');
  addText(
    'OPS/nav.xhtml',
    '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="toc"><ol>
  <li><a href="chapter-1.xhtml">Chapter one</a></li>
  <li><a href="chapter-2.xhtml#part">Chapter two</a></li>
</ol></nav></body></html>''',
  );
  addText('OPS/chapter-1.xhtml', '<html><body>one</body></html>');
  addText('OPS/chapter-2.xhtml', '<html><body>two</body></html>');
  archive.addFile(ArchiveFile('OPS/images/cover.jpg', 4, [1, 2, 3, 4]));
  return ZipEncoder().encode(archive);
}
