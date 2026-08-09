import 'dart:async';

import 'reader_drafts.dart';

class ReaderProgressCoordinator {
  ReaderProgressCoordinator({
    required this.persist,
    required this.report,
    this.debounce = const Duration(milliseconds: 600),
  });

  final Future<void> Function(PendingReaderProgress value) persist;
  final void Function(PendingReaderProgress value) report;
  final Duration debounce;

  PendingReaderProgress? _pending;
  PendingReaderProgress? _lastReported;
  Timer? _timer;
  Future<void> _writeTail = Future<void>.value();

  void capture(PendingReaderProgress value) {
    if (_shouldReport(value)) {
      _lastReported = value;
      report(value);
    }
    _pending = value;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (pending == null) return _writeTail;
    final write = _writeTail.then((_) => persist(pending));
    _writeTail = write.catchError((_) {});
    return write;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(flush());
  }

  bool _shouldReport(PendingReaderProgress value) {
    final previous = _lastReported;
    return previous == null ||
        previous.chapterIndex != value.chapterIndex ||
        (previous.progress - value.progress).abs() >= .005;
  }
}
