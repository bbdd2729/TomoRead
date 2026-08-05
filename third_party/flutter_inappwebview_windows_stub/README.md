# TomoRead InAppWebView Windows Stub

TomoRead uses `flutter_inappwebview` only for the Android EPUB virtual-origin
renderer. The upstream umbrella package automatically registers its Windows
implementation too, while the desktop reader uses `webview_flutter_windows`.
Both native implementations initialise WinRT dispatcher and graphics-capture
resources, which can make the desktop reader fail with `unsupported_platform`.

This Dart-only federated-plugin replacement keeps Android support intact while
preventing a second native WebView renderer from being registered on Windows.
