import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../domain/models/tts.dart';

enum _UtteranceOutcome { completed, cancelled }

class PlatformTtsEngine implements TtsEngine {
  PlatformTtsEngine({FlutterTts? flutterTts})
    : _tts = flutterTts ?? FlutterTts() {
    _tts.setCompletionHandler(
      () => _completeUtterance(_UtteranceOutcome.completed),
    );
    _tts.setCancelHandler(() {
      if (!_paused) _completeUtterance(_UtteranceOutcome.cancelled);
    });
    _tts.setProgressHandler((text, start, end, word) {
      final controller = _eventController;
      if (controller == null || controller.isClosed) return;
      final absoluteStart = (_utteranceOffset + start)
          .clamp(0, _currentText.length)
          .toInt();
      final absoluteEnd = (_utteranceOffset + end)
          .clamp(absoluteStart, _currentText.length)
          .toInt();
      _lastWordStart = absoluteStart;
      controller.add(
        TtsPlaybackEvent(
          type: TtsPlaybackEventType.wordProgress,
          segmentIndex: _segmentIndex,
          wordStart: absoluteStart,
          wordEnd: absoluteEnd,
        ),
      );
    });
    _tts.setErrorHandler((message) {
      _utteranceError = message.toString();
      _completeUtterance(_UtteranceOutcome.cancelled);
    });
  }

  final FlutterTts _tts;
  StreamController<TtsPlaybackEvent>? _eventController;
  Completer<_UtteranceOutcome>? _utteranceCompleter;
  String _currentText = '';
  int _segmentIndex = 0;
  int _utteranceOffset = 0;
  int _lastWordStart = 0;
  int _session = 0;
  bool _paused = false;
  String? _utteranceError;

  bool get _platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  @override
  Future<TtsAvailability> checkAvailability() async {
    if (!_platformSupported) {
      return const TtsAvailability(
        available: false,
        reason: '当前平台没有可用的系统 TTS 后端。Linux 将在检测到受支持后端后启用。',
      );
    }
    try {
      final languages = await _tts.getLanguages;
      if (languages is Iterable && languages.isNotEmpty) {
        return const TtsAvailability.available();
      }
      return const TtsAvailability(
        available: false,
        reason: '系统没有安装可用的语音或语言包。',
      );
    } on MissingPluginException {
      return const TtsAvailability(
        available: false,
        reason: '当前构建未包含系统 TTS 后端。',
      );
    } on PlatformException catch (error) {
      return TtsAvailability(
        available: false,
        reason: error.message ?? '无法初始化系统 TTS。',
      );
    }
  }

  @override
  Future<List<TtsVoice>> listVoices() async {
    if (!_platformSupported) return const [];
    try {
      final source = await _tts.getVoices;
      if (source is! Iterable) return const [];
      final voices = <TtsVoice>[];
      final ids = <String>{};
      for (final value in source) {
        if (value is! Map) continue;
        final name = value['name']?.toString().trim() ?? '';
        final locale = value['locale']?.toString().trim() ?? '';
        if (name.isEmpty || locale.isEmpty) continue;
        final identifier = value['identifier']?.toString().trim();
        final id = identifier?.isNotEmpty == true
            ? identifier!
            : '$name|$locale';
        if (ids.add(id)) {
          voices.add(TtsVoice(id: id, name: name, locale: locale));
        }
      }
      voices.sort((a, b) {
        final locale = a.locale.compareTo(b.locale);
        return locale != 0 ? locale : a.name.compareTo(b.name);
      });
      return voices;
    } on Object {
      return const [];
    }
  }

  @override
  Stream<TtsPlaybackEvent> speak(TtsRequest request) {
    final controller = StreamController<TtsPlaybackEvent>();
    final session = ++_session;
    _completeUtterance(_UtteranceOutcome.cancelled);
    unawaited(_run(request, controller, session));
    return controller.stream;
  }

  Future<void> _run(
    TtsRequest request,
    StreamController<TtsPlaybackEvent> controller,
    int session,
  ) async {
    _eventController = controller;
    try {
      if (!_platformSupported) {
        throw StateError('当前平台没有可用的系统 TTS 后端。');
      }
      await _tts.stop();
      if (session != _session) return;
      await _tts.setLanguage(request.language);
      await _tts.setSpeechRate(request.rate);
      await _tts.setVolume(request.volume);
      final voice = request.voice;
      if (voice != null) {
        await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      }
      for (var index = request.startIndex;
          index < request.segments.length;
          index++) {
        if (session != _session) return;
        final segment = request.segments[index];
        _segmentIndex = index;
        _currentText = segment.text;
        _utteranceOffset = 0;
        _lastWordStart = 0;
        _utteranceError = null;
        _paused = false;
        final completer = Completer<_UtteranceOutcome>();
        _utteranceCompleter = completer;
        controller.add(
          TtsPlaybackEvent(
            type: TtsPlaybackEventType.segmentStarted,
            segmentIndex: index,
          ),
        );
        final result = await _tts.speak(segment.text, focus: true);
        if (result != 1) {
          throw StateError('系统拒绝了当前朗读请求。');
        }
        final outcome = await completer.future;
        if (session != _session) return;
        final utteranceError = _utteranceError;
        if (utteranceError != null) {
          throw StateError(utteranceError);
        }
        if (outcome == _UtteranceOutcome.cancelled) {
          controller.add(
            const TtsPlaybackEvent(type: TtsPlaybackEventType.cancelled),
          );
          return;
        }
        controller.add(
          TtsPlaybackEvent(
            type: TtsPlaybackEventType.segmentCompleted,
            segmentIndex: index,
          ),
        );
      }
      controller.add(
        const TtsPlaybackEvent(type: TtsPlaybackEventType.completed),
      );
    } on Object catch (error) {
      if (session == _session && !controller.isClosed) {
        controller.add(
          TtsPlaybackEvent(
            type: TtsPlaybackEventType.failed,
            error: error.toString(),
          ),
        );
      }
    } finally {
      if (identical(_eventController, controller)) {
        _eventController = null;
        _utteranceCompleter = null;
      }
      if (!controller.isClosed) await controller.close();
    }
  }

  @override
  Future<void> pause() async {
    if (!_platformSupported || _utteranceCompleter == null || _paused) return;
    _paused = true;
    await _tts.pause();
  }

  @override
  Future<void> resume() async {
    if (!_platformSupported || !_paused || _currentText.isEmpty) return;
    // Android resumes from the last range start while Windows resumes its
    // native paused utterance. Keeping the absolute start here makes progress
    // callbacks from either backend map back to the original segment.
    _utteranceOffset = _lastWordStart;
    _paused = false;
    final result = await _tts.speak(_currentText, focus: true);
    if (result != 1) {
      _utteranceError = '系统无法恢复当前朗读。';
      _completeUtterance(_UtteranceOutcome.cancelled);
    }
  }

  @override
  Future<void> stop() async {
    _session++;
    _paused = false;
    _completeUtterance(_UtteranceOutcome.cancelled);
    if (_platformSupported) {
      try {
        await _tts.stop();
      } on MissingPluginException {
        // Explicitly unavailable platforms degrade without affecting reader UI.
      }
    }
  }

  @override
  Future<void> setRate(double rate) async {
    if (_platformSupported) {
      await _tts.setSpeechRate(rate.clamp(0, 1).toDouble());
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_platformSupported) {
      await _tts.setVolume(volume.clamp(0, 1).toDouble());
    }
  }

  void _completeUtterance(_UtteranceOutcome outcome) {
    final completer = _utteranceCompleter;
    if (completer != null && !completer.isCompleted) completer.complete(outcome);
  }
}
