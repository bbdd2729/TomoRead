import '../../domain/models/document_locator.dart';

enum PdfSelectionFailureReason {
  copyProtected,
  textLayerUnavailable,
  multiplePages,
  invalidRange,
  invalidGeometry,
}

class PdfSelectionException implements Exception {
  const PdfSelectionException(this.reason, this.message);

  final PdfSelectionFailureReason reason;
  final String message;

  @override
  String toString() => message;
}

class PdfSelectionSourceRect {
  const PdfSelectionSourceRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

class PdfSelectionSource {
  const PdfSelectionSource({
    required this.pageNumber,
    required this.pageText,
    required this.start,
    required this.end,
    required this.pageWidth,
    required this.pageHeight,
    required this.rects,
  });

  final int pageNumber;
  final String pageText;
  final int start;
  final int end;
  final double pageWidth;
  final double pageHeight;
  final List<PdfSelectionSourceRect> rects;
}

class PdfVerifiedSelection {
  const PdfVerifiedSelection({required this.locator, required this.text});

  final PdfDocumentLocator locator;
  final String text;
}

/// Builds and verifies the format-specific locator used by PDF annotations.
///
/// The source rectangles use the rotated, top-left-origin page coordinate
/// system shown by the viewer. Persisted rectangles are normalized to 0..1,
/// so zoom and viewport changes do not affect annotation placement.
class PdfSelectionLocatorService {
  const PdfSelectionLocatorService();

  static const _contextLength = 64;

  PdfVerifiedSelection create(PdfSelectionSource source) {
    if (source.pageNumber < 1 ||
        source.pageWidth <= 0 ||
        source.pageHeight <= 0 ||
        !source.pageWidth.isFinite ||
        !source.pageHeight.isFinite ||
        source.start < 0 ||
        source.end <= source.start ||
        source.end > source.pageText.length) {
      throw const PdfSelectionException(
        PdfSelectionFailureReason.invalidRange,
        '无法验证当前 PDF 选区，请重新选择文字。',
      );
    }

    final quote = normalizeText(
      source.pageText.substring(source.start, source.end),
    );
    if (quote.isEmpty) {
      throw const PdfSelectionException(
        PdfSelectionFailureReason.textLayerUnavailable,
        '当前选区没有可用文本，不支持文本标注。',
      );
    }

    final rects = <PdfNormalizedRect>[];
    final serializedRects = <String>{};
    for (final sourceRect in source.rects) {
      final left = sourceRect.left.clamp(0.0, source.pageWidth).toDouble();
      final top = sourceRect.top.clamp(0.0, source.pageHeight).toDouble();
      final right = (sourceRect.left + sourceRect.width)
          .clamp(0.0, source.pageWidth)
          .toDouble();
      final bottom = (sourceRect.top + sourceRect.height)
          .clamp(0.0, source.pageHeight)
          .toDouble();
      if (!left.isFinite ||
          !top.isFinite ||
          !right.isFinite ||
          !bottom.isFinite ||
          right <= left ||
          bottom <= top) {
        continue;
      }
      final rect = PdfNormalizedRect(
        left: left / source.pageWidth,
        top: top / source.pageHeight,
        width: (right - left) / source.pageWidth,
        height: (bottom - top) / source.pageHeight,
      );
      final serialized = rect.serialize();
      if (rect.isValid && serializedRects.add(serialized)) rects.add(rect);
    }
    if (rects.isEmpty) {
      throw const PdfSelectionException(
        PdfSelectionFailureReason.invalidGeometry,
        '无法取得当前 PDF 选区的位置，请重新选择文字。',
      );
    }

    final prefix = _takeLast(
      normalizeText(source.pageText.substring(0, source.start)),
      _contextLength,
    );
    final suffix = _takeFirst(
      normalizeText(source.pageText.substring(source.end)),
      _contextLength,
    );
    final locator = PdfDocumentLocator(
      pageNumber: source.pageNumber,
      rects: rects,
      quote: quote,
      prefix: prefix.isEmpty ? null : prefix,
      suffix: suffix.isEmpty ? null : suffix,
    );
    if (!verifies(locator, source.pageText)) {
      throw const PdfSelectionException(
        PdfSelectionFailureReason.invalidRange,
        '当前 PDF 文本与选区位置不一致，请重新选择文字。',
      );
    }
    return PdfVerifiedSelection(locator: locator, text: quote);
  }

  bool verifies(PdfDocumentLocator locator, String pageText) {
    final quote = normalizeText(locator.quote ?? '');
    if (locator.pageNumber < 1 || quote.isEmpty || locator.rects.isEmpty) {
      return false;
    }
    final normalizedPage = normalizeText(pageText);
    if (normalizedPage.isEmpty) return false;
    final prefix = normalizeText(locator.prefix ?? '');
    final suffix = normalizeText(locator.suffix ?? '');
    var searchStart = 0;
    while (searchStart <= normalizedPage.length - quote.length) {
      final index = normalizedPage.indexOf(quote, searchStart);
      if (index < 0) return false;
      final before = normalizedPage.substring(0, index);
      final after = normalizedPage.substring(index + quote.length);
      if ((prefix.isEmpty || before.trimRight().endsWith(prefix)) &&
          (suffix.isEmpty || after.trimLeft().startsWith(suffix))) {
        return true;
      }
      searchStart = index + 1;
    }
    return false;
  }

  String normalizeText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _takeFirst(String value, int length) =>
      value.length <= length ? value : value.substring(0, length);

  String _takeLast(String value, int length) =>
      value.length <= length ? value : value.substring(value.length - length);
}
