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
}
