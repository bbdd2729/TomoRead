import 'dart:isolate';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models/text_chapter.dart';

class ChapterParserService {
  const ChapterParserService();

  static const parserVersion = 1;

  Future<TextChapterParseResult> parse({
    required String bookId,
    required String text,
    required String contentHash,
    required bool markdown,
  }) => Isolate.run(
    () => parseTextChapters((bookId, text, contentHash, markdown)),
  );
}

TextChapterParseResult parseTextChapters(
  (String bookId, String text, String contentHash, bool markdown) request,
) {
  final (bookId, text, _, markdown) = request;
  final lines = _linesWithOffsets(text);
  final matches = <_ChapterMatch>[];
  final previews = <String, List<String>>{};

  void addMatch(String ruleId, String title, int offset, String sourceLine) {
    matches.add(_ChapterMatch(ruleId, title.trim(), offset));
    final values = previews.putIfAbsent(ruleId, () => <String>[]);
    if (values.length < 10) values.add(sourceLine.trim());
  }

  if (markdown) {
    final atx = RegExp(r'^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$');
    final setext = RegExp(r'^\s*(=+|-+)\s*$');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final atxMatch = atx.firstMatch(line.text);
      if (atxMatch != null) {
        addMatch('markdown-atx', atxMatch.group(1)!, line.start, line.text);
        continue;
      }
      if (index > 0 &&
          line.text.trim().isNotEmpty &&
          setext.hasMatch(line.text) &&
          lines[index - 1].text.trim().isNotEmpty) {
        final heading = lines[index - 1];
        addMatch('markdown-setext', heading.text, heading.start, heading.text);
      }
    }
  }

  final occupied = matches.map((item) => item.offset).toSet();
  final chineseNumber = RegExp(
    r'^\s*第\s*[0-9０-９一二三四五六七八九十百千万零〇两]+\s*[章回卷节集部篇](?:\s+|[:：、.-]*)(.*)\s*$',
  );
  final special = RegExp(
    r'^\s*(序章|序言|前言|引子|楔子|后记|尾声|番外(?:\s*[0-9一二三四五六七八九十]*)?)(?:\s+.*)?$',
  );
  final ordered = RegExp(r'^\s*([0-9０-９]{1,4})[、.．]\s*(\S.*)$');
  for (final line in lines) {
    if (occupied.contains(line.start)) continue;
    final value = line.text.trim();
    if (value.isEmpty || value.length > 120) continue;
    final chapterMatch = chineseNumber.firstMatch(value);
    if (chapterMatch != null) {
      addMatch('chinese-chapter', value, line.start, line.text);
      continue;
    }
    if (special.hasMatch(value)) {
      addMatch('special-heading', value, line.start, line.text);
      continue;
    }
    if (ordered.hasMatch(value)) {
      addMatch('numeric-heading', value, line.start, line.text);
    }
  }

  matches.sort((a, b) {
    final offset = a.offset.compareTo(b.offset);
    if (offset != 0) return offset;
    final aMarkdown = a.ruleId.startsWith('markdown') ? 0 : 1;
    final bMarkdown = b.ruleId.startsWith('markdown') ? 0 : 1;
    return aMarkdown.compareTo(bMarkdown);
  });
  final deduplicated = <_ChapterMatch>[];
  for (final match in matches) {
    if (deduplicated.isEmpty || deduplicated.last.offset != match.offset) {
      deduplicated.add(match);
    }
  }
  if (deduplicated.isEmpty) {
    deduplicated.add(const _ChapterMatch('fallback', '正文', 0));
  } else if (deduplicated.first.offset > 0) {
    deduplicated.insert(0, const _ChapterMatch('preface', '正文开始前', 0));
  }

  final chapters = <TextChapter>[];
  for (var index = 0; index < deduplicated.length; index++) {
    final match = deduplicated[index];
    final end = index + 1 < deduplicated.length
        ? deduplicated[index + 1].offset
        : text.length;
    final chapterHash = sha256
        .convert(utf8.encode(text.substring(match.offset, end)))
        .toString();
    chapters.add(
      TextChapter(
        id: '$bookId-${chapterHash.substring(0, 16)}-$index',
        bookId: bookId,
        ordinal: index,
        title: match.title,
        rawStart: match.offset,
        rawEnd: end,
        sourceRuleId: match.ruleId,
        contentHash: chapterHash,
      ),
    );
  }
  return TextChapterParseResult(
    chapters: chapters,
    rulePreviews: previews.entries
        .map(
          (entry) => ChapterRulePreview(
            ruleId: entry.key,
            matchCount: matches
                .where((match) => match.ruleId == entry.key)
                .length,
            examples: entry.value,
          ),
        )
        .toList(),
  );
}

List<_TextLine> _linesWithOffsets(String text) {
  final result = <_TextLine>[];
  var start = 0;
  for (var index = 0; index <= text.length; index++) {
    if (index == text.length || text.codeUnitAt(index) == 0x0a) {
      var end = index;
      if (end > start && text.codeUnitAt(end - 1) == 0x0d) end--;
      result.add(_TextLine(text.substring(start, end), start));
      start = index + 1;
    }
  }
  return result;
}

class _TextLine {
  const _TextLine(this.text, this.start);

  final String text;
  final int start;
}

class _ChapterMatch {
  const _ChapterMatch(this.ruleId, this.title, this.offset);

  final String ruleId;
  final String title;
  final int offset;
}
