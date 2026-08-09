import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/reading_settings.dart';
import 'package:tomoread/features/settings/volume_key_page_turning_setting.dart';

void main() {
  testWidgets('shows the switch on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VolumeKeyPageTurningSetting(
            settings: ReadingSettings(),
            onChanged: _ignoreSettings,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('volume-key-turns-page-setting')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('does not render the switch on desktop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VolumeKeyPageTurningSetting(
            settings: ReadingSettings(),
            onChanged: _ignoreSettings,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('volume-key-turns-page-setting')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}

void _ignoreSettings(ReadingSettings settings) {}
