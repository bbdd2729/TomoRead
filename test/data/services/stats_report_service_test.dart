import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/data/repositories/reading_session_repository.dart';
import 'package:tomoread/data/services/stats_report_service.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/reading_activity.dart';
import 'package:tomoread/domain/models/stats_models.dart';

void main() {
  late AppDatabase database;
  late ReadingSessionRepository sessions;
  late StatsReportService service;

  setUp(() async {
    database = AppDatabase.inMemory();
    final books = BookRepository(database);
    sessions = ReadingSessionRepository(database);
    service = StatsReportService(sessions: sessions, books: books);
    await books.saveImportedPdfBook(_book());
  });

  tearDown(() => database.close());

  test('builds a daily report from completed reading activity', () async {
    final timezoneOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final localEnd = DateTime.utc(2026, 6, 15, 12);
    final end = localEnd.subtract(Duration(minutes: timezoneOffsetMinutes));
    final start = end.subtract(const Duration(minutes: 10));
    await sessions.start(
      id: 'activity-a',
      sessionGroupId: 'group-a',
      identity: const ReaderIdentity(
        bookId: 'book-a',
        format: ReaderFormat.pdf,
      ),
      position: const ReaderPosition(progress: .1, locator: 'page:1'),
      nowUtc: start,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
    await sessions.checkpoint(
      id: 'activity-a',
      nowUtc: end,
      endedAtUtc: end,
      activeMillis: const Duration(minutes: 10).inMilliseconds,
      position: const ReaderPosition(progress: .3, locator: 'page:3'),
      interactionCount: 3,
    );

    final report = await service.loadReport(
      StatsSelection(
        dimension: StatsDimension.day,
        anchor: DateTime(2026, 6, 15),
      ),
    );

    expect(
      report.summary.activeMillis,
      const Duration(minutes: 10).inMilliseconds,
    );
    expect(report.summary.activeDays, 1);
    expect(report.summary.sessionCount, 1);
    expect(report.summary.booksTouched, 1);
    expect(report.topBooks.single.book.id, 'book-a');
    expect(report.topBooks.single.progressDelta, closeTo(.2, .0001));
  });
}

LibraryBook _book() => LibraryBook(
  id: 'book-a',
  fileHash: 'hash-a',
  title: '统计测试',
  author: '作者',
  filePath: 'book.pdf',
  progress: 0,
  importedAt: DateTime(2026),
  format: 'pdf',
  chapterCount: 10,
  direction: ReadingDirection.ltr,
);
