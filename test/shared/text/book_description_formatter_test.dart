import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/shared/text/book_description_formatter.dart';

void main() {
  group('BookDescriptionFormatter', () {
    test('converts escaped EPUB HTML into readable paragraphs', () {
      final description = BookDescriptionFormatter.format(
        '&lt;p&gt;第一段&lt;br/&gt;继续&lt;/p&gt;&lt;p&gt;第二段&lt;/p&gt;',
      );

      expect(description, '第一段\n继续\n\n第二段');
    });

    test(
      'formats lists and decodes text entities without rendering markup',
      () {
        final description = BookDescriptionFormatter.format(
          '<div>作者&amp;译者</div><ul><li>条目一</li><li>条目二</li></ul>',
        );

        expect(description, '作者&译者\n\n• 条目一\n• 条目二');
        expect(description, isNot(contains('<li>')));
      },
    );

    test('preserves plain text and removes non-display metadata markup', () {
      final description = BookDescriptionFormatter.format(
        '普通简介 <script>alert(1)</script> 保留文字',
      );

      expect(description, '普通简介 保留文字');
    });
  });
}
