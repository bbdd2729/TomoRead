import 'package:flutter/material.dart';

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
  });

  final ThemeMode mode;
  final ThemeSeed seed;
  final double textScale;

  AppAppearance copyWith({
    ThemeMode? mode,
    ThemeSeed? seed,
    double? textScale,
  }) {
    return AppAppearance(
      mode: mode ?? this.mode,
      seed: seed ?? this.seed,
      textScale: textScale ?? this.textScale,
    );
  }
}
