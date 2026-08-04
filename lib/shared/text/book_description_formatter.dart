/// Formats EPUB and other imported metadata descriptions for plain-text UI.
///
/// Descriptions often contain HTML escaped inside XML metadata. Keeping the
/// source string unchanged lets users edit or export it faithfully, while this
/// formatter provides a safe, readable representation for Flutter [Text].
class BookDescriptionFormatter {
  const BookDescriptionFormatter._();

  static String format(String? source) {
    var value = source?.trim() ?? '';
    if (value.isEmpty) return '';

    // EPUB metadata commonly stores an HTML fragment as `&lt;p&gt;…`.
    // Decode before identifying structural tags, then once more for text
    // entities that were nested inside the fragment.
    value = _decodeHtmlEntities(value);
    value = value
        .replaceAll(
          RegExp(
            r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false, dotAll: true),
          '\n',
        )
        .replaceAll(
          RegExp(
            r'</\s*(?:p|div|h[1-6]|tr|blockquote|section|article)\s*>',
            caseSensitive: false,
            dotAll: true,
          ),
          '\n\n',
        )
        .replaceAll(
          RegExp(r'<\s*li\b[^>]*>', caseSensitive: false, dotAll: true),
          '\n• ',
        )
        .replaceAll(
          RegExp(r'</\s*li\s*>', caseSensitive: false, dotAll: true),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
    value = _decodeHtmlEntities(value).replaceAll('\u00a0', ' ');

    final lines = value
        .split(RegExp(r'\r?\n'))
        .map((line) => line.replaceAll(RegExp(r'[\t\f ]+'), ' ').trim())
        .toList(growable: false);
    return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static String _decodeHtmlEntities(String value) {
    const named = <String, String>{
      'amp': '&',
      'apos': "'",
      'copy': '©',
      'gt': '>',
      'hellip': '…',
      'laquo': '«',
      'ldquo': '“',
      'lsquo': '‘',
      'lt': '<',
      'mdash': '—',
      'nbsp': ' ',
      'ndash': '–',
      'quot': '"',
      'raquo': '»',
      'rdquo': '”',
      'reg': '®',
      'rsquo': '’',
    };
    return value.replaceAllMapped(
      RegExp(r'&(?:#x([0-9a-fA-F]+)|#(\d+)|([a-zA-Z][a-zA-Z0-9]+));'),
      (match) {
        final hexadecimal = match.group(1);
        final decimal = match.group(2);
        if (hexadecimal != null || decimal != null) {
          final codePoint = int.tryParse(
            hexadecimal ?? decimal!,
            radix: hexadecimal == null ? 10 : 16,
          );
          return codePoint == null ||
                  codePoint < 0 ||
                  codePoint > 0x10ffff ||
                  (codePoint >= 0xd800 && codePoint <= 0xdfff)
              ? match.group(0)!
              : String.fromCharCode(codePoint);
        }
        return named[match.group(3)?.toLowerCase()] ?? match.group(0)!;
      },
    );
  }
}
