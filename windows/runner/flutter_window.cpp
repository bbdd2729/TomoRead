#include "flutter_window.h"

#include <shellapi.h>

#include <optional>
#include <set>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

int CALLBACK CollectFontFamily(
    const LOGFONTW* logical_font,
    const TEXTMETRICW*,
    DWORD,
    LPARAM data) {
  auto* families = reinterpret_cast<std::set<std::wstring>*>(data);
  if (logical_font->lfFaceName[0] != L'@') {
    families->insert(logical_font->lfFaceName);
  }
  return 1;
}

flutter::EncodableList ListInstalledFontFamilies() {
  LOGFONTW query = {};
  query.lfCharSet = DEFAULT_CHARSET;
  std::set<std::wstring> families;
  HDC device_context = GetDC(nullptr);
  EnumFontFamiliesExW(
      device_context,
      &query,
      reinterpret_cast<FONTENUMPROCW>(CollectFontFamily),
      reinterpret_cast<LPARAM>(&families),
      0);
  ReleaseDC(nullptr, device_context);
  flutter::EncodableList result;
  for (const auto& family : families) {
    result.emplace_back(Utf8FromUtf16(family.c_str()));
  }
  return result;
}

flutter::EncodableList DecodeDroppedFiles(HDROP drop) {
  flutter::EncodableList result;
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT index = 0; index < count; index++) {
    const UINT length = DragQueryFileW(drop, index, nullptr, 0);
    if (length == 0) {
      continue;
    }
    std::vector<wchar_t> value(length + 1, L'\0');
    if (DragQueryFileW(drop, index, value.data(), length + 1) == 0) {
      continue;
    }
    flutter::EncodableMap item;
    item[flutter::EncodableValue("kind")] =
        flutter::EncodableValue("desktopDrop");
    item[flutter::EncodableValue("path")] =
        flutter::EncodableValue(Utf8FromUtf16(value.data()));
    result.emplace_back(item);
  }
  return result;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DragAcceptFiles(GetHandle(), TRUE);
  font_catalog_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "dev.tomoread/font_catalog",
      &flutter::StandardMethodCodec::GetInstance());
  font_catalog_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "listFonts") {
          result->Success(flutter::EncodableValue(ListInstalledFontFamilies()));
        } else {
          result->NotImplemented();
        }
      });
  import_inbox_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "dev.tomoread/import_inbox",
      &flutter::StandardMethodCodec::GetInstance());
  import_inbox_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getInitialSources") {
          result->Success(flutter::EncodableValue(flutter::EncodableList()));
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    DragAcceptFiles(GetHandle(), FALSE);
    import_inbox_channel_.reset();
    font_catalog_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_DROPFILES) {
    const auto drop = reinterpret_cast<HDROP>(wparam);
    const auto files = DecodeDroppedFiles(drop);
    DragFinish(drop);
    if (import_inbox_channel_ && !files.empty()) {
      import_inbox_channel_->InvokeMethod(
          "incomingSources",
          std::make_unique<flutter::EncodableValue>(files));
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
