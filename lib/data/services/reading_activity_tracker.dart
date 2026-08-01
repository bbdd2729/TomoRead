import 'dart:async';

import '../../domain/models/reading_activity.dart';
import '../repositories/reading_session_repository.dart';

typedef Clock = DateTime Function();

class ReadingActivityTracker {
  ReadingActivityTracker({
    required this.repository,
    required this.onChanged,
    Clock? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()) {
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _enqueue(_checkpoint),
    );
    _enqueue(() => repository.recoverOpenSessions(_clock()));
  }

  static const idleThreshold = Duration(seconds: 90);
  static const groupThreshold = Duration(minutes: 5);

  final ReadingSessionRepository repository;
  final void Function() onChanged;
  final Clock _clock;
  late final Timer _timer;
  Future<void> _writeQueue = Future.value();

  ReaderIdentity? _identity;
  ReaderPosition? _position;
  DateTime? _activeStartedAt;
  DateTime? _lastInteractionAt;
  DateTime? _lastEndedAt;
  String? _activityId;
  String? _sessionGroupId;
  var _interactionCount = 0;
  var _visible = true;
  var _foreground = true;
  var _disposed = false;

  void open(ReaderIdentity identity, ReaderPosition initialPosition) {
    _enqueue(() async {
      await _finishActive(_clock());
      _identity = identity;
      _position = initialPosition;
      _sessionGroupId = null;
      _lastEndedAt = null;
    });
  }

  void recordInteraction(
    ReaderPosition position,
    ReadingInteraction interaction,
  ) {
    _enqueue(() async {
      if (_identity == null) return;
      final now = _clock();
      _position = position;
      _lastInteractionAt = now;
      _interactionCount += 1;
      if (!_visible || !_foreground) return;
      if (_activityId == null) await _startActive(now, position);
    });
  }

  void setVisibility(bool visible) {
    _enqueue(() async {
      if (_visible == visible) return;
      _visible = visible;
      if (!visible) await _finishActive(_clock());
    });
  }

  void setForeground(bool foreground) {
    _enqueue(() async {
      if (_foreground == foreground) return;
      _foreground = foreground;
      if (!foreground) await _finishActive(_clock());
    });
  }

  Future<void> close() {
    _enqueue(() async {
      await _finishActive(_clock());
      _identity = null;
      _position = null;
      _sessionGroupId = null;
      _lastEndedAt = null;
    });
    return _writeQueue;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _timer.cancel();
    await close();
    _disposed = true;
  }

  Future<void> _startActive(DateTime now, ReaderPosition position) async {
    final identity = _identity;
    if (identity == null) return;
    if (_sessionGroupId == null ||
        (_lastEndedAt != null &&
            now.difference(_lastEndedAt!) > groupThreshold)) {
      _sessionGroupId = 'reading-group-${now.microsecondsSinceEpoch}';
    }
    _activityId = 'reading-${now.microsecondsSinceEpoch}-${identity.bookId}';
    _activeStartedAt = now;
    _lastInteractionAt = now;
    _interactionCount = 1;
    await repository.start(
      id: _activityId!,
      sessionGroupId: _sessionGroupId!,
      identity: identity,
      position: position,
      nowUtc: now,
      timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    );
  }

  Future<void> _checkpoint() async {
    final activityId = _activityId;
    final startedAt = _activeStartedAt;
    final lastInteraction = _lastInteractionAt;
    final position = _position;
    if (activityId == null ||
        startedAt == null ||
        lastInteraction == null ||
        position == null) {
      return;
    }
    final now = _clock();
    final idleEnd = lastInteraction.add(idleThreshold);
    if (!now.isBefore(idleEnd)) {
      await _finishActive(idleEnd);
      return;
    }
    await repository.checkpoint(
      id: activityId,
      nowUtc: now,
      activeMillis: now.difference(startedAt).inMilliseconds,
      position: position,
      interactionCount: _interactionCount,
    );
    onChanged();
  }

  Future<void> _finishActive(DateTime requestedEnd) async {
    final activityId = _activityId;
    final startedAt = _activeStartedAt;
    final lastInteraction = _lastInteractionAt;
    final position = _position;
    if (activityId == null ||
        startedAt == null ||
        lastInteraction == null ||
        position == null) {
      return;
    }
    final idleEnd = lastInteraction.add(idleThreshold);
    final end = requestedEnd.isBefore(idleEnd) ? requestedEnd : idleEnd;
    final safeEnd = end.isBefore(startedAt) ? startedAt : end;
    await repository.checkpoint(
      id: activityId,
      nowUtc: requestedEnd,
      activeMillis: safeEnd.difference(startedAt).inMilliseconds,
      position: position,
      interactionCount: _interactionCount,
      endedAtUtc: safeEnd,
    );
    _activityId = null;
    _activeStartedAt = null;
    _lastEndedAt = safeEnd;
    _interactionCount = 0;
    onChanged();
  }

  void _enqueue(Future<void> Function() operation) {
    if (_disposed) return;
    _writeQueue = _writeQueue.then((_) => operation()).catchError((_) {});
  }
}
