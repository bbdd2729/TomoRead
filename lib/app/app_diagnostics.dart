import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Emits concise, privacy-safe diagnostics for debug and profile builds.
///
/// Callers must not include book content, search queries, credentials, or full
/// local paths in [details].
abstract final class AppDiagnostics {
  static bool get isEnabled => kDebugMode || kProfileMode;

  static void info(
    String area,
    String event, {
    Map<String, Object?> details = const {},
  }) => _write(area, event, details: details);

  static void error(
    String area,
    String event, {
    Map<String, Object?> details = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => _write(
    area,
    event,
    details: details,
    error: error,
    stackTrace: stackTrace,
  );

  static void _write(
    String area,
    String event, {
    required Map<String, Object?> details,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabled) return;
    final suffix = details.entries
        .map((entry) => '${entry.key}=${_compact(entry.value)}')
        .join(' ');
    final message = suffix.isEmpty ? event : '$event $suffix';
    developer.log(
      message,
      name: 'TomoRead.$area',
      level: error == null ? 800 : 1000,
      error: error,
      stackTrace: stackTrace,
    );
    debugPrintSynchronously(
      'TomoRead/$area: $message${error == null ? '' : ' error=$error'}',
    );
  }

  static String _compact(Object? value) {
    final text = '$value'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 240 ? text : '${text.substring(0, 237)}...';
  }
}
