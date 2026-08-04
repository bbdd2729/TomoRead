import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/pomodoro_repository.dart';
import 'package:tomoread/data/services/pomodoro_timer_service.dart';
import 'package:tomoread/domain/models/pomodoro.dart';
import 'package:tomoread/features/reader/pomodoro_controller.dart';

void main() {
  late AppDatabase database;
  late PomodoroRepository repository;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.inMemory();
    repository = PomodoroRepository(database);
    container = ProviderContainer(
      overrides: [
        pomodoroRepositoryProvider.overrideWithValue(repository),
        pomodoroTimerServiceProvider.overrideWithValue(
          const PomodoroTimerService(),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });
  });

  test('build returns the idle default state', () async {
    final state = await container.read(pomodoroControllerProvider.future);
    expect(state.phase, PomodoroPhase.idle);
    expect(state.isRunning, isFalse);
  });

  test('startFocus begins a running focus phase and persists it', () async {
    final notifier = container.read(pomodoroControllerProvider.notifier);
    await container.read(pomodoroControllerProvider.future);

    await notifier.startFocus(bookId: 'book-a');

    final state = container.read(pomodoroControllerProvider).requireValue;
    expect(state.phase, PomodoroPhase.focus);
    expect(state.isRunning, isTrue);
    expect(state.bookId, 'book-a');
    expect(state.sessionId, isNotNull);
    final persisted = await repository.loadState(const PomodoroConfig());
    expect(persisted.phase, PomodoroPhase.focus);
  });

  test('startOrResume pauses and resumes without losing the session', () async {
    final notifier = container.read(pomodoroControllerProvider.notifier);
    await container.read(pomodoroControllerProvider.future);
    await notifier.startFocus();

    await notifier.pause();
    final paused = container.read(pomodoroControllerProvider).requireValue;
    expect(paused.isRunning, isFalse);
    expect(paused.sessionId, isNotNull);
    expect(paused.remainingMillis, greaterThan(0));

    await notifier.startOrResume();
    final resumed = container.read(pomodoroControllerProvider).requireValue;
    expect(resumed.isRunning, isTrue);
    expect(resumed.sessionId, paused.sessionId);
  });

  test('stop records a cancelled session and returns to idle', () async {
    final notifier = container.read(pomodoroControllerProvider.notifier);
    await container.read(pomodoroControllerProvider.future);
    await notifier.startFocus();

    await notifier.stop();

    final state = container.read(pomodoroControllerProvider).requireValue;
    expect(state.phase, PomodoroPhase.idle);
    expect(state.isRunning, isFalse);
    final history = await repository.listHistory();
    expect(history, hasLength(1));
    expect(history.single.status, PomodoroSessionStatus.cancelled);
  });

  test('saveConfig is ignored while a phase is running', () async {
    final notifier = container.read(pomodoroControllerProvider.notifier);
    await container.read(pomodoroControllerProvider.future);
    await notifier.startFocus();
    final current = container.read(pomodoroControllerProvider).requireValue;

    await notifier.saveConfig(const PomodoroConfig(focusMinutes: 10));

    final state = container.read(pomodoroControllerProvider).requireValue;
    expect(state.config.focusMinutes, current.config.focusMinutes);
  });
}
