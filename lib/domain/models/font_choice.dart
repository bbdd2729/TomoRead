enum FontChoice { system, serif, monospace }

extension FontChoiceX on FontChoice {
  String get label => switch (this) {
    FontChoice.system => '系统默认',
    FontChoice.serif => '衬线字体',
    FontChoice.monospace => '等宽字体',
  };

  String? get fontFamily => switch (this) {
    FontChoice.system => null,
    FontChoice.serif => 'serif',
    FontChoice.monospace => 'monospace',
  };
}
