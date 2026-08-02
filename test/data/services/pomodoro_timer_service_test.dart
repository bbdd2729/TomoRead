import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/pomodoro_timer_service.dart';
import 'package:tomoread/domain/models/pomodoro.dart';

void main() {
  const service = PomodoroTimerService();
  const config = PomodoroConfig();
  final startedAt = DateTime.utc(2026, 8, 2, 12);

  test('uses the absolute end timestamp across delayed ticks', () {
    final started = service.startFocus(
      config: config,
      nowUtc: startedAt,
      sessionId: 'focus-a',
    );

    final refreshed = service.refresh(
      started,
      startedAt.add(const Duration(minutes: 10, seconds: 3)),
    );

    expect(
      refreshed.remainingMillis,
      const Duration(minutes: 14, seconds: 57).inMilliseconds,
    );
  });

  test('pause freezes remaining time and resume derives a new end time', () {
    final started = service.startFocus(
      config: config,
      nowUtc: startedAt,
      sessionId: 'focus-b',
    );
    final paused = service.pause(
      started,
      startedAt.add(const Duration(minutes: 5)),
    );
    final stillPaused = service.refresh(
      paused,
      startedAt.add(const Duration(hours: 2)),
    );
    final resumed = service.resume(
      stillPaused,
      startedAt.add(const Duration(hours: 2)),
    );

    expect(stillPaused.remainingMillis, const Duration(minutes: 20).inMilliseconds);
    expect(
      resumed.endsAtUtc,
      startedAt.add(const Duration(hours: 2, minutes: 20)),
    );
  });

  test('selects a long break after the configured focus interval', () {
    final focus = service.startFocus(
      config: config,
      nowUtc: startedAt,
      sessionId: 'focus-c',
      completedFocusCount: 3,
    );

    final waiting = service.waitingBreak(focus);

    expect(waiting.phase, PomodoroPhase.longBreak);
    expect(waiting.completedFocusCount, 4);
    expect(waiting.isRunning, isFalse);
    expect(
      waiting.remainingMillis,
      const Duration(minutes: 15).inMilliseconds,
    );
  });
}
