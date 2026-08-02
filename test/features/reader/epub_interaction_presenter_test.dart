import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/epub_interaction.dart';
import 'package:tomoread/features/reader/epub_interaction_presenter.dart';

void main() {
  const locator = EpubInteractionLocator(chapterIndex: 0, ratio: 0.2);
  final interaction = EpubInteraction(
    kind: EpubInteractionKind.externalLinkRequested,
    href: 'OEBPS/Text/chapter.xhtml',
    locator: locator,
    externalUri: Uri.parse('https://example.com/reference'),
  );

  Widget app({required EpubExternalUriLauncher launcher}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(
            presentEpubInteraction(
              context,
              interaction,
              launcher: launcher,
            ),
          ),
          child: const Text('请求打开'),
        ),
      ),
    ),
  );

  group('EPUB external link confirmation', () {
    testWidgets('does not launch when the user cancels', (tester) async {
      var launches = 0;
      await tester.pumpWidget(
        app(
          launcher: (uri) async {
            launches++;
            return true;
          },
        ),
      );

      await tester.tap(find.text('请求打开'));
      await tester.pump();
      expect(find.text('打开外部链接？'), findsOneWidget);
      expect(find.text('https://example.com/reference'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(launches, 0);
    });

    testWidgets('launches only after explicit confirmation', (tester) async {
      Uri? launchedUri;
      await tester.pumpWidget(
        app(
          launcher: (uri) async {
            launchedUri = uri;
            return true;
          },
        ),
      );

      await tester.tap(find.text('请求打开'));
      await tester.pump();
      expect(launchedUri, isNull);

      await tester.tap(find.text('继续打开'));
      await tester.pump();
      expect(launchedUri, Uri.parse('https://example.com/reference'));
    });
  });
}
