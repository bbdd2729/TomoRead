import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/tts.dart';

class PlatformTtsWakeLock implements TtsWakeLock {
  const PlatformTtsWakeLock({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.tomoread/wake_lock');

  final MethodChannel _channel;

  @override
  Future<bool> setEnabled(bool enabled) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('setEnabled', {
            'enabled': enabled,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
