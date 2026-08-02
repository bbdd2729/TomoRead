import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/text_coloring_layout.dart';
import 'package:tomoread/features/reader/text_coloring_text.dart';

void main() {
  testWidgets('renders foreground colors and keeps selection callbacks', (
    tester,
  ) async {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );
    final plain = TextColoringLayout.plain('Color text');
    final layout = TextColoringLayout(
      text: plain.text,
      displaySourceLength: plain.displaySourceLength,
      sourceCells: plain.sourceCells,
      styles: const [
        MarkdownTextStyleRange(
          start: 6,
          end: 10,
          style: MarkdownTextStyle(code: true),
        ),
      ],
      colors: const [
        TextColoringRange(
          start: 0,
          end: 5,
          rawStart: 0,
          rawEnd: 5,
          colorKey: 'term-blue',
          hexColor: '#246B9B',
        ),
      ],
    );
    TextSelection? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: TextColoringSelectableText(
            layout: layout,
            style: const TextStyle(fontSize: 18),
            emphasisRange: const TextEmphasisRange(start: 6, end: 10),
            onSelectionChanged: (selection, _) => selected = selection,
          ),
        ),
      ),
    );

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    final spans = selectable.textSpan!.children!.cast<TextSpan>().toList();
    expect(spans.map((span) => span.text).join(), 'Color text');
    expect(spans.first.style?.color, const Color(0xff246b9b));
    expect(spans.last.style?.fontFamily, 'monospace');
    expect(
      spans.last.style?.backgroundColor,
      theme.colorScheme.primaryContainer,
    );

    selectable.onSelectionChanged!(
      const TextSelection(baseOffset: 0, extentOffset: 5),
      SelectionChangedCause.tap,
    );
    expect(selected, const TextSelection(baseOffset: 0, extentOffset: 5));
  });

  test('maps display offsets back to visible markdown text', () {
    const layout = TextColoringLayout(
      text: 'Title',
      displaySourceLength: 7,
      sourceCells: [
        TextColoringSourceCell(sourceStart: 2, sourceEnd: 3, isExact: true),
        TextColoringSourceCell(sourceStart: 3, sourceEnd: 4, isExact: true),
        TextColoringSourceCell(sourceStart: 4, sourceEnd: 5, isExact: true),
        TextColoringSourceCell(sourceStart: 5, sourceEnd: 6, isExact: true),
        TextColoringSourceCell(sourceStart: 6, sourceEnd: 7, isExact: true),
      ],
      styles: [],
      colors: [],
    );

    final visible = layout.displayToVisible(2, 7);

    expect((visible.start, visible.end, visible.isExact), (0, 5, true));
  });
}
