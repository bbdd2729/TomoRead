import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/epub_location.dart';

void main() {
  test('round-trips an EPUB location with an anchor', () {
    const location = EpubLocation(
      chapterIndex: 4,
      scrollRatio: 0.375,
      anchor: 'section:two',
    );

    final restored = EpubLocation.fromLocator(
      location.toLocator(),
      fallbackChapterIndex: 0,
    );

    expect(restored.chapterIndex, 4);
    expect(restored.scrollRatio, closeTo(0.375, 0.00001));
    expect(restored.anchor, 'section:two');
    expect(location.toLocator(), 'epub:v3|4|0.37500|section%3Atwo|');
  });

  test('reads legacy progress and chapter bookmark locators', () {
    final progress = EpubLocation.fromLocator('2:0.5', fallbackChapterIndex: 0);
    final bookmark = EpubLocation.fromLocator(
      'chapter-3:start',
      fallbackChapterIndex: 0,
    );

    expect(progress.chapterIndex, 2);
    expect(progress.scrollRatio, 0.5);
    expect(bookmark.chapterIndex, 3);
    expect(bookmark.scrollRatio, 0);
  });

  test('matches versioned locations with legacy bookmarks', () {
    const current = EpubLocation(
      chapterIndex: 2,
      scrollRatio: 0.5,
      anchor: 'heading',
    );

    expect(
      EpubLocation.matchesLocator(
        'epub:2|0.50000|',
        current,
        fallbackChapterIndex: 0,
      ),
      isTrue,
    );
  });

  test('uses measured page position for paginated relocation progress', () {
    expect(
      EpubLocation.normalizedRelocationRatio(
        reportedRatio: 0,
        paginated: true,
        pageIndex: 2,
        pageCount: 5,
      ),
      0.5,
    );
    expect(
      EpubLocation.normalizedRelocationRatio(
        reportedRatio: 0.35,
        paginated: false,
        pageIndex: 2,
        pageCount: 5,
      ),
      0.35,
    );
  });

  test('does not match bookmarks from different pages in one chapter', () {
    const secondPage = EpubLocation(
      chapterIndex: 0,
      scrollRatio: 0.25,
      cfi: 'epubcfi(/6/4!/4/2/2)',
    );

    expect(
      EpubLocation.matchesLocator(
        'epub:v3|0|0.00000||',
        secondPage,
        fallbackChapterIndex: 0,
      ),
      isFalse,
    );
  });

  test('keeps pagination progress normalized when page count changes', () {
    expect(
      EpubLocation.normalizedRelocationRatio(
        reportedRatio: 0,
        paginated: true,
        pageIndex: 2,
        pageCount: 5,
      ),
      0.5,
    );
    expect(
      EpubLocation.normalizedRelocationRatio(
        reportedRatio: 0,
        paginated: true,
        pageIndex: 2,
        pageCount: 3,
      ),
      1.0,
    );
    expect(
      EpubLocation.normalizedRelocationRatio(
        reportedRatio: 0,
        paginated: true,
        pageIndex: 0,
        pageCount: 3,
      ),
      0.0,
    );
  });

  test('matches a legacy v2 anchor after layout change', () {
    const location = EpubLocation(
      chapterIndex: 1,
      scrollRatio: 0.25,
      anchor: 'heading',
    );

    expect(
      EpubLocation.matchesLocator(
        'epub:v2|1|0.90000|heading',
        location,
        fallbackChapterIndex: 0,
      ),
      isTrue,
    );
  });

  test('matches legacy ratio-only progress in the same chapter', () {
    const location = EpubLocation(
      chapterIndex: 2,
      scrollRatio: 0.5,
    );

    expect(
      EpubLocation.matchesLocator(
        'epub:2|0.50000|',
        location,
        fallbackChapterIndex: 0,
      ),
      isTrue,
    );
  });
}
