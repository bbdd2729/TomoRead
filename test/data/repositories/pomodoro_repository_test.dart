import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/pomodoro_repository.dart';
import 'package:tomoread/domain/models/pomodoro.dart';

void main() {
  late AppDatabase database;
  late PomodoroRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = PomodoroRepository(database);
  });

  tearDown(() => database.close());

  test('persists configuration, active state, and separate history', () async {
    const config = PomodoroConfig(
      focusMinutes: 40,
      shortBreakMinutes: 8,
      longBreakMinutes: 20,
      longBreakEvery: 3,
    );
    final started = DateTime.utc(2026, 8, 2, 12);
    final active = PomodoroTimerState(
      config: config,
      phase: PomodoroPhase.focus,
      remainingMillis: const Duration(minutes: 10).inMilliseconds,
      plannedMillis: const Duration(minutes: 40).inMilliseconds,
      isRunning: false,
      startedAtUtc: started,
      sessionId: 'session-a',
    );
    final idle = PomodoroTimerState(config: config, completedFocusCount: 1);

    await repository.saveConfig(config);
    await repository.saveState(active);
    await repository.finishSession(
      PomodoroSession(
        id: 'session-a',
        phase: PomodoroPhase.focus,
        plannedMillis: active.plannedMillis,
        elapsedMillis: const Duration(minutes: 30).inMilliseconds,
        status: PomodoroSessionStatus.cancelled,
        startedAtUtc: started,
        endedAtUtc: started.add(const Duration(minutes: 35)),
      ),
      idle,
    );

    final loadedConfig = await repository.loadConfig();
    final loadedState = await repository.loadState(loadedConfig);
    final history = await repository.listHistory();
    expect(loadedConfig.focusMinutes, 40);
    expect(loadedState.phase, PomodoroPhase.idle);
    expect(loadedState.completedFocusCount, 1);
    expect(history.single.elapsedMillis, const Duration(minutes: 30).inMilliseconds);
    expect(history.single.status, PomodoroSessionStatus.cancelled);
  });
}
