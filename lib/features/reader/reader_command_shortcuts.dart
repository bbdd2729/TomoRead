import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/reader_commands.dart';

class ReaderCommandIntent extends Intent {
  const ReaderCommandIntent(this.command);

  final ReaderCommand command;
}

class ReaderCommandShortcuts extends StatelessWidget {
  const ReaderCommandShortcuts({
    super.key,
    required this.settings,
    required this.callbacks,
    required this.child,
    this.autofocus = true,
    this.platform,
  });

  final ReaderCommandSettings settings;
  final Map<ReaderCommand, VoidCallback> callbacks;
  final Widget child;
  final bool autofocus;
  final ReaderShortcutPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final platform = this.platform ?? currentReaderShortcutPlatform();
    if (platform == null || kIsWeb) return child;
    final shortcuts = <ShortcutActivator, Intent>{};
    for (final binding in settings.forPlatform(platform)) {
      final chord = binding.chord;
      if (!binding.enabled || chord == null || !callbacks.containsKey(binding.command)) {
        continue;
      }
      final key = logicalReaderShortcutKey(chord.key);
      if (key == null) continue;
      shortcuts[
        SingleActivator(
          key,
          control: chord.control,
          alt: chord.alt,
          shift: chord.shift,
          meta: chord.meta,
        )
      ] = ReaderCommandIntent(binding.command);
    }
    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: {
          ReaderCommandIntent: CallbackAction<ReaderCommandIntent>(
            onInvoke: (intent) {
              callbacks[intent.command]?.call();
              return null;
            },
          ),
        },
        child: Focus(autofocus: autofocus, child: child),
      ),
    );
  }
}

ReaderShortcutPlatform? currentReaderShortcutPlatform() =>
    switch (defaultTargetPlatform) {
      TargetPlatform.windows => ReaderShortcutPlatform.windows,
      TargetPlatform.linux => ReaderShortcutPlatform.linux,
      _ => null,
    };

LogicalKeyboardKey? logicalReaderShortcutKey(String key) => switch (key) {
  'arrowUp' => LogicalKeyboardKey.arrowUp,
  'arrowDown' => LogicalKeyboardKey.arrowDown,
  'arrowLeft' => LogicalKeyboardKey.arrowLeft,
  'arrowRight' => LogicalKeyboardKey.arrowRight,
  'pageUp' => LogicalKeyboardKey.pageUp,
  'pageDown' => LogicalKeyboardKey.pageDown,
  'home' => LogicalKeyboardKey.home,
  'end' => LogicalKeyboardKey.end,
  'space' => LogicalKeyboardKey.space,
  'minus' => LogicalKeyboardKey.minus,
  'equal' => LogicalKeyboardKey.equal,
  _ when key.length == 4 && key.startsWith('key') =>
    _letterKey(key.codeUnitAt(3)),
  _ => null,
};

LogicalKeyboardKey? _letterKey(int codeUnit) => switch (codeUnit) {
  0x41 => LogicalKeyboardKey.keyA,
  0x42 => LogicalKeyboardKey.keyB,
  0x43 => LogicalKeyboardKey.keyC,
  0x44 => LogicalKeyboardKey.keyD,
  0x45 => LogicalKeyboardKey.keyE,
  0x46 => LogicalKeyboardKey.keyF,
  0x47 => LogicalKeyboardKey.keyG,
  0x48 => LogicalKeyboardKey.keyH,
  0x49 => LogicalKeyboardKey.keyI,
  0x4a => LogicalKeyboardKey.keyJ,
  0x4b => LogicalKeyboardKey.keyK,
  0x4c => LogicalKeyboardKey.keyL,
  0x4d => LogicalKeyboardKey.keyM,
  0x4e => LogicalKeyboardKey.keyN,
  0x4f => LogicalKeyboardKey.keyO,
  0x50 => LogicalKeyboardKey.keyP,
  0x51 => LogicalKeyboardKey.keyQ,
  0x52 => LogicalKeyboardKey.keyR,
  0x53 => LogicalKeyboardKey.keyS,
  0x54 => LogicalKeyboardKey.keyT,
  0x55 => LogicalKeyboardKey.keyU,
  0x56 => LogicalKeyboardKey.keyV,
  0x57 => LogicalKeyboardKey.keyW,
  0x58 => LogicalKeyboardKey.keyX,
  0x59 => LogicalKeyboardKey.keyY,
  0x5a => LogicalKeyboardKey.keyZ,
  _ => null,
};
