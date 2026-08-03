import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import 'app/app_diagnostics.dart';
import 'app/tomo_read_app.dart';

export 'app/tomo_read_app.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    AppDiagnostics.error(
      'flutter',
      'framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppDiagnostics.error(
      'dart',
      'unhandled asynchronous error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  AppDiagnostics.info(
    'app',
    'startup',
    details: {'importArguments': arguments.length},
  );
  runApp(TomoReadApp(initialImportArguments: arguments));
}
