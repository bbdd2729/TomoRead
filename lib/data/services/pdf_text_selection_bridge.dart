import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

import '../../domain/models/document_locator.dart';
import '../../domain/models/reading_annotation.dart';
import 'pdf_selection_locator_service.dart';

/// Isolates pdfrx text-selection objects from reader UI and stored locators.
class PdfTextSelectionBridge {
  const PdfTextSelectionBridge({
    this.locatorService = const PdfSelectionLocatorService(),
  });

  final PdfSelectionLocatorService locatorService;

  Future<PdfVerifiedSelection> capture({
    required PdfTextSelectionDelegate delegate,
    required PdfDocument document,
  }) async {
    if (!delegate.isCopyAllowed) {
      throw const PdfSelectionException(
        PdfSelectionFailureReason.copyProtected,
        '此 PDF 禁止复制文本，无法创建可验证标注。',
      );
    }
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) {
      throw const PdfSelectionException(
        PdfSelectionFailureReason.textLayerUnavailable,
        '当前 PDF 没有可用文本层，不支持文本标注。',
      );
    }
    final pages = ranges.map((range) => range.pageNumber).toSet();
    if (pages.length != 1 || ranges.length != 1) {
      throw const PdfSelectionException(
        PdfSelectionFailureReason.multiplePages,
        '暂不支持跨页标注，请在同一页内选择文字。',
      );
    }

    final range = ranges.single;
    if (range.pageNumber < 1 || range.pageNumber > document.pages.length) {
      throw const PdfSelectionException(
        PdfSelectionFailureReason.invalidRange,
        '无法验证当前 PDF 页码，请重新选择文字。',
      );
    }
    final page = document.pages[range.pageNumber - 1];
    final rects = range.enumerateFragmentBoundingRects().map((fragment) {
      final rect = fragment.bounds.toRect(page: page);
      return PdfSelectionSourceRect(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
      );
    }).toList(growable: false);
    return locatorService.create(
      PdfSelectionSource(
        pageNumber: range.pageNumber,
        pageText: range.pageText.fullText,
        start: range.start,
        end: range.end,
        pageWidth: page.width,
        pageHeight: page.height,
        rects: rects,
      ),
    );
  }

  Future<bool> pageSupportsText(PdfDocument document, int pageNumber) async {
    if (document.permissions?.allowsCopying == false ||
        pageNumber < 1 ||
        pageNumber > document.pages.length) {
      return false;
    }
    try {
      final text = await document.pages[pageNumber - 1].loadStructuredText();
      return text.fullText.trim().isNotEmpty && text.charRects.isNotEmpty;
    } on Object {
      return false;
    }
  }

  Future<bool> verifyLocator(
    PdfDocument document,
    PdfDocumentLocator locator,
  ) async {
    if (locator.pageNumber < 1 ||
        locator.pageNumber > document.pages.length ||
        locator.precision != DocumentLocatorPrecision.exact) {
      return false;
    }
    try {
      final text = await document.pages[locator.pageNumber - 1]
          .loadStructuredText();
      return locatorService.verifies(locator, text.fullText);
    } on Object {
      return false;
    }
  }

  Future<List<ReadingAnnotation>> verifyAnnotations(
    PdfDocument document,
    Iterable<ReadingAnnotation> annotations,
  ) async {
    final result = <ReadingAnnotation>[];
    final pageText = <int, String?>{};
    for (final annotation in annotations) {
      final locator = PdfDocumentLocator.tryParse(annotation.locator);
      if (locator == null ||
          locator.precision != DocumentLocatorPrecision.exact ||
          locator.pageNumber > document.pages.length ||
          locatorService.normalizeText(annotation.selectedText) !=
              locatorService.normalizeText(locator.quote ?? '')) {
        continue;
      }
      if (!pageText.containsKey(locator.pageNumber)) {
        try {
          pageText[locator.pageNumber] = (await document
                  .pages[locator.pageNumber - 1]
                  .loadStructuredText())
              .fullText;
        } on Object {
          pageText[locator.pageNumber] = null;
        }
      }
      final text = pageText[locator.pageNumber];
      if (text != null && locatorService.verifies(locator, text)) {
        result.add(annotation);
      }
    }
    return result;
  }

  PdfRect? targetRect(PdfDocument document, PdfDocumentLocator locator) {
    if (locator.pageNumber < 1 ||
        locator.pageNumber > document.pages.length ||
        locator.rects.isEmpty) {
      return null;
    }
    final page = document.pages[locator.pageNumber - 1];
    var left = 1.0;
    var top = 1.0;
    var right = 0.0;
    var bottom = 0.0;
    for (final rect in locator.rects) {
      if (rect.left < left) left = rect.left;
      if (rect.top < top) top = rect.top;
      if (rect.left + rect.width > right) right = rect.left + rect.width;
      if (rect.top + rect.height > bottom) bottom = rect.top + rect.height;
    }
    if (right <= left || bottom <= top) return null;
    return Rect.fromLTRB(
      left * page.width,
      top * page.height,
      right * page.width,
      bottom * page.height,
    ).toPdfRect(page: page);
  }
}
