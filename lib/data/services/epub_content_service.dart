import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/reader_chapter.dart';

class EpubContentException implements Exception {
  const EpubContentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EpubContentService {
  const EpubContentService();

  Future<ReaderChapter> loadChapter({
    required LibraryBook book,
    required EpubManifest manifest,
    required int chapterIndex,
  }) async {
    final file = File(book.filePath);
    if (!await file.exists()) {
      throw const EpubContentException('找不到已导入的 EPUB 文件');
    }
    return loadChapterFromBytes(
      epubBytes: await file.readAsBytes(),
      manifest: manifest,
      chapterIndex: chapterIndex,
    );
  }

  ReaderChapter loadChapterFromBytes({
    required List<int> epubBytes,
    required EpubManifest manifest,
    required int chapterIndex,
  }) {
    if (chapterIndex < 0 || chapterIndex >= manifest.spine.length) {
      throw const EpubContentException('章节索引无效');
    }
    try {
      final archive = ZipDecoder().decodeBytes(epubBytes);
      final spineItem = manifest.spine[chapterIndex];
      final file = archive.findFile(spineItem.href);
      if (file == null) {
        throw EpubContentException('找不到章节文件：${spineItem.href}');
      }
      return _parseChapter(
        utf8.decode(file.content as List<int>, allowMalformed: true),
        index: chapterIndex,
        href: spineItem.href,
      );
    } on EpubContentException {
      rethrow;
    } catch (error) {
      throw EpubContentException('无法读取章节内容：$error');
    }
  }

  ReaderChapter _parseChapter(
    String source, {
    required int index,
    required String href,
  }) {
    final document = XmlDocument.parse(source);
    final body = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local.toLowerCase() == 'body')
        .firstOrNull;
    final root = body ?? document.rootElement;
    final blocks = <ReaderChapterBlock>[];
    for (final element in root.descendants.whereType<XmlElement>()) {
      final tag = element.name.local.toLowerCase();
      final isHeading = RegExp(r'^h[1-6]$').hasMatch(tag);
      if (!isHeading && !const {'p', 'li', 'blockquote', 'pre'}.contains(tag)) {
        continue;
      }
      final text = _normalizeText(element.innerText);
      if (text.isNotEmpty) {
        blocks.add(ReaderChapterBlock(text: text, isHeading: isHeading));
      }
    }

    if (blocks.isEmpty) {
      final text = _normalizeText(root.innerText);
      if (text.isNotEmpty) {
        blocks.add(ReaderChapterBlock(text: text, isHeading: false));
      }
    }

    final heading = blocks.where((block) => block.isHeading).firstOrNull;
    return ReaderChapter(
      index: index,
      href: href,
      title: heading?.text ?? '第 ${index + 1} 章',
      blocks: blocks,
    );
  }

  String _normalizeText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').replaceAll('\u00a0', ' ').trim();
}
