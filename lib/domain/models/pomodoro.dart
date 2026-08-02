enum PomodoroPhase { idle, focus, shortBreak, longBreak }

enum PomodoroSessionStatus { completed, cancelled, skipped }

extension PomodoroPhaseLabel on PomodoroPhase {
  String get label => switch (this) {
    PomodoroPhase.idle => '未开始',
    PomodoroPhase.focus => '专注',
    PomodoroPhase.shortBreak => '短休息',
    PomodoroPhase.longBreak => '长休息',
  };

  bool get isBreak =>
      this == PomodoroPhase.shortBreak || this == PomodoroPhase.longBreak;
}

class PomodoroConfig {
  const PomodoroConfig({
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.longBreakEvery = 4,
  });

  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int longBreakEvery;

  int durationMillis(PomodoroPhase phase) => switch (phase) {
    PomodoroPhase.focus => focusMinutes * Duration.millisecondsPerMinute,
    PomodoroPhase.shortBreak =>
      shortBreakMinutes * Duration.millisecondsPerMinute,
    PomodoroPhase.longBreak =>
      longBreakMinutes * Duration.millisecondsPerMinute,
    PomodoroPhase.idle => 0,
  };

  Map<String, Object> toJson() => {
    'focusMinutes': focusMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'longBreakMinutes': longBreakMinutes,
    'longBreakEvery': longBreakEvery,
  };

  factory PomodoroConfig.fromJson(Map<String, Object?> value) =>
      PomodoroConfig(
        focusMinutes: _boundedInt(value['focusMinutes'], 25, 1, 180),
        shortBreakMinutes: _boundedInt(value['shortBreakMinutes'], 5, 1, 60),
        longBreakMinutes: _boundedInt(value['longBreakMinutes'], 15, 1, 120),
        longBreakEvery: _boundedInt(value['longBreakEvery'], 4, 1, 12),
      );
}

class PomodoroTimerState {
  const PomodoroTimerState({
    required this.config,
    this.phase = PomodoroPhase.idle,
    this.remainingMillis = 0,
    this.plannedMillis = 0,
    this.completedFocusCount = 0,
    this.isRunning = false,
    this.endsAtUtc,
    this.startedAtUtc,
    this.bookId,
    this.sessionId,
  });

  final PomodoroConfig config;
  final PomodoroPhase phase;
  final int remainingMillis;
  final int plannedMillis;
  final int completedFocusCount;
  final bool isRunning;
  final DateTime? endsAtUtc;
  final DateTime? startedAtUtc;
  final String? bookId;
  final String? sessionId;

  bool get isIdle => phase == PomodoroPhase.idle;
  bool get isBreak => phase.isBreak;

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'remainingMillis': remainingMillis,
    'plannedMillis': plannedMillis,
    'completedFocusCount': completedFocusCount,
    'isRunning': isRunning,
    'endsAtUtc': endsAtUtc?.toIso8601String(),
    'startedAtUtc': startedAtUtc?.toIso8601String(),
    'bookId': bookId,
    'sessionId': sessionId,
  };

  factory PomodoroTimerState.fromJson(
    Map<String, Object?> value,
    PomodoroConfig config,
  ) => PomodoroTimerState(
    config: config,
    phase: PomodoroPhase.values.firstWhere(
      (item) => item.name == value['phase'],
      orElse: () => PomodoroPhase.idle,
    ),
    remainingMillis: _boundedInt(
      value['remainingMillis'],
      0,
      0,
      12 * Duration.millisecondsPerHour,
    ),
    plannedMillis: _boundedInt(
      value['plannedMillis'],
      0,
      0,
      12 * Duration.millisecondsPerHour,
    ),
    completedFocusCount: _boundedInt(
      value['completedFocusCount'],
      0,
      0,
      1000000,
    ),
    isRunning: value['isRunning'] == true,
    endsAtUtc: DateTime.tryParse(value['endsAtUtc'] as String? ?? '')?.toUtc(),
    startedAtUtc: DateTime.tryParse(
      value['startedAtUtc'] as String? ?? '',
    )?.toUtc(),
    bookId: value['bookId'] as String?,
    sessionId: value['sessionId'] as String?,
  );
}

class PomodoroSession {
  const PomodoroSession({
    required this.id,
    required this.phase,
    required this.plannedMillis,
    required this.elapsedMillis,
    required this.status,
    required this.startedAtUtc,
    required this.endedAtUtc,
    this.bookId,
  });

  final String id;
  final String? bookId;
  final PomodoroPhase phase;
  final int plannedMillis;
  final int elapsedMillis;
  final PomodoroSessionStatus status;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
}

int _boundedInt(Object? value, int fallback, int minimum, int maximum) {
  final number = value is num ? value.toInt() : fallback;
  return number.clamp(minimum, maximum).toInt();
}
