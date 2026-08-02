import 'dart:async';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../domain/models/book_import.dart';

class PlatformImportEvent {
  const PlatformImportEvent({this.sources = const [], this.errors = const []});

  final List<ImportSource> sources;
  final List<String> errors;

  bool get isEmpty => sources.isEmpty && errors.isEmpty;
}

class PlatformImportInboxService {
  PlatformImportInboxService({
    List<String> initialArguments = const [],
    MethodChannel? channel,
  }) : _initialArguments = List.unmodifiable(initialArguments),
       _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.tomoread/import_inbox';
  static const _supportedExtensions = {
    '.epub',
    '.pdf',
    '.txt',
    '.md',
    '.markdown',
  };

  final List<String> _initialArguments;
  final MethodChannel _channel;
  final StreamController<PlatformImportEvent> _events =
      StreamController.broadcast();
  bool _initialized = false;

  Stream<PlatformImportEvent> get events => _events.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);

    final commandLine = _commandLineEvent();
    if (!commandLine.isEmpty) _events.add(commandLine);
    try {
      final initial = await _channel.invokeMethod<Object?>('getInitialSources');
      final event = _decodeNativePayload(initial);
      if (!event.isEmpty) _events.add(event);
    } on MissingPluginException {
      // Unsupported platforms still accept Dart entrypoint arguments.
    } on PlatformException catch (error) {
      _events.add(
        PlatformImportEvent(errors: ['无法读取系统传入的文件：${error.message ?? error.code}']),
      );
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'incomingSources') return;
    final event = _decodeNativePayload(call.arguments);
    if (!event.isEmpty) _events.add(event);
  }

  PlatformImportEvent _commandLineEvent() {
    final sources = <ImportSource>[];
    for (final argument in _initialArguments) {
      final value = argument.trim();
      if (value.isEmpty || value.startsWith('-')) continue;
      final extension = path.extension(value).toLowerCase();
      if (extension.isNotEmpty && !_supportedExtensions.contains(extension)) {
        continue;
      }
      sources.add(
        ImportSource(
          kind: ImportSourceKind.commandLine,
          location: value,
          displayName: path.basename(value),
        ),
      );
    }
    return PlatformImportEvent(sources: List.unmodifiable(sources));
  }

  PlatformImportEvent _decodeNativePayload(Object? payload) {
    if (payload is! List) return const PlatformImportEvent();
    final sources = <ImportSource>[];
    final errors = <String>[];
    for (final value in payload) {
      if (value is! Map) continue;
      final error = value['error'];
      if (error is String && error.trim().isNotEmpty) {
        errors.add(error.trim());
        continue;
      }
      final location = value['path'];
      final kind = _parseKind(value['kind']);
      if (location is! String || location.trim().isEmpty || kind == null) {
        errors.add('系统传入了无效的导入项目。');
        continue;
      }
      final mimeType = value['mimeType'];
      final displayName = value['displayName'];
      sources.add(
        ImportSource(
          kind: kind,
          location: location,
          displayName: displayName is String && displayName.isNotEmpty
              ? displayName
              : path.basename(location),
          mimeType: mimeType is String && mimeType.isNotEmpty ? mimeType : null,
          temporary: value['temporary'] == true,
        ),
      );
    }
    return PlatformImportEvent(
      sources: List.unmodifiable(sources),
      errors: List.unmodifiable(errors),
    );
  }

  ImportSourceKind? _parseKind(Object? value) => switch (value) {
    'desktopDrop' => ImportSourceKind.desktopDrop,
    'androidView' => ImportSourceKind.androidView,
    'androidShare' => ImportSourceKind.androidShare,
    _ => null,
  };

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}
