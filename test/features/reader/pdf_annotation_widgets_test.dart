import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/reading_annotation.dart';
import 'package:tomoread/features/reader/pdf_annotation_widgets.dart';

void main() {
  testWidgets('lists PDF annotations and removes a selected item', (
    tester,
  ) async {
    final annotation = ReadingAnnotation(
      id: 'pdf-note-1',
      bookId: 'book-1',
      href: 'pdf:page:3',
      locator: 'pdf:v1|3|0.1,0.2,0.3,0.1|quote|before|after',
      selectedText: 'quote',
      color: AnnotationColor.blue,
      createdAt: DateTime(2026),
      chapterIndex: 2,
      chapterTitle: '第 3 页',
    );
    var deletedId = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<ReadingAnnotation>(
                context: context,
                builder: (_) => PdfAnnotationsDialog(
                  annotations: [annotation],
                  onDelete: (value) async {
                    deletedId = value.id;
                  },
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('quote'), findsOneWidget);
    expect(find.text('第 3 页'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf-annotation-delete-pdf-note-1')));
    await tester.pumpAndSettle();
    expect(deletedId, 'pdf-note-1');
    expect(find.text('quote'), findsNothing);
    expect(find.text('还没有 PDF 标注。'), findsOneWidget);
  });
}
