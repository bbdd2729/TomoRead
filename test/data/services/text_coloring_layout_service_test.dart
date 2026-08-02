import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/text_coloring_layout_service.dart';
import 'package:tomoread/domain/models/display_projection.dart';
import 'package:tomoread/domain/models/text_coloring.dart';

void main() {
  const service = TextColoringLayoutService();

  test('longest term wins before shorter overlapping terms', () async {
    final layout = await service.layout(
      projection: DisplayProjection.identity('catalog cat'),
      coloring: _coloring([
        _term('short', 'cat', TextColorTermTone.blue),
        _term('long', 'catalog', TextColorTermTone.purple),
      ]),
      markdown: false,
      dark: false,
    );

    expect(
      layout.colors.map((range) => (
        layout.text.substring(range.start, range.end),
        range.colorKey,
      )),
      [
        ('catalog', 'term-purple'),
        ('cat', 'term-blue'),
      ],
    );
  });

  test('book term wins over global term with the same text', () async {
    final layout = await service.layout(
      projection: DisplayProjection.identity('TomoRead'),
      coloring: _coloring([
        _term('global', 'TomoRead', TextColorTermTone.blue),
        _term(
          'book',
          'TomoRead',
          TextColorTermTone.rose,
          bookId: 'book-1',
        ),
      ]),
      markdown: false,
      dark: false,
    );

    expect(layout.colors, hasLength(1));
    expect(layout.colors.single.colorKey, 'term-rose');
  });

  test('semantic rules do not overwrite an earlier quoted range', () async {
    final defaults = TextColoringSettings.defaults();
    final settings = defaults.copyWith(
      enabled: true,
      tokens: {
        ...defaults.tokens,
        TextColorSemanticToken.quoted: defaults.tokens[TextColorSemanticToken.quoted]!
            .copyWith(enabled: true),
        TextColorSemanticToken.latin: defaults.tokens[TextColorSemanticToken.latin]!
            .copyWith(enabled: true),
      },
    );
    final layout = await service.layout(
      projection: DisplayProjection.identity('“Hello” X'),
      coloring: ResolvedTextColoring(
        settings: settings,
        enabled: true,
        terms: const [],
      ),
      markdown: false,
      dark: false,
    );

    expect(
      layout.colors.map((range) => (
        layout.text.substring(range.start, range.end),
        range.colorKey,
      )),
      [
        ('Hello', 'token-quoted'),
        ('X', 'token-latin'),
      ],
    );
  });

  test('ambiguous display projection is conservatively left uncolored', () async {
    const projection = DisplayProjection(
      rawText: 'a',
      displayText: 'aa',
      segments: [
        ProjectionSegment(
          rawStart: 0,
          rawEnd: 1,
          displayStart: 0,
          displayEnd: 2,
          isExact: false,
        ),
      ],
      mappingCells: [
        ProjectionCell(rawStart: 0, rawEnd: 1, isExact: false),
        ProjectionCell(rawStart: 0, rawEnd: 1, isExact: false),
      ],
    );
    final layout = await service.layout(
      projection: projection,
      coloring: _coloring([_term('ambiguous', 'aa', TextColorTermTone.blue)]),
      markdown: false,
      dark: false,
    );

    expect(layout.colors, isEmpty);
  });

  test('Markdown colors visible prose but skips code URL and image alt', () async {
    const source =
        '# Body\n`code` [label](https://example.com) '
        '![alt](image.png)\n```\ncode\n```';
    final layout = await service.layout(
      projection: DisplayProjection.identity(source),
      coloring: _coloring([
        _term('body', 'Body', TextColorTermTone.rose),
        _term('code', 'code', TextColorTermTone.orange),
        _term('label', 'label', TextColorTermTone.green),
        _term('url', 'https://example.com', TextColorTermTone.blue),
        _term('alt', 'alt', TextColorTermTone.purple),
      ]),
      markdown: true,
      dark: false,
    );

    final coloredText = layout.colors
        .map((range) => layout.text.substring(range.start, range.end))
        .toList();
    expect(coloredText, containsAll(['Body', 'label']));
    expect(coloredText, isNot(contains('code')));
    expect(coloredText, isNot(contains('alt')));
    expect(layout.text, isNot(contains('https://example.com')));

    final labelStart = layout.text.indexOf('label');
    final labelRange = layout.visibleToDisplay(labelStart, labelStart + 5);
    expect(labelRange.isExact, isTrue);
    expect(source.substring(labelRange.start, labelRange.end), 'label');
  });
}

ResolvedTextColoring _coloring(List<TextColorTerm> terms) {
  final settings = TextColoringSettings.defaults().copyWith(enabled: true);
  return ResolvedTextColoring(
    settings: settings,
    enabled: true,
    terms: terms,
  );
}

TextColorTerm _term(
  String id,
  String text,
  TextColorTermTone tone, {
  String? bookId,
}) => TextColorTerm(
  id: id,
  bookId: bookId,
  term: text,
  normalizedTerm: normalizeTextColorTerm(text),
  tone: tone,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
