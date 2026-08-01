import '../../domain/models/library_book.dart';
import '../../domain/models/reading_activity.dart';
import '../../domain/models/stats_models.dart';
import '../repositories/book_repository.dart';
import '../repositories/reading_session_repository.dart';

class StatsReportService {
  const StatsReportService({required this.sessions, required this.books});

  final ReadingSessionRepository sessions;
  final BookRepository books;

  Future<StatsReport> loadReport(StatsSelection selection) async {
    final activities = await sessions.listAll();
    final libraryBooks = await books.listBooks();
    final allFacts = _buildFacts(activities);
    final period = _buildPeriod(selection, allFacts);
    final facts = allFacts
        .where(
          (fact) =>
              fact.dateKey.compareTo(period.startKey) >= 0 &&
              fact.dateKey.compareTo(period.endKey) <= 0,
        )
        .toList();
    final activeFacts = facts
        .where((fact) => fact.activeMillis >= 60000)
        .toList();
    final groups = facts.expand((fact) => fact.sessionGroups).toSet();
    final touched = facts.expand((fact) => fact.books.keys).toSet();
    final summary = StatsSummary(
      activeMillis: facts.fold(0, (sum, fact) => sum + fact.activeMillis),
      activeDays: activeFacts.length,
      sessionCount: groups.length,
      booksTouched: touched.length,
      currentStreak: _currentStreak(allFacts),
    );
    return StatsReport(
      dimension: selection.dimension,
      period: period,
      summary: summary,
      timeline: _buildTimeline(selection.dimension, period, facts),
      topBooks: _buildTopBooks(facts, libraryBooks),
      canGoNext: _canGoNext(selection),
    );
  }

  List<DailyReadingFact> _buildFacts(List<ReadingActivity> activities) {
    final facts = <String, _MutableDailyFact>{};
    for (final activity in activities) {
      final endUtc = activity.endedAtUtc;
      if (endUtc == null || activity.activeMillis <= 0) continue;
      final shiftedStart = activity.startedAtUtc.add(
        Duration(minutes: activity.timezoneOffsetMinutes),
      );
      final shiftedEnd = endUtc.add(
        Duration(minutes: activity.timezoneOffsetMinutes),
      );
      final totalWall = shiftedEnd.difference(shiftedStart).inMilliseconds;
      var cursor = shiftedStart;
      while (cursor.isBefore(shiftedEnd)) {
        final nextDay = DateTime.utc(cursor.year, cursor.month, cursor.day + 1);
        final segmentEnd = shiftedEnd.isBefore(nextDay) ? shiftedEnd : nextDay;
        final segmentWall = segmentEnd.difference(cursor).inMilliseconds;
        final segmentActive = totalWall <= 0
            ? activity.activeMillis
            : (activity.activeMillis * segmentWall / totalWall).round();
        final key = _dateKey(cursor);
        final fact = facts.putIfAbsent(key, () => _MutableDailyFact(key));
        fact.activeMillis += segmentActive;
        fact.sessionGroups.add(activity.sessionGroupId);
        final book = fact.books.putIfAbsent(
          activity.bookId,
          () => _MutableBookFact(activity.bookId),
        );
        book.activeMillis += segmentActive;
        book.progressDelta += (activity.progressEnd - activity.progressStart)
            .clamp(0, 1);
        book.sessionGroups.add(activity.sessionGroupId);
        cursor = segmentEnd;
      }
    }
    return facts.values.map((fact) => fact.freeze()).toList()
      ..sort((a, b) => a.dateKey.compareTo(b.dateKey));
  }

  StatsPeriod _buildPeriod(
    StatsSelection selection,
    List<DailyReadingFact> facts,
  ) {
    final anchor = DateTime(
      selection.anchor.year,
      selection.anchor.month,
      selection.anchor.day,
    );
    return switch (selection.dimension) {
      StatsDimension.day => StatsPeriod(
        startKey: _dateKey(anchor),
        endKey: _dateKey(anchor),
        label: '${anchor.month}月${anchor.day}日',
      ),
      StatsDimension.week => () {
        final start = anchor.subtract(Duration(days: anchor.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return StatsPeriod(
          startKey: _dateKey(start),
          endKey: _dateKey(end),
          label: '${start.month}月${start.day}日 - ${end.month}月${end.day}日',
        );
      }(),
      StatsDimension.month => StatsPeriod(
        startKey: _dateKey(DateTime(anchor.year, anchor.month)),
        endKey: _dateKey(DateTime(anchor.year, anchor.month + 1, 0)),
        label: '${anchor.year}年${anchor.month}月',
      ),
      StatsDimension.year => StatsPeriod(
        startKey: _dateKey(DateTime(anchor.year)),
        endKey: _dateKey(DateTime(anchor.year, 12, 31)),
        label: '${anchor.year}年',
      ),
      StatsDimension.lifetime => StatsPeriod(
        startKey: facts.isEmpty ? _dateKey(anchor) : facts.first.dateKey,
        endKey: _dateKey(DateTime.now()),
        label: '全部阅读时间',
      ),
    };
  }

  List<ActivityPoint> _buildTimeline(
    StatsDimension dimension,
    StatsPeriod period,
    List<DailyReadingFact> facts,
  ) {
    final byDay = {for (final fact in facts) fact.dateKey: fact.activeMillis};
    if (dimension == StatsDimension.day) {
      return [
        ActivityPoint(
          label: period.label,
          activeMillis: byDay[period.startKey] ?? 0,
        ),
      ];
    }
    if (dimension == StatsDimension.week || dimension == StatsDimension.month) {
      final start = _parseDateKey(period.startKey);
      final end = _parseDateKey(period.endKey);
      final points = <ActivityPoint>[];
      for (
        var day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))
      ) {
        final key = _dateKey(day);
        points.add(
          ActivityPoint(
            label: dimension == StatsDimension.week
                ? ['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1]
                : '${day.day}',
            activeMillis: byDay[key] ?? 0,
          ),
        );
      }
      return points;
    }
    final buckets = <String, int>{};
    for (final fact in facts) {
      final date = _parseDateKey(fact.dateKey);
      final key = dimension == StatsDimension.year
          ? '${date.month}月'
          : '${date.year}年';
      buckets.update(
        key,
        (value) => value + fact.activeMillis,
        ifAbsent: () => fact.activeMillis,
      );
    }
    return buckets.entries
        .map(
          (entry) => ActivityPoint(label: entry.key, activeMillis: entry.value),
        )
        .toList();
  }

  List<TopBookEntry> _buildTopBooks(
    List<DailyReadingFact> facts,
    List<LibraryBook> books,
  ) {
    final totals = <String, (int, double)>{};
    for (final fact in facts) {
      for (final entry in fact.books.entries) {
        final current = totals[entry.key] ?? (0, 0.0);
        totals[entry.key] = (
          current.$1 + entry.value.activeMillis,
          current.$2 + entry.value.progressDelta,
        );
      }
    }
    final bookMap = {for (final book in books) book.id: book};
    final result =
        totals.entries
            .where((entry) => bookMap.containsKey(entry.key))
            .map(
              (entry) => TopBookEntry(
                book: bookMap[entry.key]!,
                activeMillis: entry.value.$1,
                progressDelta: entry.value.$2,
              ),
            )
            .toList()
          ..sort((a, b) => b.activeMillis.compareTo(a.activeMillis));
    return result.take(5).toList();
  }

  int _currentStreak(List<DailyReadingFact> facts) {
    final activeKeys = facts
        .where((fact) => fact.activeMillis >= 60000)
        .map((fact) => fact.dateKey)
        .toSet();
    var cursor = DateTime.now();
    if (!activeKeys.contains(_dateKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (activeKeys.contains(_dateKey(cursor))) {
      count += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  bool _canGoNext(StatsSelection selection) {
    if (selection.dimension == StatsDimension.lifetime) return false;
    final now = DateTime.now();
    final next = shiftStatsAnchor(selection, 1);
    return !DateTime(
      next.year,
      next.month,
      next.day,
    ).isAfter(DateTime(now.year, now.month, now.day));
  }
}

DateTime shiftStatsAnchor(StatsSelection selection, int direction) =>
    switch (selection.dimension) {
      StatsDimension.day => selection.anchor.add(Duration(days: direction)),
      StatsDimension.week => selection.anchor.add(
        Duration(days: 7 * direction),
      ),
      StatsDimension.month => DateTime(
        selection.anchor.year,
        selection.anchor.month + direction,
        1,
      ),
      StatsDimension.year => DateTime(selection.anchor.year + direction, 1, 1),
      StatsDimension.lifetime => selection.anchor,
    };

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime _parseDateKey(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

class _MutableDailyFact {
  _MutableDailyFact(this.dateKey);

  final String dateKey;
  var activeMillis = 0;
  final sessionGroups = <String>{};
  final books = <String, _MutableBookFact>{};

  DailyReadingFact freeze() => DailyReadingFact(
    dateKey: dateKey,
    activeMillis: activeMillis,
    sessionGroups: Set.unmodifiable(sessionGroups),
    books: {for (final entry in books.entries) entry.key: entry.value.freeze()},
  );
}

class _MutableBookFact {
  _MutableBookFact(this.bookId);

  final String bookId;
  var activeMillis = 0;
  var progressDelta = 0.0;
  final sessionGroups = <String>{};

  DailyBookFact freeze() => DailyBookFact(
    bookId: bookId,
    activeMillis: activeMillis,
    progressDelta: progressDelta,
    sessionGroups: Set.unmodifiable(sessionGroups),
  );
}
