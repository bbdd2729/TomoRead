import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/tts_queue_service.dart';
import 'package:tomoread/domain/models/tts.dart';
import 'package:tomoread/features/reader/tts_controller.dart';

void main() {
  late _FakeTtsEngine engine;
  late _FakeTtsStore store;
  late _FakeWakeLock wakeLock;
  late TtsPlaybackController controller;

  setUp(() {
    engine = _FakeTtsEngine();
    store = _FakeTtsStore();
    wakeLock = _FakeWakeLock();
    controller = TtsPlaybackController(
      engine: engine,
      queue: _FakeQueueLoader(),
      store: store,
      wakeLock: wakeLock,
    );
  });

  tearDown(() => controller.dispose());

  test('plays, pauses, resumes and persists the active locator', () async {
    await controller.prepare(
      bookId: 'book-1',
      format: 'epub',
      chapterIndex: 0,
      currentLocator: 'ratio:0.000000',
    );
    await controller.updateSettings(
      controller.state.settings.copyWith(keepAwake: true),
    );
    await controller.playPause();
    engine.emit(
      const TtsPlaybackEvent(
        type: TtsPlaybackEventType.segmentStarted,
        segmentIndex: 0,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, TtsPlaybackStatus.playing);
    expect(store.cursor?.locator, 'ratio:0.000000');
    expect(wakeLock.enabled, isTrue);

    await controller.pause();
    expect(controller.state.status, TtsPlaybackStatus.paused);
    expect(engine.paused, isTrue);
    expect(wakeLock.enabled, isFalse);

    await controller.resume();
    expect(controller.state.status, TtsPlaybackStatus.playing);
    expect(engine.resumed, isTrue);
    expect(wakeLock.enabled, isTrue);
  });

  test('jumps between sentences and restarts active playback', () async {
    await controller.prepare(
      bookId: 'book-1',
      format: 'epub',
      chapterIndex: 0,
      currentLocator: null,
    );
    await controller.playPause();
    await controller.next();

    expect(controller.state.currentIndex, 1);
    expect(engine.requests.last.startIndex, 1);
    expect(store.cursor?.segmentId, 'segment-2');

    await controller.previous();
    expect(controller.state.currentIndex, 0);
    expect(engine.requests.last.startIndex, 0);
  });

  test('stops and releases wake lock after completion', () async {
    await controller.prepare(
      bookId: 'book-1',
      format: 'epub',
      chapterIndex: 0,
      currentLocator: null,
    );
    await controller.updateSettings(
      controller.state.settings.copyWith(keepAwake: true),
    );
    await controller.playPause();
    engine.emit(
      const TtsPlaybackEvent(type: TtsPlaybackEventType.completed),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, TtsPlaybackStatus.completed);
    expect(wakeLock.enabled, isFalse);
  });
}

class _FakeTtsEngine implements TtsEngine {
  final requests = <TtsRequest>[];
  final _events = StreamController<TtsPlaybackEvent>.broadcast();
  bool paused = false;
  bool resumed = false;

  void emit(TtsPlaybackEvent event) => _events.add(event);

  @override
  Future<TtsAvailability> checkAvailability() async =>
      const TtsAvailability.available();

  @override
  Future<List<TtsVoice>> listVoices() async => const [
    TtsVoice(id: 'voice-1', name: 'System', locale: 'zh-CN'),
  ];

  @override
  Stream<TtsPlaybackEvent> speak(TtsRequest request) {
    requests.add(request);
    return _events.stream;
  }

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => resumed = true;

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}
}

class _FakeQueueLoader implements TtsQueueLoader {
  @override
  Future<TtsQueueResult> load({
    required String bookId,
    required String format,
    required int chapterIndex,
    required String? currentLocator,
    required TtsCursor? savedCursor,
  }) async => TtsQueueResult(
    segments: const [
      TtsSegment(
        id: 'segment-1',
        text: '第一句。',
        href: 'chapter.xhtml',
        locatorStart: 'ratio:0.000000',
        locatorEnd: 'ratio:0.500000',
        chapterIndex: 0,
        chapterTitle: '第一章',
        rawStart: 0,
        rawEnd: 4,
      ),
      TtsSegment(
        id: 'segment-2',
        text: '第二句。',
        href: 'chapter.xhtml',
        locatorStart: 'ratio:0.500000',
        locatorEnd: 'ratio:1.000000',
        chapterIndex: 0,
        chapterTitle: '第一章',
        rawStart: 4,
        rawEnd: 8,
      ),
    ],
    startIndex: 0,
  );
}

class _FakeTtsStore implements TtsStateStore {
  TtsSettings settings = const TtsSettings();
  TtsCursor? cursor;

  @override
  Future<TtsCursor?> loadCursor(String bookId) async => cursor;

  @override
  Future<TtsSettings> loadSettings() async => settings;

  @override
  Future<void> saveCursor(TtsCursor value) async => cursor = value;

  @override
  Future<void> saveSettings(TtsSettings value) async => settings = value;
}

class _FakeWakeLock implements TtsWakeLock {
  bool enabled = false;

  @override
  Future<bool> setEnabled(bool value) async {
    enabled = value;
    return true;
  }
}
