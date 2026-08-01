import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';

void main() {
  test('resolves a spine index from a resource href', () {
    const manifest = EpubManifest(
      opfPath: 'OEBPS/content.opf',
      version: '3.0',
      direction: ReadingDirection.ltr,
      spine: [
        EpubSpineItem(
          id: 'cover',
          href: 'OEBPS/Text/cover.xhtml',
          linear: true,
        ),
        EpubSpineItem(
          id: 'chapter-1',
          href: 'OEBPS/Text/chapter-1.xhtml',
          linear: true,
        ),
      ],
      toc: [],
    );

    expect(
      epubSpineIndexForHref(
        manifest,
        'https://reader.local/OEBPS/Text/chapter-1.xhtml#section-2',
      ),
      1,
    );
    expect(epubSpineIndexForHref(manifest, 'missing.xhtml'), isNull);
  });
}
