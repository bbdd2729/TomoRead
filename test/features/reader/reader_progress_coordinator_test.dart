import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/features/reader/reader_drafts.dart';
import 'package:tomoread/features/reader/reader_progress_coordinator.dart';

void main() {
  test(
    'deduplicates nearby relocations and persists the latest snapshot',
    () async {
      final writes = <PendingReaderProgress>[];
      final reports = <PendingReaderProgress>[];
      final coordinator = ReaderProgressCoordinator(
        persist: (value) async => writes.add(value),
        report: reports.add,
        debounce: Duration.zero,
      );
      addTearDown(coordinator.dispose);

      coordinator.capture(
        const PendingReaderProgress(
          chapterIndex: 1,
          progress: .500,
          locator: '1:.500',
        ),
      );
      coordinator.capture(
        const PendingReaderProgress(
          chapterIndex: 1,
          progress: .501,
          locator: '1:.501',
        ),
      );
      coordinator.capture(
        const PendingReaderProgress(
          chapterIndex: 1,
          progress: .750,
          locator: '1:.750',
        ),
      );
      await coordinator.flush();

      expect(reports, hasLength(2));
      expect(writes.single.locator, '1:.750');
    },
  );
}
