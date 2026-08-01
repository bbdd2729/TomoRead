import 'library_book.dart';

enum StatsDimension { day, week, month, year, lifetime }

class StatsSelection {
  const StatsSelection({
    this.dimension = StatsDimension.week,
    required this.anchor,
  });

  final StatsDimension dimension;
  final DateTime anchor;

  StatsSelection copyWith({StatsDimension? dimension, DateTime? anchor}) =>
      StatsSelection(
        dimension: dimension ?? this.dimension,
        anchor: anchor ?? this.anchor,
      );
}

class DailyBookFact {
  const DailyBookFact({
    required this.bookId,
    required this.activeMillis,
    required this.progressDelta,
    required this.sessionGroups,
  });

  final String bookId;
  final int activeMillis;
  final double progressDelta;
  final Set<String> sessionGroups;
}

class DailyReadingFact {
  const DailyReadingFact({
    required this.dateKey,
    required this.activeMillis,
    required this.sessionGroups,
    required this.books,
  });

  final String dateKey;
  final int activeMillis;
  final Set<String> sessionGroups;
  final Map<String, DailyBookFact> books;
}

class StatsPeriod {
  const StatsPeriod({
    required this.startKey,
    required this.endKey,
    required this.label,
  });

  final String startKey;
  final String endKey;
  final String label;
}

class StatsSummary {
  const StatsSummary({
    required this.activeMillis,
    required this.activeDays,
    required this.sessionCount,
    required this.booksTouched,
    required this.currentStreak,
  });

  final int activeMillis;
  final int activeDays;
  final int sessionCount;
  final int booksTouched;
  final int currentStreak;
}

class ActivityPoint {
  const ActivityPoint({required this.label, required this.activeMillis});

  final String label;
  final int activeMillis;
}

class TopBookEntry {
  const TopBookEntry({
    required this.book,
    required this.activeMillis,
    required this.progressDelta,
  });

  final LibraryBook book;
  final int activeMillis;
  final double progressDelta;
}

class StatsReport {
  const StatsReport({
    required this.dimension,
    required this.period,
    required this.summary,
    required this.timeline,
    required this.topBooks,
    required this.canGoNext,
  });

  final StatsDimension dimension;
  final StatsPeriod period;
  final StatsSummary summary;
  final List<ActivityPoint> timeline;
  final List<TopBookEntry> topBooks;
  final bool canGoNext;
}
