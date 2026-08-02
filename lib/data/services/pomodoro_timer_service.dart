import '../../domain/models/pomodoro.dart';

class PomodoroTimerService {
  const PomodoroTimerService();

  PomodoroTimerState refresh(PomodoroTimerState state, DateTime nowUtc) {
    if (!state.isRunning || state.endsAtUtc == null) return state;
    final remaining = state.endsAtUtc!
        .difference(nowUtc.toUtc())
        .inMilliseconds
        .clamp(0, state.plannedMillis)
        .toInt();
    return _copy(state, remainingMillis: remaining);
  }

  PomodoroTimerState startFocus({
    required PomodoroConfig config,
    required DateTime nowUtc,
    required String sessionId,
    String? bookId,
    int completedFocusCount = 0,
  }) => startPhase(
    phase: PomodoroPhase.focus,
    config: config,
    nowUtc: nowUtc,
    sessionId: sessionId,
    bookId: bookId,
    completedFocusCount: completedFocusCount,
  );

  PomodoroTimerState startPhase({
    required PomodoroPhase phase,
    required PomodoroConfig config,
    required DateTime nowUtc,
    required String sessionId,
    required int completedFocusCount,
    String? bookId,
  }) {
    final planned = config.durationMillis(phase);
    return PomodoroTimerState(
      config: config,
      phase: phase,
      remainingMillis: planned,
      plannedMillis: planned,
      completedFocusCount: completedFocusCount,
      isRunning: true,
      endsAtUtc: nowUtc.toUtc().add(Duration(milliseconds: planned)),
      startedAtUtc: nowUtc.toUtc(),
      bookId: bookId,
      sessionId: sessionId,
    );
  }

  PomodoroTimerState pause(PomodoroTimerState state, DateTime nowUtc) {
    final refreshed = refresh(state, nowUtc);
    return _copy(refreshed, isRunning: false, clearEndsAt: true);
  }

  PomodoroTimerState resume(PomodoroTimerState state, DateTime nowUtc) => _copy(
    state,
    isRunning: true,
    endsAtUtc: nowUtc.toUtc().add(
      Duration(milliseconds: state.remainingMillis),
    ),
  );

  PomodoroTimerState waitingBreak(PomodoroTimerState completedFocus) {
    final completed = completedFocus.completedFocusCount + 1;
    final phase = completed % completedFocus.config.longBreakEvery == 0
        ? PomodoroPhase.longBreak
        : PomodoroPhase.shortBreak;
    final duration = completedFocus.config.durationMillis(phase);
    return PomodoroTimerState(
      config: completedFocus.config,
      phase: phase,
      remainingMillis: duration,
      plannedMillis: duration,
      completedFocusCount: completed,
      bookId: completedFocus.bookId,
    );
  }

  PomodoroTimerState idle(PomodoroTimerState state) => PomodoroTimerState(
    config: state.config,
    completedFocusCount: state.completedFocusCount,
  );

  int elapsedMillis(PomodoroTimerState state) =>
      (state.plannedMillis - state.remainingMillis).clamp(
        0,
        state.plannedMillis,
      ).toInt();

  PomodoroTimerState _copy(
    PomodoroTimerState state, {
    int? remainingMillis,
    bool? isRunning,
    DateTime? endsAtUtc,
    bool clearEndsAt = false,
  }) => PomodoroTimerState(
    config: state.config,
    phase: state.phase,
    remainingMillis: remainingMillis ?? state.remainingMillis,
    plannedMillis: state.plannedMillis,
    completedFocusCount: state.completedFocusCount,
    isRunning: isRunning ?? state.isRunning,
    endsAtUtc: clearEndsAt ? null : endsAtUtc ?? state.endsAtUtc,
    startedAtUtc: state.startedAtUtc,
    bookId: state.bookId,
    sessionId: state.sessionId,
  );
}
