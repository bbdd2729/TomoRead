import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/epub_interaction.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';

void main() {
  const manifest = EpubManifest(
    opfPath: 'OEBPS/content.opf',
    version: '3.0',
    direction: ReadingDirection.ltr,
    spine: [
      EpubSpineItem(
        id: 'chapter-1',
        href: 'OEBPS/Text/chapter-1.xhtml',
        linear: true,
      ),
      EpubSpineItem(
        id: 'notes',
        href: 'OEBPS/Text/notes.xhtml',
        linear: true,
      ),
    ],
    toc: [],
  );

  Map<Object?, Object?> message({
    String action = 'footnoteOpened',
    String href = 'OEBPS/Text/chapter-1.xhtml',
    String? targetHref = 'OEBPS/Text/notes.xhtml',
    String? resourceId = 'note-1',
  }) => {
    'bridgeVersion': epubBridgeSchemaVersion,
    'type': 'epubInteraction',
    'action': action,
    'href': href,
    'targetHref': targetHref,
    'resourceId': resourceId,
    'locator': {
      'chapterIndex': 0,
      'ratio': 0.25,
      'anchor': 'paragraph-3',
      'cfi': 'epubcfi(/6/4!/4/2)',
    },
  };

  group('EpubInteraction bridge validation', () {
    test('accepts a versioned footnote message from the spine', () {
      final interaction = EpubInteraction.fromBridgeMessage(
        message(),
        manifest: manifest,
      );

      expect(interaction.kind, EpubInteractionKind.footnoteOpened);
      expect(interaction.resourceId, 'note-1');
      expect(interaction.locator.chapterIndex, 0);
      expect(interaction.locator.ratio, 0.25);
    });

    test('accepts only http and https external links without credentials', () {
      final value = message(
        action: 'externalLinkRequested',
        targetHref: null,
        resourceId: null,
      )..['externalUrl'] = 'https://example.com/reference';

      final interaction = EpubInteraction.fromBridgeMessage(
        value,
        manifest: manifest,
      );
      expect(interaction.externalUri?.host, 'example.com');

      value['externalUrl'] = 'javascript:alert(1)';
      expect(
        () => EpubInteraction.fromBridgeMessage(value, manifest: manifest),
        throwsFormatException,
      );
      value['externalUrl'] = 'https://reader:secret@example.com/private';
      expect(
        () => EpubInteraction.fromBridgeMessage(value, manifest: manifest),
        throwsFormatException,
      );
    });

    test('rejects unknown versions and non-spine source hrefs', () {
      final value = message()..['bridgeVersion'] = 99;
      expect(
        () => EpubInteraction.fromBridgeMessage(value, manifest: manifest),
        throwsFormatException,
      );

      value
        ..['bridgeVersion'] = epubBridgeSchemaVersion
        ..['href'] = '../outside.xhtml';
      expect(
        () => EpubInteraction.fromBridgeMessage(value, manifest: manifest),
        throwsFormatException,
      );
    });

    test('rejects traversal resource ids and mismatched locator chapters', () {
      final value = message(
        action: 'imageOpened',
        targetHref: null,
        resourceId: '../private/image.png',
      );
      expect(
        () => EpubInteraction.fromBridgeMessage(value, manifest: manifest),
        throwsFormatException,
      );

      value['resourceId'] = 'OEBPS/Images/cover.png';
      (value['locator']! as Map<Object?, Object?>)['chapterIndex'] = 1;
      expect(
        () => EpubInteraction.fromBridgeMessage(value, manifest: manifest),
        throwsFormatException,
      );
    });
  });
}
