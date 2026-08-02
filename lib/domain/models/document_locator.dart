import 'epub_location.dart';

enum DocumentLocatorKind { epub, pdf, text }

enum DocumentLocatorPrecision { exact, approximate }

abstract interface class DocumentLocator {
  DocumentLocatorKind get kind;
  int get version;
  DocumentLocatorPrecision get precision;
  String serialize();
}

class EpubDocumentLocator implements DocumentLocator {
  const EpubDocumentLocator({required this.location, this.href});

  final EpubLocation location;
  final String? href;

  @override
  DocumentLocatorKind get kind => DocumentLocatorKind.epub;

  @override
  int get version => 3;

  @override
  DocumentLocatorPrecision get precision =>
      location.cfi != null || location.anchor != null
      ? DocumentLocatorPrecision.exact
      : DocumentLocatorPrecision.approximate;

  @override
  String serialize() => location.toLocator();

  static EpubDocumentLocator? tryParse(
    String? value, {
    required int fallbackChapterIndex,
    String? href,
  }) {
    if (value == null || value.trim().isEmpty) return null;
    if (!_isStructurallyValid(value)) return null;
    try {
      return EpubDocumentLocator(
        href: href,
        location: EpubLocation.fromLocator(
          value,
          fallbackChapterIndex: fallbackChapterIndex,
        ),
      );
    } on FormatException {
      return null;
    }
  }

  static bool _isStructurallyValid(String value) {
    if (RegExp(r'^chapter-\d+:start$').hasMatch(value) ||
        RegExp(r'^\d+:(?:\d+(?:\.\d+)?|\.\d+)$').hasMatch(value)) {
      return true;
    }
    final String? versionPrefix;
    if (value.startsWith('epub:v3|')) {
      versionPrefix = 'epub:v3|';
    } else if (value.startsWith('epub:v2|')) {
      versionPrefix = 'epub:v2|';
    } else if (value.startsWith('epub:')) {
      versionPrefix = 'epub:';
    } else {
      versionPrefix = null;
    }
    if (versionPrefix == null) return false;
    final parts = value.substring(versionPrefix.length).split('|');
    if (versionPrefix == 'epub:v3|') {
      if (parts.length != 4) return false;
    } else if (parts.length < 2 || parts.length > 3) {
      return false;
    }
    final chapter = int.tryParse(parts[0]);
    final ratio = double.tryParse(parts[1]);
    if (chapter == null || chapter < 0 || ratio == null || !ratio.isFinite) {
      return false;
    }
    if (ratio < 0 || ratio > 1) return false;
    try {
      for (final encoded in parts.skip(2)) {
        if (encoded.isNotEmpty) Uri.decodeComponent(encoded);
      }
    } on FormatException {
      return false;
    }
    return true;
  }
}

class PdfNormalizedRect {
  const PdfNormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  bool get isValid =>
      left >= 0 &&
      top >= 0 &&
      width > 0 &&
      height > 0 &&
      left + width <= 1.000001 &&
      top + height <= 1.000001;

  String serialize() => [left, top, width, height]
      .map((value) => value.toStringAsFixed(6))
      .join(',');

  static PdfNormalizedRect? tryParse(String value) {
    final parts = value.split(',').map(double.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return null;
    final rect = PdfNormalizedRect(
      left: parts[0]!,
      top: parts[1]!,
      width: parts[2]!,
      height: parts[3]!,
    );
    return rect.isValid ? rect : null;
  }
}

class PdfDocumentLocator implements DocumentLocator {
  const PdfDocumentLocator({
    required this.pageNumber,
    this.rects = const [],
    this.quote,
    this.prefix,
    this.suffix,
  });

  final int pageNumber;
  final List<PdfNormalizedRect> rects;
  final String? quote;
  final String? prefix;
  final String? suffix;

  @override
  DocumentLocatorKind get kind => DocumentLocatorKind.pdf;

  @override
  int get version => 1;

  @override
  DocumentLocatorPrecision get precision => rects.isNotEmpty && quote != null
      ? DocumentLocatorPrecision.exact
      : DocumentLocatorPrecision.approximate;

  @override
  String serialize() {
    final encodedRects = rects.map((rect) => rect.serialize()).join(';');
    return 'pdf:v1|$pageNumber|$encodedRects|${_encode(quote)}|'
        '${_encode(prefix)}|${_encode(suffix)}';
  }

  static PdfDocumentLocator? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final legacy = RegExp(r'^page:(\d+)$').firstMatch(value);
    if (legacy != null) {
      final page = int.parse(legacy.group(1)!);
      return page > 0 ? PdfDocumentLocator(pageNumber: page) : null;
    }
    if (!value.startsWith('pdf:v1|')) return null;
    try {
      final parts = value.substring('pdf:v1|'.length).split('|');
      if (parts.length != 5) return null;
      final page = int.tryParse(parts[0]);
      if (page == null || page <= 0) return null;
      final rects = parts[1].isEmpty
          ? const <PdfNormalizedRect>[]
          : parts[1]
                .split(';')
                .map(PdfNormalizedRect.tryParse)
                .toList();
      if (rects.any((rect) => rect == null)) return null;
      return PdfDocumentLocator(
        pageNumber: page,
        rects: rects.cast<PdfNormalizedRect>(),
        quote: _decode(parts[2]),
        prefix: _decode(parts[3]),
        suffix: _decode(parts[4]),
      );
    } on FormatException {
      return null;
    }
  }
}

class TextDocumentLocator implements DocumentLocator {
  const TextDocumentLocator({
    required this.chapterIndex,
    required this.rawStart,
    required this.rawEnd,
  });

  final int chapterIndex;
  final int rawStart;
  final int rawEnd;

  @override
  DocumentLocatorKind get kind => DocumentLocatorKind.text;

  @override
  int get version => 1;

  @override
  DocumentLocatorPrecision get precision => DocumentLocatorPrecision.exact;

  @override
  String serialize() => 'text:v1|$chapterIndex|$rawStart|$rawEnd';

  static TextDocumentLocator? tryParse(String? value) {
    if (value == null || !value.startsWith('text:v1|')) return null;
    final parts = value.substring('text:v1|'.length).split('|');
    if (parts.length != 3) return null;
    final chapter = int.tryParse(parts[0]);
    final start = int.tryParse(parts[1]);
    final end = int.tryParse(parts[2]);
    if (chapter == null ||
        start == null ||
        end == null ||
        chapter < 0 ||
        start < 0 ||
        end < start) {
      return null;
    }
    return TextDocumentLocator(
      chapterIndex: chapter,
      rawStart: start,
      rawEnd: end,
    );
  }
}

String _encode(String? value) =>
    value == null || value.isEmpty ? '' : Uri.encodeComponent(value);

String? _decode(String value) =>
    value.isEmpty ? null : Uri.decodeComponent(value);
