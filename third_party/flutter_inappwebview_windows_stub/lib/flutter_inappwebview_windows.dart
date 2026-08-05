library flutter_inappwebview_windows;

/// Prevents the Android-only InAppWebView dependency from registering its
/// native Windows renderer. TomoRead uses `webview_flutter_windows` for the
/// Windows EPUB reader; loading both renderers creates competing WinRT
/// DispatcherQueue and Graphics Capture contexts.
class TomoReadInAppWebViewWindowsStub {
  static void registerWith() {}
}
