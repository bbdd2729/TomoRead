import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/pomodoro.dart';

final pomodoroControllerProvider =
    AsyncNotifierProvider<PomodoroController, PomodoroTimerState>(
      PomodoroController.new,
    );

class PomodoroController extends AsyncNotifier<PomodoroTimerState> {
  Timer? _ticker;

  @override
  Future<PomodoroTimerState> build() async {
    ref.onDispose(() => _ticker?.cancel());
    final repository = ref.watch(pomodoroRepositoryProvider);
    final config = await repository.loadConfig();
    var restored = await repository.loadState(config);
    restored = ref
        .read(pomodoroTimerServiceProvider)
        .refresh(restored, DateTime.now().toUtc());
    if (restored.isRunning && restored.remainingMillis == 0) {
      restored = await _finish(restored, PomodoroSessionStatus.completed);
    }
    _schedule(restored);
    return restored;
  }

  Future<void> startFocus({String? bookId}) async {
    final current = state.value;
    if (current == null || !current.isIdle) return;
    final now = DateTime.now().toUtc();
    final next = ref.read(pomodoroTimerServiceProvider).startFocus(
      config: current.config,
      nowUtc: now,
      sessionId: _sessionId(now),
      bookId: bookId,
      completedFocusCount: current.completedFocusCount,
    );
    await _publish(next);
  }

  Future<void> startOrResume({String? bookId}) async {
    final current = state.value;
    if (current == null) return;
    if (current.isIdle) {
      await startFocus(bookId: bookId);
      return;
    }
    if (current.isRunning) return;
    final now = DateTime.now().toUtc();
    final service = ref.read(pomodoroTimerServiceProvider);
    final next = current.sessionId == null
        ? service.startPhase(
            phase: current.phase,
            config: current.config,
            nowUtc: now,
            sessionId: _sessionId(now),
            completedFocusCount: current.completedFocusCount,
            bookId: current.bookId ?? bookId,
          )
        : service.resume(current, now);
    await _publish(next);
  }

  Future<void> pause() async {
    final current = state.value;
    if (current == null || !current.isRunning) return;
    final next = ref
        .read(pomodoroTimerServiceProvider)
        .pause(current, DateTime.now().toUtc());
    if (next.remainingMillis == 0) {
      final completed = await _finish(
        next,
        PomodoroSessionStatus.completed,
      );
      if (ref.mounted) state = AsyncData(completed);
      return;
    }
    await _publish(next);
  }

  Future<void> stop() async {
    final current = state.value;
    if (current == null || current.isIdle) return;
    final now = DateTime.now().toUtc();
    final refreshed = ref
        .read(pomodoroTimerServiceProvider)
        .refresh(current, now);
    final next = ref.read(pomodoroTimerServiceProvider).idle(refreshed);
    if (refreshed.sessionId == null || refreshed.startedAtUtc == null) {
      await _publish(next);
      return;
    }
    await _record(
      refreshed,
      next,
      PomodoroSessionStatus.cancelled,
      now,
    );
  }

  Future<void> skipBreak() async {
    final current = state.value;
    if (current == null || !current.isBreak) return;
    final now = DateTime.now().toUtc();
    final refreshed = ref
        .read(pomodoroTimerServiceProvider)
        .refresh(current, now);
    final next = ref.read(pomodoroTimerServiceProvider).idle(refreshed);
    if (refreshed.sessionId == null || refreshed.startedAtUtc == null) {
      await _publish(next);
      return;
    }
    await _record(
      refreshed,
      next,
      PomodoroSessionStatus.skipped,
      now,
    );
  }

  Future<void> saveConfig(PomodoroConfig config) async {
    final current = state.value;
    if (current == null || !current.isIdle) return;
    final next = PomodoroTimerState(
      config: config,
      completedFocusCount: current.completedFocusCount,
    );
    await ref.read(pomodoroRepositoryProvider).saveConfig(config);
    await _publish(next);
  }

  Future<void> _tick() async {
    final current = state.value;
    if (current == null || !current.isRunning) return;
    final now = DateTime.now().toUtc();
    final refreshed = ref
        .read(pomodoroTimerServiceProvider)
        .refresh(current, now);
    if (refreshed.remainingMillis == 0) {
      final next = await _finish(
        refreshed,
        PomodoroSessionStatus.completed,
      );
      if (ref.mounted) state = AsyncData(next);
      _schedule(next);
      return;
    }
    if (ref.mounted) state = AsyncData(refreshed);
  }

  Future<PomodoroTimerState> _finish(
    PomodoroTimerState current,
    PomodoroSessionStatus status,
  ) async {
    final service = ref.read(pomodoroTimerServiceProvider);
    final next = current.phase == PomodoroPhase.focus
        ? service.waitingBreak(current)
        : service.idle(current);
    if (current.sessionId == null || current.startedAtUtc == null) {
      await ref.read(pomodoroRepositoryProvider).saveState(next);
      return next;
    }
    await _record(current, next, status, DateTime.now().toUtc());
    return next;
  }

  Future<void> _record(
    PomodoroTimerState current,
    PomodoroTimerState next,
    PomodoroSessionStatus status,
    DateTime endedAtUtc,
  ) async {
    final session = PomodoroSession(
      id: current.sessionId!,
      bookId: current.bookId,
      phase: current.phase,
      plannedMillis: current.plannedMillis,
      elapsedMillis: status == PomodoroSessionStatus.completed
          ? current.plannedMillis
          : ref.read(pomodoroTimerServiceProvider).elapsedMillis(current),
      status: status,
      startedAtUtc: current.startedAtUtc!,
      endedAtUtc: endedAtUtc,
    );
    await ref.read(pomodoroRepositoryProvider).finishSession(session, next);
    if (ref.mounted) state = AsyncData(next);
    _schedule(next);
  }

  Future<void> _publish(PomodoroTimerState next) async {
    await ref.read(pomodoroRepositoryProvider).saveState(next);
    if (ref.mounted) state = AsyncData(next);
    _schedule(next);
  }

  void _schedule(PomodoroTimerState value) {
    _ticker?.cancel();
    if (!value.isRunning) return;
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_tick()),
    );
  }

  String _sessionId(DateTime nowUtc) =>
      'pomodoro-${nowUtc.microsecondsSinceEpoch}';
}
