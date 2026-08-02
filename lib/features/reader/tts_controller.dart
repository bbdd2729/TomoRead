import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/services/tts_queue_service.dart';
import '../../domain/models/tts.dart';

class TtsPlaybackController extends ChangeNotifier {
  TtsPlaybackController({
    required TtsEngine engine,
    required TtsQueueLoader queue,
    required TtsStateStore store,
    required TtsWakeLock wakeLock,
  }) : _engine = engine,
       _queue = queue,
       _store = store,
       _wakeLock = wakeLock;

  final TtsEngine _engine;
  final TtsQueueLoader _queue;
  final TtsStateStore _store;
  final TtsWakeLock _wakeLock;

  TtsPlaybackState _state = const TtsPlaybackState();
  TtsPlaybackState get state => _state;

  StreamSubscription<TtsPlaybackEvent>? _subscription;
  String? _bookId;
  int _generation = 0;
  bool _disposed = false;

  Future<void> prepare({
    required String bookId,
    required String format,
    required int chapterIndex,
    required String? currentLocator,
  }) async {
    final generation = ++_generation;
    await _stopPlayback(setIdle: false);
    _bookId = bookId;
    _setState(
      _state.copyWith(
        status: TtsPlaybackStatus.loading,
        segments: const [],
        currentIndex: 0,
        clearError: true,
        clearWordRange: true,
      ),
    );
    try {
      final settings = await _store.loadSettings();
      final availability = await _engine.checkAvailability();
      final voices = availability.available
          ? await _engine.listVoices()
          : const <TtsVoice>[];
      final cursor = await _store.loadCursor(bookId);
      final result = await _queue.load(
        bookId: bookId,
        format: format,
        chapterIndex: chapterIndex,
        currentLocator: currentLocator,
        savedCursor: cursor,
      );
      if (_disposed || generation != _generation) return;
      if (availability.available) {
        await _engine.setRate(settings.rate);
        await _engine.setVolume(settings.volume);
      }
      _setState(
        TtsPlaybackState(
          status: TtsPlaybackStatus.idle,
          availability: availability,
          settings: settings,
          voices: voices,
          segments: result.segments,
          currentIndex: result.startIndex,
          error: availability.reason,
        ),
      );
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _setState(
        _state.copyWith(
          status: TtsPlaybackStatus.failed,
          availability: TtsAvailability(
            available: false,
            reason: error.toString(),
          ),
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> playPause() async {
    if (!_state.canPlay) return;
    switch (_state.status) {
      case TtsPlaybackStatus.playing:
        await pause();
      case TtsPlaybackStatus.paused:
        await resume();
      case TtsPlaybackStatus.idle ||
            TtsPlaybackStatus.completed ||
            TtsPlaybackStatus.failed:
        await _start(_state.currentIndex);
      case TtsPlaybackStatus.loading:
        return;
    }
  }

  Future<void> pause() async {
    if (_state.status != TtsPlaybackStatus.playing) return;
    await _engine.pause();
    await _setWakeLock(false);
    _setState(_state.copyWith(status: TtsPlaybackStatus.paused));
  }

  Future<void> resume() async {
    if (_state.status != TtsPlaybackStatus.paused) return;
    await _setWakeLock(_state.settings.keepAwake);
    await _engine.resume();
    _setState(_state.copyWith(status: TtsPlaybackStatus.playing));
  }

  Future<void> stop() => _stopPlayback(setIdle: true);

  Future<void> previous() => seekTo(_state.currentIndex - 1);
  Future<void> next() => seekTo(_state.currentIndex + 1);

  Future<void> seekTo(int index) async {
    if (_state.segments.isEmpty) return;
    final target = index.clamp(0, _state.segments.length - 1).toInt();
    final wasActive = _state.status == TtsPlaybackStatus.playing ||
        _state.status == TtsPlaybackStatus.paused;
    await _stopPlayback(setIdle: true);
    _setState(
      _state.copyWith(
        currentIndex: target,
        status: TtsPlaybackStatus.idle,
        clearWordRange: true,
        clearError: true,
      ),
    );
    await _persistCursor(target);
    if (wasActive) await _start(target);
  }

  Future<void> updateSettings(TtsSettings settings) async {
    final normalized = settings.copyWith(
      rate: settings.rate.clamp(.1, 1).toDouble(),
      volume: settings.volume.clamp(0, 1).toDouble(),
    );
    if (_state.availability.available) {
      await _engine.setRate(normalized.rate);
      await _engine.setVolume(normalized.volume);
    }
    await _store.saveSettings(normalized);
    if (_state.status == TtsPlaybackStatus.playing) {
      await _setWakeLock(normalized.keepAwake);
    }
    _setState(_state.copyWith(settings: normalized));
  }

  Future<void> _start(int startIndex) async {
    final bookId = _bookId;
    if (bookId == null || !_state.canPlay) return;
    await _subscription?.cancel();
    await _setWakeLock(_state.settings.keepAwake);
    _setState(
      _state.copyWith(
        status: TtsPlaybackStatus.playing,
        currentIndex: startIndex,
        clearError: true,
        clearWordRange: true,
      ),
    );
    final stream = _engine.speak(
      TtsRequest(
        bookId: bookId,
        segments: _state.segments,
        startIndex: startIndex,
        language: _state.settings.language,
        voice: _state.selectedVoice,
        rate: _state.settings.rate,
        volume: _state.settings.volume,
      ),
    );
    _subscription = stream.listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) =>
          _fail(error.toString()),
    );
  }

  void _handleEvent(TtsPlaybackEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case TtsPlaybackEventType.segmentStarted:
        final index = event.segmentIndex ?? _state.currentIndex;
        _setState(
          _state.copyWith(
            status: TtsPlaybackStatus.playing,
            currentIndex: index,
            clearWordRange: true,
          ),
        );
        unawaited(_persistCursor(index));
      case TtsPlaybackEventType.wordProgress:
        _setState(
          _state.copyWith(
            wordStart: event.wordStart,
            wordEnd: event.wordEnd,
          ),
        );
      case TtsPlaybackEventType.segmentCompleted:
        final index = event.segmentIndex;
        if (index != null && index + 1 < _state.segments.length) {
          _setState(
            _state.copyWith(
              currentIndex: index + 1,
              clearWordRange: true,
            ),
          );
        }
      case TtsPlaybackEventType.completed:
        unawaited(_setWakeLock(false));
        _setState(
          _state.copyWith(
            status: TtsPlaybackStatus.completed,
            clearWordRange: true,
          ),
        );
      case TtsPlaybackEventType.cancelled:
        unawaited(_setWakeLock(false));
        _setState(
          _state.copyWith(
            status: TtsPlaybackStatus.idle,
            clearWordRange: true,
          ),
        );
      case TtsPlaybackEventType.failed:
        _fail(event.error ?? '系统朗读失败。');
    }
  }

  Future<void> _stopPlayback({required bool setIdle}) async {
    await _engine.stop();
    await _subscription?.cancel();
    _subscription = null;
    await _setWakeLock(false);
    if (setIdle && !_disposed) {
      _setState(
        _state.copyWith(
          status: TtsPlaybackStatus.idle,
          clearWordRange: true,
        ),
      );
    }
  }

  Future<void> _persistCursor(int index) async {
    final bookId = _bookId;
    if (bookId == null || index < 0 || index >= _state.segments.length) return;
    final segment = _state.segments[index];
    await _store.saveCursor(
      TtsCursor(
        bookId: bookId,
        segmentId: segment.id,
        locator: segment.locatorStart,
        chapterIndex: segment.chapterIndex,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _setWakeLock(bool enabled) async {
    try {
      await _wakeLock.setEnabled(enabled);
    } on Object {
      // Wake lock is optional; playback remains available without it.
    }
  }

  void _fail(String message) {
    unawaited(_setWakeLock(false));
    _setState(
      _state.copyWith(
        status: TtsPlaybackStatus.failed,
        error: message,
        clearWordRange: true,
      ),
    );
  }

  void _setState(TtsPlaybackState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_engine.stop());
    unawaited(_subscription?.cancel());
    unawaited(_setWakeLock(false));
    super.dispose();
  }
}
