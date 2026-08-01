enum ReaderFormat { epub, pdf }

enum ReadingInteraction { pageTurn, scroll, navigation, seek, selection }

class ReaderIdentity {
  const ReaderIdentity({required this.bookId, required this.format});

  final String bookId;
  final ReaderFormat format;
}

class ReaderPosition {
  const ReaderPosition({required this.progress, this.locator});

  final double progress;
  final String? locator;
}

class ReadingActivity {
  const ReadingActivity({
    required this.id,
    required this.bookId,
    required this.sessionGroupId,
    required this.format,
    required this.startedAtUtc,
    required this.activeMillis,
    required this.timezoneOffsetMinutes,
    required this.progressStart,
    required this.progressEnd,
    required this.interactionCount,
    required this.updatedAtUtc,
    this.endedAtUtc,
    this.locatorStart,
    this.locatorEnd,
  });

  final String id;
  final String bookId;
  final String sessionGroupId;
  final ReaderFormat format;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final int activeMillis;
  final int timezoneOffsetMinutes;
  final double progressStart;
  final double progressEnd;
  final String? locatorStart;
  final String? locatorEnd;
  final int interactionCount;
  final DateTime updatedAtUtc;
}
