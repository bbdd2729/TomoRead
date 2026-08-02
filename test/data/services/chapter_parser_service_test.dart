import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/chapter_parser_service.dart';

void main() {
  test('prioritizes Markdown headings and preserves raw UTF-16 offsets', () async {
    const text = '''前置说明
# 第一章
正文😀
第二章
---
内容
第3章 结尾
尾声''';

    final result = await const ChapterParserService().parse(
      bookId: 'book-a',
      text: text,
      contentHash: 'hash-a',
      markdown: true,
    );

    expect(result.chapters.first.title, '正文开始前');
    expect(result.chapters[1].title, '第一章');
    expect(result.chapters[2].title, '第二章');
    expect(result.chapters[3].title, '第3章 结尾');
    expect(result.chapters.last.title, '尾声');
    expect(
      result.chapters[1].rawStart,
      text.indexOf('# 第一章'),
    );
    expect(
      result.chapters[1].locator(),
      'text:v1|1|${result.chapters[1].rawStart}|${result.chapters[1].rawEnd}',
    );
    expect(
      result.rulePreviews
          .firstWhere((preview) => preview.ruleId == 'markdown-atx')
          .matchCount,
      1,
    );
  });
}
