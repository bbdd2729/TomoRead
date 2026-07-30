import 'package:flutter/material.dart';

import '../domain/models/font_choice.dart';

enum ThemeSeed { blue, teal, green, orange, purple }

extension ThemeSeedX on ThemeSeed {
  String get label => switch (this) {
    ThemeSeed.blue => '蓝色',
    ThemeSeed.teal => '青色',
    ThemeSeed.green => '绿色',
    ThemeSeed.orange => '橙色',
    ThemeSeed.purple => '紫色',
  };

  Color get color => switch (this) {
    ThemeSeed.blue => const Color(0xFF216A83),
    ThemeSeed.teal => const Color(0xFF006C67),
    ThemeSeed.green => const Color(0xFF3F6B45),
    ThemeSeed.orange => const Color(0xFFA24A1E),
    ThemeSeed.purple => const Color(0xFF76518A),
  };
}

class AppAppearance {
  const AppAppearance({
    this.mode = ThemeMode.system,
    this.seed = ThemeSeed.teal,
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
