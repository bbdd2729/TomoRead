enum TextColorSemanticToken { latin, number, punctuation, quoted, bracketed }

extension TextColorSemanticTokenX on TextColorSemanticToken {
  String get label => switch (this) {
    TextColorSemanticToken.latin => '英文字母',
    TextColorSemanticToken.number => '数字',
    TextColorSemanticToken.punctuation => '标点符号',
    TextColorSemanticToken.quoted => '引号内容',
    TextColorSemanticToken.bracketed => '括号内容',
  };

  String get description => switch (this) {
    TextColorSemanticToken.latin => '突出中文正文中的英文术语。',
    TextColorSemanticToken.number => '突出年份、编号和数值。',
    TextColorSemanticToken.punctuation => '使用较柔和的颜色显示标点。',
    TextColorSemanticToken.quoted => '为同一文本片段内成对引号中的内容着色。',
    TextColorSemanticToken.bracketed => '为同一文本片段内成对括号中的内容着色。',
  };
}

enum TextColorTermTone { rose, orange, green, blue, purple }

extension TextColorTermToneX on TextColorTermTone {
  String get label => switch (this) {
    TextColorTermTone.rose => '玫红',
    TextColorTermTone.orange => '橙色',
    TextColorTermTone.green => '绿色',
    TextColorTermTone.blue => '蓝色',
    TextColorTermTone.purple => '紫色',
  };
}

class TextColorPair {
  const TextColorPair({required this.light, required this.dark});

  final String light;
  final String dark;

  TextColorPair copyWith({String? light, String? dark}) => TextColorPair(
    light: light ?? this.light,
    dark: dark ?? this.dark,
  );

  Map<String, Object> toJson() => {'light': light, 'dark': dark};

  static TextColorPair fromJson(
    Object? source, {
    required TextColorPair fallback,
  }) {
    if (source is! Map) return fallback;
    return TextColorPair(
      light: normalizeHexColor(source['light'], fallback.light),
      dark: normalizeHexColor(source['dark'], fallback.dark),
    );
  }
}

class TextColorTokenStyle {
  const TextColorTokenStyle({
    required this.enabled,
    required this.colors,
  });

  final bool enabled;
  final TextColorPair colors;

  TextColorTokenStyle copyWith({bool? enabled, TextColorPair? colors}) =>
      TextColorTokenStyle(
        enabled: enabled ?? this.enabled,
        colors: colors ?? this.colors,
      );

  Map<String, Object> toJson() => {
    'enabled': enabled,
    ...colors.toJson(),
  };

  static TextColorTokenStyle fromJson(
    Object? source, {
    required TextColorTokenStyle fallback,
  }) {
    if (source is! Map) return fallback;
    final enabled = source['enabled'];
    return TextColorTokenStyle(
      enabled: enabled is bool ? enabled : fallback.enabled,
      colors: TextColorPair.fromJson(source, fallback: fallback.colors),
    );
  }
}

class TextColoringSettings {
  const TextColoringSettings({
    required this.enabled,
    required this.tokens,
    required this.termPalette,
  });

  factory TextColoringSettings.defaults() => const TextColoringSettings(
    enabled: false,
    tokens: {
      TextColorSemanticToken.latin: TextColorTokenStyle(
        enabled: false,
        colors: TextColorPair(light: '#2E6B8A', dark: '#8BC4E3'),
      ),
      TextColorSemanticToken.number: TextColorTokenStyle(
        enabled: false,
        colors: TextColorPair(light: '#8A5A20', dark: '#F0BE75'),
      ),
      TextColorSemanticToken.punctuation: TextColorTokenStyle(
        enabled: false,
        colors: TextColorPair(light: '#6D7780', dark: '#AAB4BE'),
      ),
      TextColorSemanticToken.quoted: TextColorTokenStyle(
        enabled: false,
        colors: TextColorPair(light: '#7B4E91', dark: '#D9B8F0'),
      ),
      TextColorSemanticToken.bracketed: TextColorTokenStyle(
        enabled: false,
        colors: TextColorPair(light: '#476D4C', dark: '#A5D6A7'),
      ),
    },
    termPalette: {
      TextColorTermTone.rose: TextColorPair(
        light: '#B4235A',
        dark: '#FF8DB5',
      ),
      TextColorTermTone.orange: TextColorPair(
        light: '#9A4B12',
        dark: '#FFB46A',
      ),
      TextColorTermTone.green: TextColorPair(
        light: '#287044',
        dark: '#78D89A',
      ),
      TextColorTermTone.blue: TextColorPair(
        light: '#246B9B',
        dark: '#7CC7F5',
      ),
      TextColorTermTone.purple: TextColorPair(
        light: '#7544A3',
        dark: '#D1A2FF',
      ),
    },
  );

  final bool enabled;
  final Map<TextColorSemanticToken, TextColorTokenStyle> tokens;
  final Map<TextColorTermTone, TextColorPair> termPalette;

  TextColoringSettings copyWith({
    bool? enabled,
    Map<TextColorSemanticToken, TextColorTokenStyle>? tokens,
    Map<TextColorTermTone, TextColorPair>? termPalette,
  }) => TextColoringSettings(
    enabled: enabled ?? this.enabled,
    tokens: tokens ?? this.tokens,
    termPalette: termPalette ?? this.termPalette,
  );

  TextColoringSettings updateToken(
    TextColorSemanticToken token,
    TextColorTokenStyle style,
  ) => copyWith(tokens: {...tokens, token: style});

  TextColoringSettings updateTermTone(
    TextColorTermTone tone,
    TextColorPair colors,
  ) => copyWith(termPalette: {...termPalette, tone: colors});

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'tokens': {
      for (final entry in tokens.entries) entry.key.name: entry.value.toJson(),
    },
    'termPalette': {
      for (final entry in termPalette.entries)
        entry.key.name: entry.value.toJson(),
    },
  };

  static TextColoringSettings fromJson(Object? source) {
    final defaults = TextColoringSettings.defaults();
    if (source is! Map) return defaults;
    final tokenSource = source['tokens'];
    final paletteSource = source['termPalette'];
    final enabled = source['enabled'];
    return TextColoringSettings(
      enabled: enabled is bool ? enabled : defaults.enabled,
      tokens: {
        for (final token in TextColorSemanticToken.values)
          token: TextColorTokenStyle.fromJson(
            tokenSource is Map ? tokenSource[token.name] : null,
            fallback: defaults.tokens[token]!,
          ),
      },
      termPalette: {
        for (final tone in TextColorTermTone.values)
          tone: TextColorPair.fromJson(
            paletteSource is Map ? paletteSource[tone.name] : null,
            fallback: defaults.termPalette[tone]!,
          ),
      },
    );
  }
}

class TextColorTerm {
  const TextColorTerm({
    required this.id,
    required this.term,
    required this.normalizedTerm,
    required this.tone,
    required this.createdAt,
    required this.updatedAt,
    this.bookId,
  });

  final String id;
  final String? bookId;
  final String term;
  final String normalizedTerm;
  final TextColorTermTone tone;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isGlobal => bookId == null;
}

class ResolvedTextColoring {
  const ResolvedTextColoring({
    required this.settings,
    required this.enabled,
    required this.terms,
  });

  factory ResolvedTextColoring.disabled() => ResolvedTextColoring(
    settings: TextColoringSettings.defaults(),
    enabled: false,
    terms: const [],
  );

  final TextColoringSettings settings;
  final bool enabled;
  final List<TextColorTerm> terms;

  Map<String, Object> toRuntimeJson({required bool dark}) {
    final colors = <String, String>{};
    final enabledTokens = <String>[];
    for (final entry in settings.tokens.entries) {
      if (!entry.value.enabled) continue;
      enabledTokens.add(entry.key.name);
      colors['token-${entry.key.name}'] = dark
          ? entry.value.colors.dark
          : entry.value.colors.light;
    }
    for (final entry in settings.termPalette.entries) {
      colors['term-${entry.key.name}'] = dark
          ? entry.value.dark
          : entry.value.light;
    }
    return {
      'enabled': enabled,
      'tokens': enabledTokens,
      'colors': colors,
      'terms': [
        for (final term in terms)
          {
            'text': term.term,
            'colorKey': 'term-${term.tone.name}',
            'scope': term.isGlobal ? 'global' : 'book',
          },
      ],
    };
  }
}

String normalizeTextColorTerm(String source) =>
    source.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String normalizeHexColor(Object? source, String fallback) {
  final value = source is String ? source.trim().toUpperCase() : '';
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(value) ? value : fallback;
}

class TextColoringException implements Exception {
  const TextColoringException(this.message);

  final String message;

  @override
  String toString() => message;
}
