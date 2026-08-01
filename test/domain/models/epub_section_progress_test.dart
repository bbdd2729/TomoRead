import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/epub_section_progress.dart';

void main() {
  test('weights whole-book progress by section size', () {
    final progress = EpubSectionProgress.fromSizes([100, 300, 600]);

    expect(progress.overallProgress(0, 0.5), closeTo(0.05, 0.00001));
    expect(progress.overallProgress(1, 0.5), closeTo(0.25, 0.00001));
    expect(progress.overallProgress(2, 0.5), closeTo(0.7, 0.00001));
  });

  test('locates a whole-book progress value inside its weighted section', () {
    final progress = EpubSectionProgress.fromSizes([100, 300, 600]);

    final location = progress.locationForProgress(0.7);

    expect(location.chapterIndex, 2);
    expect(location.chapterRatio, closeTo(0.5, 0.00001));
  });

  test('falls back to equal sections when no resources have a size', () {
    final progress = EpubSectionProgress.fromSizes([0, 0]);

    expect(progress.overallProgress(1, 0), closeTo(0.5, 0.00001));
    final location = progress.locationForProgress(0.75);
    expect(location.chapterIndex, 1);
    expect(location.chapterRatio, closeTo(0.5, 0.00001));
  });
}
