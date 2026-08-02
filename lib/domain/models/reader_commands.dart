enum ReaderCommand {
  previousPage,
  nextPage,
  scrollUp,
  scrollDown,
  openTableOfContents,
  toggleBookmark,
  search,
  toggleFocusMode,
  increaseFontSize,
  decreaseFontSize,
  toggleTextColoring,
  togglePomodoro,
  ttsPlayPause,
  ttsStop,
  toggleAutoScroll,
}

extension ReaderCommandInfo on ReaderCommand {
  String get label => switch (this) {
    ReaderCommand.previousPage => '上一页 / 上一章',
    ReaderCommand.nextPage => '下一页 / 下一章',
    ReaderCommand.scrollUp => '向上滚动',
    ReaderCommand.scrollDown => '向下滚动',
    ReaderCommand.openTableOfContents => '打开章节目录',
    ReaderCommand.toggleBookmark => '添加 / 移除书签',
    ReaderCommand.search => '搜索正文',
    ReaderCommand.toggleFocusMode => '切换沉浸模式',
    ReaderCommand.increaseFontSize => '增大字号',
    ReaderCommand.decreaseFontSize => '减小字号',
    ReaderCommand.toggleTextColoring => '开关文字前景色',
    ReaderCommand.togglePomodoro => '开始 / 暂停番茄钟',
    ReaderCommand.ttsPlayPause => '播放 / 暂停朗读',
    ReaderCommand.ttsStop => '停止朗读',
    ReaderCommand.toggleAutoScroll => '开始 / 停止自动滚动',
  };
}

enum ReaderShortcutPlatform { windows, linux }

enum AutoScrollUnit { linesPerMinute, screensPerMinute }

extension AutoScrollUnitInfo on AutoScrollUnit {
  String get label => switch (this) {
    AutoScrollUnit.linesPerMinute => '行 / 分钟',
    AutoScrollUnit.screensPerMinute => '屏 / 分钟',
  };
}

class AutoScrollPreference {
  const AutoScrollPreference({
    this.unit = AutoScrollUnit.linesPerMinute,
    this.speed = 30,
  });

  final AutoScrollUnit unit;
  final double speed;

  AutoScrollPreference copyWith({AutoScrollUnit? unit, double? speed}) =>
      AutoScrollPreference(
        unit: unit ?? this.unit,
        speed: (speed ?? this.speed).clamp(0.1, 240).toDouble(),
      );

  Map<String, Object> toJson() => {'unit': unit.name, 'speed': speed};

  factory AutoScrollPreference.fromJson(Object? source) {
    if (source is! Map) return const AutoScrollPreference();
    final unitName = source['unit'];
    final speed = source['speed'];
    return AutoScrollPreference(
      unit: AutoScrollUnit.values.firstWhere(
        (value) => value.name == unitName,
        orElse: () => AutoScrollUnit.linesPerMinute,
      ),
      speed: (speed is num ? speed.toDouble() : 30)
          .clamp(0.1, 240)
          .toDouble(),
    );
  }
}

class ReaderShortcutChord {
  const ReaderShortcutChord({
    required this.key,
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  final String key;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;

  String get signature => [
    if (control) 'control',
    if (alt) 'alt',
    if (shift) 'shift',
    if (meta) 'meta',
    key.toLowerCase(),
  ].join('+');

  String get label => [
    if (control) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    if (meta) 'Meta',
    readerShortcutKeyLabel(key),
  ].join(' + ');

  Map<String, Object> toJson() => {
    'key': key,
    'control': control,
    'alt': alt,
    'shift': shift,
    'meta': meta,
  };

  factory ReaderShortcutChord.fromJson(Object? source) {
    if (source is! Map || source['key'] is! String) {
      throw const FormatException('快捷键缺少按键。');
    }
    return ReaderShortcutChord(
      key: source['key']! as String,
      control: source['control'] == true,
      alt: source['alt'] == true,
      shift: source['shift'] == true,
      meta: source['meta'] == true,
    );
  }
}

class ReaderShortcutBinding {
  const ReaderShortcutBinding({
    required this.command,
    required this.platform,
    required this.chord,
    this.enabled = true,
    this.userModifiable = true,
  });

  final ReaderCommand command;
  final ReaderShortcutPlatform platform;
  final ReaderShortcutChord? chord;
  final bool enabled;
  final bool userModifiable;

  ReaderShortcutBinding copyWith({
    ReaderShortcutChord? chord,
    bool clearChord = false,
    bool? enabled,
  }) => ReaderShortcutBinding(
    command: command,
    platform: platform,
    chord: clearChord ? null : chord ?? this.chord,
    enabled: enabled ?? this.enabled,
    userModifiable: userModifiable,
  );

  Map<String, Object?> toJson() => {
    'command': command.name,
    'platform': platform.name,
    'chord': chord?.toJson(),
    'enabled': enabled,
    'userModifiable': userModifiable,
  };

  factory ReaderShortcutBinding.fromJson(Object? source) {
    if (source is! Map) throw const FormatException('快捷键绑定格式无效。');
    final commandName = source['command'];
    final platformName = source['platform'];
    final command = ReaderCommand.values.firstWhere(
      (value) => value.name == commandName,
      orElse: () => throw const FormatException('快捷键命令无效。'),
    );
    final platform = ReaderShortcutPlatform.values.firstWhere(
      (value) => value.name == platformName,
      orElse: () => throw const FormatException('快捷键平台无效。'),
    );
    final chordSource = source['chord'];
    return ReaderShortcutBinding(
      command: command,
      platform: platform,
      chord: chordSource == null
          ? null
          : ReaderShortcutChord.fromJson(chordSource),
      enabled: source['enabled'] != false,
      userModifiable: source['userModifiable'] != false,
    );
  }
}

class ReaderCommandSettings {
  const ReaderCommandSettings({
    required this.bindings,
    required this.autoScroll,
  });

  factory ReaderCommandSettings.defaults() => ReaderCommandSettings(
    bindings: [
      for (final platform in ReaderShortcutPlatform.values)
        ..._defaultBindingsFor(platform),
    ],
    autoScroll: const AutoScrollPreference(),
  );

  final List<ReaderShortcutBinding> bindings;
  final AutoScrollPreference autoScroll;

  List<ReaderShortcutBinding> forPlatform(ReaderShortcutPlatform platform) =>
      bindings.where((binding) => binding.platform == platform).toList();

  ReaderCommandSettings replaceBinding(ReaderShortcutBinding binding) =>
      ReaderCommandSettings(
        bindings: [
          for (final current in bindings)
            if (current.command == binding.command &&
                current.platform == binding.platform)
              binding
            else
              current,
        ],
        autoScroll: autoScroll,
      );

  ReaderCommandSettings copyWith({
    List<ReaderShortcutBinding>? bindings,
    AutoScrollPreference? autoScroll,
  }) => ReaderCommandSettings(
    bindings: bindings ?? this.bindings,
    autoScroll: autoScroll ?? this.autoScroll,
  );

  Map<String, Object> toJson() => {
    'bindings': bindings.map((binding) => binding.toJson()).toList(),
    'autoScroll': autoScroll.toJson(),
  };

  factory ReaderCommandSettings.fromJson(Object? source) {
    final defaults = ReaderCommandSettings.defaults();
    if (source is! Map || source['bindings'] is! List) return defaults;
    final decoded = <ReaderShortcutBinding>[];
    for (final value in source['bindings']! as List) {
      try {
        decoded.add(ReaderShortcutBinding.fromJson(value));
      } on FormatException {
        // Unknown commands from a newer version are ignored.
      }
    }
    final byIdentity = <String, ReaderShortcutBinding>{
      for (final binding in decoded)
        '${binding.platform.name}:${binding.command.name}': binding,
    };
    return ReaderCommandSettings(
      bindings: [
        for (final fallback in defaults.bindings)
          byIdentity['${fallback.platform.name}:${fallback.command.name}'] ??
              fallback,
      ],
      autoScroll: AutoScrollPreference.fromJson(source['autoScroll']),
    );
  }
}

List<ReaderShortcutBinding> _defaultBindingsFor(
  ReaderShortcutPlatform platform,
) {
  const chords = <ReaderCommand, ReaderShortcutChord?>{
    ReaderCommand.previousPage: ReaderShortcutChord(key: 'pageUp'),
    ReaderCommand.nextPage: ReaderShortcutChord(key: 'pageDown'),
    ReaderCommand.scrollUp: ReaderShortcutChord(key: 'arrowUp'),
    ReaderCommand.scrollDown: ReaderShortcutChord(key: 'arrowDown'),
    ReaderCommand.openTableOfContents: ReaderShortcutChord(
      key: 'keyT',
      control: true,
    ),
    ReaderCommand.toggleBookmark: ReaderShortcutChord(
      key: 'keyD',
      control: true,
    ),
    ReaderCommand.search: ReaderShortcutChord(key: 'keyF', control: true),
    ReaderCommand.toggleFocusMode: ReaderShortcutChord(
      key: 'keyM',
      control: true,
    ),
    ReaderCommand.increaseFontSize: ReaderShortcutChord(
      key: 'equal',
      control: true,
    ),
    ReaderCommand.decreaseFontSize: ReaderShortcutChord(
      key: 'minus',
      control: true,
    ),
    ReaderCommand.toggleTextColoring: ReaderShortcutChord(
      key: 'keyC',
      control: true,
      shift: true,
    ),
    ReaderCommand.togglePomodoro: ReaderShortcutChord(
      key: 'keyP',
      control: true,
      shift: true,
    ),
    ReaderCommand.ttsPlayPause: ReaderShortcutChord(
      key: 'space',
      control: true,
      shift: true,
    ),
    ReaderCommand.ttsStop: ReaderShortcutChord(
      key: 'keyS',
      control: true,
      shift: true,
    ),
    ReaderCommand.toggleAutoScroll: ReaderShortcutChord(
      key: 'keyA',
      control: true,
      shift: true,
    ),
  };
  return [
    for (final command in ReaderCommand.values)
      ReaderShortcutBinding(
        command: command,
        platform: platform,
        chord: chords[command],
        enabled: chords[command] != null,
      ),
  ];
}

const supportedReaderShortcutKeys = <String>[
  'arrowUp',
  'arrowDown',
  'arrowLeft',
  'arrowRight',
  'pageUp',
  'pageDown',
  'home',
  'end',
  'space',
  'minus',
  'equal',
  'keyA',
  'keyB',
  'keyC',
  'keyD',
  'keyE',
  'keyF',
  'keyG',
  'keyH',
  'keyI',
  'keyJ',
  'keyK',
  'keyL',
  'keyM',
  'keyN',
  'keyO',
  'keyP',
  'keyQ',
  'keyR',
  'keyS',
  'keyT',
  'keyU',
  'keyV',
  'keyW',
  'keyX',
  'keyY',
  'keyZ',
];

String readerShortcutKeyLabel(String key) => switch (key) {
  'arrowUp' => '↑',
  'arrowDown' => '↓',
  'arrowLeft' => '←',
  'arrowRight' => '→',
  'pageUp' => 'Page Up',
  'pageDown' => 'Page Down',
  'home' => 'Home',
  'end' => 'End',
  'space' => 'Space',
  'minus' => '-',
  'equal' => '=',
  _ when key.startsWith('key') => key.substring(3),
  _ => key,
};
