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
}
