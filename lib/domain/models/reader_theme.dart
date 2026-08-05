enum ReaderThemePreset {
  followApp,
  white,
  mist,
  paper,
  eyeCare,
  dark,
  amoled,
  custom,
}

extension ReaderThemePresetX on ReaderThemePreset {
  String get label => switch (this) {
    ReaderThemePreset.followApp => '跟随应用',
    ReaderThemePreset.white => '白纸',
    ReaderThemePreset.mist => '雾绿',
    ReaderThemePreset.paper => '纸张',
    ReaderThemePreset.eyeCare => '护眼',
    ReaderThemePreset.dark => '深色',
    ReaderThemePreset.amoled => 'AMOLED',
    ReaderThemePreset.custom => '自定义',
  };

  String get description => switch (this) {
    ReaderThemePreset.followApp => '使用应用当前的明暗和配色。',
    ReaderThemePreset.white => '中性白色纸面。',
    ReaderThemePreset.mist => '柔和的绿灰纸面。',
    ReaderThemePreset.paper => '暖米色纸张。',
    ReaderThemePreset.eyeCare => '低刺激浅绿底色。',
    ReaderThemePreset.dark => '低对比夜间阅读。',
    ReaderThemePreset.amoled => '纯黑背景，适合 OLED 屏幕。',
    ReaderThemePreset.custom => '使用已保存的三色主题。',
  };
}

/// A saved reader-only palette. Colors are stored as ARGB integers rather
/// than Flutter [Color] values so the preference model remains platform
/// neutral and easy to back up.
class CustomReaderTheme {
  const CustomReaderTheme({
    required this.id,
    required this.name,
    required this.backgroundArgb,
    required this.foregroundArgb,
    required this.accentArgb,
  });

  final String id;
  final String name;
  final int backgroundArgb;
  final int foregroundArgb;
  final int accentArgb;

  CustomReaderTheme copyWith({
    String? id,
    String? name,
    int? backgroundArgb,
    int? foregroundArgb,
    int? accentArgb,
  }) => CustomReaderTheme(
    id: id ?? this.id,
    name: name ?? this.name,
    backgroundArgb: backgroundArgb ?? this.backgroundArgb,
    foregroundArgb: foregroundArgb ?? this.foregroundArgb,
    accentArgb: accentArgb ?? this.accentArgb,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'backgroundArgb': backgroundArgb,
    'foregroundArgb': foregroundArgb,
    'accentArgb': accentArgb,
  };

  static CustomReaderTheme? tryParse(Object? value) {
    if (value is! Map) return null;
    final id = value['id'] as String?;
    final name = value['name'] as String?;
    final background = value['backgroundArgb'];
    final foreground = value['foregroundArgb'];
    final accent = value['accentArgb'];
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.trim().isEmpty ||
        background is! num ||
        foreground is! num ||
        accent is! num) {
      return null;
    }
    return CustomReaderTheme(
      id: id,
      name: name.trim(),
      backgroundArgb: background.toInt(),
      foregroundArgb: foreground.toInt(),
      accentArgb: accent.toInt(),
    );
  }
}

class ReaderThemeSelection {
  const ReaderThemeSelection({
    this.preset = ReaderThemePreset.followApp,
    this.customThemeId,
  });

  final ReaderThemePreset preset;
  final String? customThemeId;

  bool get isCustom => preset == ReaderThemePreset.custom;

  ReaderThemeSelection copyWith({
    ReaderThemePreset? preset,
    String? customThemeId,
    bool clearCustomTheme = false,
  }) => ReaderThemeSelection(
    preset: preset ?? this.preset,
    customThemeId: clearCustomTheme
        ? null
        : customThemeId ?? this.customThemeId,
  );

  Map<String, Object?> toJson() => {
    'preset': preset.name,
    if (customThemeId != null) 'customThemeId': customThemeId,
  };

  static ReaderThemeSelection fromJson(Object? value) {
    if (value is! Map) return const ReaderThemeSelection();
    final presetName = value['preset'] as String?;
    final preset = ReaderThemePreset.values.where((candidate) {
      return candidate.name == presetName;
    }).firstOrNull;
    return ReaderThemeSelection(
      preset: preset ?? ReaderThemePreset.followApp,
      customThemeId: value['customThemeId'] as String?,
    );
  }
}
