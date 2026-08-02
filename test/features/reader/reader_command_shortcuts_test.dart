import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/reader_commands.dart';
import 'package:tomoread/features/reader/reader_command_shortcuts.dart';

void main() {
  testWidgets('dispatches configured commands through the shared intent', (
    tester,
  ) async {
    var nextCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderCommandShortcuts(
          settings: ReaderCommandSettings.defaults(),
          callbacks: {
            ReaderCommand.nextPage: () => nextCount++,
          },
          platform: ReaderShortcutPlatform.linux,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();

    expect(nextCount, 1);
  });
}
