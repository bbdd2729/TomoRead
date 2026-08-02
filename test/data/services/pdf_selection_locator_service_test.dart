import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/pdf_selection_locator_service.dart';

void main() {
  const service = PdfSelectionLocatorService();

  group('PdfSelectionLocatorService', () {
    test('creates normalized geometry with verified quote context', () {
      const pageText = 'Before context\nSelected   text\nafter context';
      final selection = service.create(
        const PdfSelectionSource(
          pageNumber: 2,
          pageText: pageText,
          start: 15,
          end: 30,
          pageWidth: 200,
          pageHeight: 400,
          rects: [
            PdfSelectionSourceRect(
              left: 20,
              top: 80,
              width: 160,
              height: 20,
            ),
          ],
        ),
      );

      expect(selection.text, 'Selected text');
      expect(selection.locator.pageNumber, 2);
      expect(selection.locator.rects.single.left, .1);
      expect(selection.locator.rects.single.top, .2);
      expect(selection.locator.rects.single.width, .8);
      expect(selection.locator.rects.single.height, .05);
      expect(service.verifies(selection.locator, pageText), isTrue);
    });

    test('rejects quote when its saved context no longer matches', () {
      final selection = service.create(
        const PdfSelectionSource(
          pageNumber: 1,
          pageText: 'alpha repeated phrase omega',
          start: 6,
          end: 21,
          pageWidth: 100,
          pageHeight: 100,
          rects: [
            PdfSelectionSourceRect(
              left: 10,
              top: 10,
              width: 50,
              height: 10,
            ),
          ],
        ),
      );

      expect(
        service.verifies(
          selection.locator,
          'different repeated phrase surroundings',
        ),
        isFalse,
      );
    });

    test('does not create an exact locator without usable geometry', () {
      expect(
        () => service.create(
          const PdfSelectionSource(
            pageNumber: 1,
            pageText: 'select me',
            start: 0,
            end: 6,
            pageWidth: 100,
            pageHeight: 100,
            rects: [],
          ),
        ),
        throwsA(
          isA<PdfSelectionException>().having(
            (error) => error.reason,
            'reason',
            PdfSelectionFailureReason.invalidGeometry,
          ),
        ),
      );
    });

    test('rejects an empty or out-of-bounds text range', () {
      expect(
        () => service.create(
          const PdfSelectionSource(
            pageNumber: 1,
            pageText: 'short',
            start: 2,
            end: 20,
            pageWidth: 100,
            pageHeight: 100,
            rects: [
              PdfSelectionSourceRect(
                left: 10,
                top: 10,
                width: 20,
                height: 10,
              ),
            ],
          ),
        ),
        throwsA(
          isA<PdfSelectionException>().having(
            (error) => error.reason,
            'reason',
            PdfSelectionFailureReason.invalidRange,
          ),
        ),
      );
    });
  });
}
