import 'package:flutter/material.dart';

import '../domain/models/font_choice.dart';

enum ThemeSeed { blue, teal, green, orange, brown, purple }

extension ThemeSeedX on ThemeSeed {
  String get label => switch (this) {
    ThemeSeed.blue => '蓝色',
    ThemeSeed.teal => '青色',
    ThemeSeed.green => '绿色',
    ThemeSeed.orange => '橙色',
    ThemeSeed.brown => '棕色',
    ThemeSeed.purple => '紫色',
  };

  Color get color => switch (this) {
    ThemeSeed.blue => const Color(0xFF216A83),
    ThemeSeed.teal => const Color(0xFF006C67),
    ThemeSeed.green => const Color(0xFF3F6B45),
    ThemeSeed.orange => const Color(0xFFA24A1E),
    ThemeSeed.brown => const Color(0xFF76512D),
    ThemeSeed.purple => const Color(0xFF76518A),
  };
}

/// The surface palette used by the whole application and reader chrome.
///
/// Brightness remains an independent preference so a person can keep the
/// paper palette in light mode while still using a comfortable dark variant
/// at night or when following the system setting.
enum AppThemeStyle { mist, white, paper }

extension AppThemeStyleX on AppThemeStyle {
  String get label => switch (this) {
    AppThemeStyle.mist => '雾绿',
    AppThemeStyle.white => '纯白',
    AppThemeStyle.paper => '纸张',
  };

  String get description => switch (this) {
    AppThemeStyle.mist => '柔和的绿灰底色，适合日常使用。',
    AppThemeStyle.white => '清晰的中性白色界面。',
    AppThemeStyle.paper => '暖米色纸张底色，减少长时间阅读的刺眼感。',
  };

  Color get previewColor => switch (this) {
    AppThemeStyle.mist => const Color(0xFFF2F6F4),
    AppThemeStyle.white => const Color(0xFFFFFFFF),
    AppThemeStyle.paper => const Color(0xFFF0E6D2),
  };

  Color get previewForeground => switch (this) {
    AppThemeStyle.mist => const Color(0xFF17211F),
    AppThemeStyle.white => const Color(0xFF1C1C1E),
    AppThemeStyle.paper => const Color(0xFF3D2B1F),
  };
}

class AppAppearance {
  const AppAppearance({
    this.mode = ThemeMode.system,
    this.seed = ThemeSeed.teal,
    this.themeStyle = AppThemeStyle.mist,
    this.textScale = 1,
    this.uiFont = FontChoice.system,
    this.desktopNavigationWidth = 240,
    this.desktopNavigationCollapsed = false,
    this.readerTocWidth = 280,
    this.readerSidePanelWidth = 320,
    this.readerTocVisible = true,
    this.readerSidePanelVisible = true,
  });

  final ThemeMode mode;
  final ThemeSeed seed;
  final AppThemeStyle themeStyle;
  final double textScale;
  final FontChoice uiFont;
  final double desktopNavigationWidth;
  final bool desktopNavigationCollapsed;
  final double readerTocWidth;
  final double readerSidePanelWidth;
  final bool readerTocVisible;
  final bool readerSidePanelVisible;

  AppAppearance copyWith({
    ThemeMode? mode,
    ThemeSeed? seed,
    AppThemeStyle? themeStyle,
    double? textScale,
    FontChoice? uiFont,
    double? desktopNavigationWidth,
    bool? desktopNavigationCollapsed,
    double? readerTocWidth,
    double? readerSidePanelWidth,
    bool? readerTocVisible,
    bool? readerSidePanelVisible,
  }) {
    return AppAppearance(
      mode: mode ?? this.mode,
      seed: seed ?? this.seed,
      themeStyle: themeStyle ?? this.themeStyle,
      textScale: textScale ?? this.textScale,
      uiFont: uiFont ?? this.uiFont,
      desktopNavigationWidth:
          desktopNavigationWidth ?? this.desktopNavigationWidth,
      desktopNavigationCollapsed:
          desktopNavigationCollapsed ?? this.desktopNavigationCollapsed,
      readerTocWidth: readerTocWidth ?? this.readerTocWidth,
      readerSidePanelWidth: readerSidePanelWidth ?? this.readerSidePanelWidth,
      readerTocVisible: readerTocVisible ?? this.readerTocVisible,
      readerSidePanelVisible:
          readerSidePanelVisible ?? this.readerSidePanelVisible,
    );
  }
}
