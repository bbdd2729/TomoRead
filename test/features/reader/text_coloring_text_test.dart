import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/text_coloring_layout.dart';
import 'package:tomoread/features/reader/text_coloring_text.dart';

void main() {
  testWidgets('renders foreground colors and keeps selection callbacks', (
    tester,
  ) async {
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
        home: Scaffold(
          body: TextColoringSelectableText(
            layout: layout,
            style: const TextStyle(fontSize: 18),
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

    selectable.onSelectionChanged!(
      const TextSelection(baseOffset: 0, extentOffset: 5),
      SelectionChangedCause.tap,
    );
    expect(selected, const TextSelection(baseOffset: 0, extentOffset: 5));
  });
}
