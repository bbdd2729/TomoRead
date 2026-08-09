import 'dart:async';

import 'package:flutter/foundation.dart';

enum VolumeKeyEvent { up, down }

abstract interface class VolumeKeyControl {
  Stream<VolumeKeyEvent> get events;

  Future<void> enable();

  Future<void> disable();
}

class VolumeKeyPageTurner {
  VolumeKeyPageTurner({required this.control});

  final VolumeKeyControl control;
  StreamSubscription<VolumeKeyEvent>? _subscription;
  VoidCallback? _onPrevious;
  VoidCallback? _onNext;
  Future<void> _pendingOperation = Future.value();

  Future<void> configure({
    required bool enabled,
    required VoidCallback onPrevious,
    required VoidCallback onNext,
  }) async {
    _onPrevious = onPrevious;
    _onNext = onNext;
    return _enqueue(() async {
      if (!enabled) {
        await _subscription?.cancel();
        _subscription = null;
        await control.disable();
        return;
      }
      _subscription ??= control.events.listen(_handleEvent);
      await control.enable();
    });
  }

  Future<void> dispose() => _enqueue(() async {
    await _subscription?.cancel();
    _subscription = null;
    await control.disable();
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final scheduled = _pendingOperation.then((_) => operation());
    _pendingOperation = scheduled.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return scheduled;
  }

  void _handleEvent(VolumeKeyEvent event) {
    switch (event) {
      case VolumeKeyEvent.up:
        _onPrevious?.call();
      case VolumeKeyEvent.down:
        _onNext?.call();
    }
  }
}
