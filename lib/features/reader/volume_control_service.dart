import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'volume_key_page_turner.dart';

class VolumeControlService implements VolumeKeyControl {
  static const _methodChannel = MethodChannel('dev.tomoread/volume_control');
  static const _eventChannel = EventChannel('dev.tomoread/volume_events');

  bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<VolumeKeyEvent> get events {
    if (!_isSupported) return const Stream.empty();
    return _eventChannel
        .receiveBroadcastStream()
        .map(parseAndroidVolumeKeyEvent)
        .where((event) => event != null)
        .cast<VolumeKeyEvent>();
  }

  @override
  Future<void> disable() => _invoke('disableInterception');

  @override
  Future<void> enable() => _invoke('enableInterception');

  Future<void> _invoke(String method) async {
    if (!_isSupported) return;
    try {
      await _methodChannel.invokeMethod<void>(method);
    } on MissingPluginException catch (error) {
      debugPrint('Volume-key interception $method is unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('Volume-key interception $method failed: ${error.message}');
    }
  }
}

VolumeKeyEvent? parseAndroidVolumeKeyEvent(Object? event) => switch (event) {
  'up' => VolumeKeyEvent.up,
  'down' => VolumeKeyEvent.down,
  _ => null,
};
