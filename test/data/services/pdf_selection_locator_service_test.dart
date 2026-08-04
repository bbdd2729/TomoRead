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

    test('normalized rects survive zoom and viewport changes', () {
      final selection = service.create(
        const PdfSelectionSource(
          pageNumber: 1,
          pageText: 'target phrase stays put',
          start: 0,
          end: 14,
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
      final rect = selection.locator.rects.single;

      const zoomed = PdfSelectionSource(
        pageNumber: 1,
        pageText: 'target phrase stays put',
        start: 0,
        end: 14,
        pageWidth: 1200,
        pageHeight: 2400,
        rects: [
          PdfSelectionSourceRect(
            left: 120,
            top: 480,
            width: 960,
            height: 120,
          ),
        ],
      );
      final zoomedSelection = service.create(zoomed);

      expect(zoomedSelection.locator.rects.single.left, closeTo(rect.left, .000001));
      expect(zoomedSelection.locator.rects.single.top, closeTo(rect.top, .000001));
      expect(zoomedSelection.locator.rects.single.width, closeTo(rect.width, .000001));
      expect(zoomedSelection.locator.rects.single.height, closeTo(rect.height, .000001));
    });

    test('verifies a persisted locator after text reflow keeps the quote', () {
      final original = service.create(
        const PdfSelectionSource(
          pageNumber: 3,
          pageText: 'The quick brown fox jumps over the lazy dog',
          start: 4,
          end: 15,
          pageWidth: 100,
          pageHeight: 100,
          rects: [
            PdfSelectionSourceRect(
              left: 10,
              top: 20,
              width: 60,
              height: 10,
            ),
          ],
        ),
      );

      final reflowed = 'The quick\nbrown fox\njumps over\nthe lazy dog';
      expect(service.verifies(original.locator, reflowed), isTrue);
    });

    test('persisted quote context no longer matches after content change', () {
      final original = service.create(
        const PdfSelectionSource(
          pageNumber: 3,
          pageText: 'The quick brown fox jumps over the lazy dog',
          start: 4,
          end: 15,
          pageWidth: 100,
          pageHeight: 100,
          rects: [
            PdfSelectionSourceRect(
              left: 10,
              top: 20,
              width: 60,
              height: 10,
            ),
          ],
        ),
      );

      expect(
        service.verifies(original.locator, 'The slow green turtle crawls past'),
        isFalse,
      );
    });
  });
}
