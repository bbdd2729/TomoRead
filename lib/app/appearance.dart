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
    ThemeSeed.blue => Colors.blue,
    ThemeSeed.teal => Colors.teal,
    ThemeSeed.green => Colors.green,
    ThemeSeed.orange => Colors.orange,
    ThemeSeed.purple => Colors.deepPurple,
  };
}

class AppAppearance {
  const AppAppearance({
    this.mode = ThemeMode.system,
    this.seed = ThemeSeed.blue,
    this.textScale = 1,
    this.uiFont = FontChoice.system,
    this.desktopNavigationWidth = 240,
    this.desktopNavigationCollapsed = false,
    this.readerTocWidth = 280,
    this.readerSidePanelWidth = 320,
  });

  final ThemeMode mode;
  final ThemeSeed seed;
  final double textScale;
  final FontChoice uiFont;
  final double desktopNavigationWidth;
  final bool desktopNavigationCollapsed;
  final double readerTocWidth;
  final double readerSidePanelWidth;

  AppAppearance copyWith({
    ThemeMode? mode,
    ThemeSeed? seed,
    double? textScale,
    FontChoice? uiFont,
    double? desktopNavigationWidth,
    bool? desktopNavigationCollapsed,
    double? readerTocWidth,
    double? readerSidePanelWidth,
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
    );
  }
}
