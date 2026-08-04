import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/document_locator.dart';
import 'package:tomoread/domain/models/epub_location.dart';

void main() {
  test('validates shared locator regression fixtures', () async {
    final fixtures = jsonDecode(
      await File('test/fixtures/locator_contracts.json').readAsString(),
    ) as List<dynamic>;

    for (final value in fixtures.cast<Map<String, dynamic>>()) {
      final locator = switch (value['format']) {
        'epub' => EpubDocumentLocator.tryParse(
          value['locator'] as String,
          fallbackChapterIndex: 0,
        ),
        'pdf' => PdfDocumentLocator.tryParse(value['locator'] as String),
        'text' => TextDocumentLocator.tryParse(value['locator'] as String),
        _ => null,
      };
      expect(
        locator != null,
        value['valid'],
        reason: '${value['format']}: ${value['locator']}',
      );
      if (value['valid'] == true && locator != null) {
        final reparsed = switch (locator.kind) {
          DocumentLocatorKind.epub => EpubDocumentLocator.tryParse(
            locator.serialize(),
            fallbackChapterIndex: 0,
          ),
          DocumentLocatorKind.pdf => PdfDocumentLocator.tryParse(
            locator.serialize(),
          ),
          DocumentLocatorKind.text => TextDocumentLocator.tryParse(
            locator.serialize(),
          ),
        };
        expect(
          reparsed,
          isNotNull,
          reason: 'reparse ${value['format']}: ${value['locator']}',
        );
        expect(
          reparsed!.serialize(),
          locator.serialize(),
          reason: 'round-trip stable ${value['format']}: ${value['locator']}',
        );
      }
    }
  });

  test('round-trips a precise EPUB locator without changing storage format', () {
    const locator = EpubDocumentLocator(
      href: 'OPS/chapter.xhtml',
      location: EpubLocation(
        chapterIndex: 2,
        scrollRatio: 0.5,
        anchor: 'heading',
        cfi: 'epubcfi(/6/4!/4/2)',
      ),
    );

    final restored = EpubDocumentLocator.tryParse(
      locator.serialize(),
      fallbackChapterIndex: 0,
      href: locator.href,
    );

    expect(restored?.href, locator.href);
    expect(restored?.location.cfi, locator.location.cfi);
    expect(restored?.precision, DocumentLocatorPrecision.exact);
  });

  test('round-trips PDF text geometry and quote context', () {
    const locator = PdfDocumentLocator(
      pageNumber: 12,
      rects: [
        PdfNormalizedRect(left: .12, top: .31, width: .74, height: .04),
      ],
      quote: 'selected text',
      prefix: 'before',
      suffix: 'after',
    );

    final restored = PdfDocumentLocator.tryParse(locator.serialize());

    expect(restored?.pageNumber, 12);
    expect(restored?.rects.single.left, closeTo(.12, .000001));
    expect(restored?.quote, locator.quote);
    expect(restored?.precision, DocumentLocatorPrecision.exact);
  });

  test('rejects unsafe or ambiguous text ranges', () {
    expect(TextDocumentLocator.tryParse('text:v1|0|-1|2'), isNull);
    expect(TextDocumentLocator.tryParse('text:v1|0|5|4'), isNull);
    expect(TextDocumentLocator.tryParse('0|5|5'), isNull);
  });
}
