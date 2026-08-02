import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/models/display_projection.dart';
import '../../domain/models/text_coloring.dart';
import '../../domain/models/text_coloring_layout.dart';

class TextColoringLayoutService {
  const TextColoringLayoutService();

  Future<TextColoringLayout> layout({
    required DisplayProjection projection,
    required ResolvedTextColoring coloring,
    required bool markdown,
    required bool dark,
  }) => startLayout(
    projection: projection,
    coloring: coloring,
    markdown: markdown,
    dark: dark,
  ).result;

  TextColoringLayoutJob startLayout({
    required DisplayProjection projection,
    required ResolvedTextColoring coloring,
    required bool markdown,
    required bool dark,
  }) => TextColoringLayoutJob._start(
    projection: projection,
    coloring: coloring,
    markdown: markdown,
    dark: dark,
  );
}

class TextColoringLayoutJob {
  TextColoringLayoutJob._(this._completer, this._isolate, this._receivePort);

  final Completer<TextColoringLayout> _completer;
  final Future<Isolate> _isolate;
  final ReceivePort _receivePort;
  var _cancelled = false;

  Future<TextColoringLayout> get result => _completer.future;

  static TextColoringLayoutJob _start({
    required DisplayProjection projection,
    required ResolvedTextColoring coloring,
    required bool markdown,
    required bool dark,
  }) {
    final receivePort = ReceivePort();
    final completer = Completer<TextColoringLayout>();
    late final TextColoringLayoutJob job;
    receivePort.listen((message) {
      if (job._cancelled || completer.isCompleted) return;
      if (message is TextColoringLayout) {
        completer.complete(message);
      } else if (message is Map && message['error'] is String) {
        completer.completeError(TextColoringLayoutException(message['error']! as String));
      }
      receivePort.close();
    });
    final isolate = Isolate.spawn<
      (SendPort, DisplayProjection, ResolvedTextColoring, bool, bool)
    >(
      _buildInIsolate,
      (receivePort.sendPort, projection, coloring, markdown, dark),
      errorsAreFatal: true,
    );
    job = TextColoringLayoutJob._(completer, isolate, receivePort);
    unawaited(
      isolate.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) completer.completeError(error, stackTrace);
          receivePort.close();
        },
      ),
    );
    return job;
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    (await _isolate).kill(priority: Isolate.immediate);
    _receivePort.close();
    if (!_completer.isCompleted) {
      _completer.completeError(
        const TextColoringLayoutException('文字前景色计算已取消。'),
      );
    }
  }
}

class TextColoringLayoutException implements Exception {
  const TextColoringLayoutException(this.message);

  final String message;

  @override
  String toString() => message;
}

void _buildInIsolate(
  (SendPort, DisplayProjection, ResolvedTextColoring, bool, bool) request,
) {
  try {
    request.$1.send(
      _buildLayout(
        projection: request.$2,
        coloring: request.$3,
        markdown: request.$4,
        dark: request.$5,
      ),
    );
  } on Object catch (error) {
    request.$1.send({'error': error.toString()});
  }
}

TextColoringLayout _buildLayout({
  required DisplayProjection projection,
  required ResolvedTextColoring coloring,
  required bool markdown,
  required bool dark,
}) {
  final projected = markdown
      ? _MarkdownProjector(projection.displayText).project()
      : _ProjectedText.plain(projection.displayText);
  final colors = _matchColors(
    projected: projected,
    projection: projection,
    coloring: coloring,
    dark: dark,
  );
  return TextColoringLayout(
    text: projected.text,
    displaySourceLength: projection.displayText.length,
    sourceCells: projected.cells,
    styles: projected.styles,
    colors: colors,
  );
}

List<TextColoringRange> _matchColors({
  required _ProjectedText projected,
  required DisplayProjection projection,
  required ResolvedTextColoring coloring,
  required bool dark,
}) {
  if (!coloring.enabled || projected.text.isEmpty) return const [];
  final configuredColors = <String, String>{};
  for (final entry in coloring.settings.termPalette.entries) {
    configuredColors['term-${entry.key.name}'] = dark
        ? entry.value.dark
        : entry.value.light;
  }
  for (final entry in coloring.settings.tokens.entries) {
    if (!entry.value.enabled) continue;
    configuredColors['token-${entry.key.name}'] = dark
        ? entry.value.colors.dark
        : entry.value.colors.light;
  }

  final occupied = Uint8List(projected.text.length);
  final blocked = Uint8List(projected.text.length);
  for (final range in projected.blocked) {
    final start = range.start.clamp(0, blocked.length).toInt();
    final end = range.end.clamp(start, blocked.length).toInt();
    blocked.fillRange(start, end, 1);
  }
  final result = <TextColoringRange>[];

  void addRange(String colorKey, int start, int end) {
    final hexColor = configuredColors[colorKey];
    if (hexColor == null || start < 0 || end <= start || end > occupied.length) {
      return;
    }
    for (var index = start; index < end; index++) {
      if (occupied[index] != 0 || blocked[index] != 0) return;
    }
    final displayRange = _visibleToDisplay(projected, start, end);
    if (!displayRange.isExact) return;
    final rawRange = projection.displayToRaw(displayRange.start, displayRange.end);
    if (!rawRange.isExact) return;
    occupied.fillRange(start, end, 1);
    result.add(
      TextColoringRange(
        start: start,
        end: end,
        rawStart: rawRange.start,
        rawEnd: rawRange.end,
        colorKey: colorKey,
        hexColor: hexColor,
      ),
    );
  }

  final terms = coloring.terms
      .where((term) => term.term.isNotEmpty && term.term.runes.length <= 100)
      .toList()
    ..sort((left, right) {
      final byLength = right.term.runes.length.compareTo(left.term.runes.length);
      if (byLength != 0) return byLength;
      if (left.isGlobal == right.isGlobal) return 0;
      return left.isGlobal ? 1 : -1;
    });
  for (final term in terms) {
    final expression = RegExp(
      RegExp.escape(term.term),
      caseSensitive: false,
      unicode: true,
    );
    for (final match in expression.allMatches(projected.text)) {
      addRange('term-${term.tone.name}', match.start, match.end);
    }
  }

  final tokens = coloring.settings.tokens;
  if (tokens[TextColorSemanticToken.quoted]?.enabled == true) {
    final expression = RegExp(
      '“[^”\\n]+”|‘[^’\\n]+’|「[^」\\n]+」|『[^』\\n]+』|"[^"\\n]+"',
      unicode: true,
    );
    for (final match in expression.allMatches(projected.text)) {
      addRange('token-quoted', match.start + 1, match.end - 1);
    }
  }
  if (tokens[TextColorSemanticToken.bracketed]?.enabled == true) {
    final expression = RegExp(
      r'（[^）\n]+）|\([^()\n]+\)|【[^】\n]+】|\[[^\]\n]+\]',
      unicode: true,
    );
    for (final match in expression.allMatches(projected.text)) {
      addRange('token-bracketed', match.start + 1, match.end - 1);
    }
  }
  if (tokens[TextColorSemanticToken.latin]?.enabled == true) {
    final expression = RegExp(
      r"[A-Za-z]+(?:['’\-][A-Za-z]+)*",
      unicode: true,
    );
    for (final match in expression.allMatches(projected.text)) {
      addRange('token-latin', match.start, match.end);
    }
  }
  if (tokens[TextColorSemanticToken.number]?.enabled == true) {
    final expression = RegExp(
      r'[0-9０-９]+(?:[.,][0-9０-９]+)*',
      unicode: true,
    );
    for (final match in expression.allMatches(projected.text)) {
      addRange('token-number', match.start, match.end);
    }
  }
  if (tokens[TextColorSemanticToken.punctuation]?.enabled == true) {
    var offset = 0;
    for (final rune in projected.text.runes) {
      final width = rune > 0xffff ? 2 : 1;
      if (_isPunctuationOrSymbol(rune)) {
        addRange('token-punctuation', offset, offset + width);
      }
      offset += width;
    }
  }
  result.sort((left, right) => left.start.compareTo(right.start));
  return result;
}

TextColoringSourceRange _visibleToDisplay(
  _ProjectedText projected,
  int start,
  int end,
) {
  if (projected.cells.isEmpty) {
    return TextColoringSourceRange(start: start, end: end, isExact: true);
  }
  final cells = projected.cells.sublist(start, end);
  var contiguous = true;
  for (var index = 1; index < cells.length; index++) {
    if (cells[index - 1].sourceEnd != cells[index].sourceStart) {
      contiguous = false;
      break;
    }
  }
  return TextColoringSourceRange(
    start: cells.first.sourceStart,
    end: cells.last.sourceEnd,
    isExact: contiguous && cells.every((cell) => cell.isExact),
  );
}

bool _isPunctuationOrSymbol(int rune) =>
    (rune >= 0x21 && rune <= 0x2f) ||
    (rune >= 0x3a && rune <= 0x40) ||
    (rune >= 0x5b && rune <= 0x60) ||
    (rune >= 0x7b && rune <= 0x7e) ||
    (rune >= 0x2000 && rune <= 0x206f) ||
    (rune >= 0x20a0 && rune <= 0x20cf) ||
    (rune >= 0x2100 && rune <= 0x27ff) ||
    (rune >= 0x2e00 && rune <= 0x2e7f) ||
    (rune >= 0x3000 && rune <= 0x303f) ||
    (rune >= 0xfe10 && rune <= 0xfe1f) ||
    (rune >= 0xfe30 && rune <= 0xfe4f) ||
    (rune >= 0xff01 && rune <= 0xff0f) ||
    (rune >= 0xff1a && rune <= 0xff20) ||
    (rune >= 0xff3b && rune <= 0xff40) ||
    (rune >= 0xff5b && rune <= 0xff65) ||
    (rune >= 0x1f000 && rune <= 0x1faff);

class _ProjectedText {
  const _ProjectedText({
    required this.text,
    required this.cells,
    required this.styles,
    required this.blocked,
  });

  factory _ProjectedText.plain(String text) => _ProjectedText(
    text: text,
    cells: const [],
    styles: const [],
    blocked: const [],
  );

  final String text;
  final List<TextColoringSourceCell> cells;
  final List<MarkdownTextStyleRange> styles;
  final List<TextColoringSourceRange> blocked;
}

class _SourceLine {
  const _SourceLine({
    required this.start,
    required this.contentEnd,
    required this.end,
  });

  final int start;
  final int contentEnd;
  final int end;
}

class _MarkdownProjector {
  _MarkdownProjector(this.source);

  final String source;
  final _text = StringBuffer();
  final _cells = <TextColoringSourceCell>[];
  final _cellStyles = <MarkdownTextStyle>[];
  final _blockedCells = <bool>[];

  _ProjectedText project() {
    final lines = _lines();
    final setextMarkers = <int>{};
    final setextLevels = <int, int>{};
    for (var index = 1; index < lines.length; index++) {
      final marker = source.substring(lines[index].start, lines[index].contentEnd);
      final match = RegExp(r'^\s{0,3}(=+|-+)\s*$').firstMatch(marker);
      if (match != null &&
          source.substring(lines[index - 1].start, lines[index - 1].contentEnd).trim().isNotEmpty) {
        setextMarkers.add(index);
        setextLevels[index - 1] = match.group(1)!.startsWith('=') ? 1 : 2;
      }
    }

    String? fence;
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final lineText = source.substring(line.start, line.contentEnd);
      final fenceMatch = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(lineText);
      if (fenceMatch != null) {
        final marker = fenceMatch.group(1)!;
        if (fence == null) {
          fence = marker[0];
        } else if (marker[0] == fence) {
          fence = null;
        }
        _appendLineEnding(line, const MarkdownTextStyle(code: true), true);
        continue;
      }
      if (fence != null) {
        _appendSource(
          line.start,
          line.contentEnd,
          const MarkdownTextStyle(code: true),
          true,
        );
        _appendLineEnding(line, const MarkdownTextStyle(code: true), true);
        continue;
      }
      if (setextMarkers.contains(lineIndex)) {
        _appendLineEnding(line, const MarkdownTextStyle(), false);
        continue;
      }

      var contentStart = line.start;
      var contentEnd = line.contentEnd;
      var style = MarkdownTextStyle(headingLevel: setextLevels[lineIndex]);
      var relative = source.substring(contentStart, contentEnd);

      final quote = RegExp(r'^\s{0,3}(?:>\s?)+').firstMatch(relative);
      if (quote != null) {
        contentStart += quote.end;
        style = style.merge(const MarkdownTextStyle(quote: true));
        relative = source.substring(contentStart, contentEnd);
      }
      final heading = RegExp(r'^\s{0,3}(#{1,6})[ \t]+').firstMatch(relative);
      if (heading != null) {
        contentStart += heading.end;
        style = style.merge(
          MarkdownTextStyle(headingLevel: heading.group(1)!.length),
        );
        final trailing = RegExp(r'[ \t]+#+[ \t]*$').firstMatch(
          source.substring(contentStart, contentEnd),
        );
        if (trailing != null) contentEnd = contentStart + trailing.start;
        relative = source.substring(contentStart, contentEnd);
      }
      final unordered = RegExp(r'^(\s*)[-+*][ \t]+').firstMatch(relative);
      final ordered = unordered == null
          ? RegExp(r'^(\s*)(\d+[.)])[ \t]+').firstMatch(relative)
          : null;
      if (unordered != null) {
        final indentationEnd = contentStart + unordered.group(1)!.length;
        _appendSource(contentStart, indentationEnd, style, false);
        _appendGenerated('• ', indentationEnd, contentStart + unordered.end, style);
        contentStart += unordered.end;
      } else if (ordered != null) {
        final indentationEnd = contentStart + ordered.group(1)!.length;
        final markerEnd = indentationEnd + ordered.group(2)!.length;
        _appendSource(contentStart, markerEnd, style, false);
        _appendGenerated(' ', markerEnd, contentStart + ordered.end, style);
        contentStart += ordered.end;
      } else if (relative.startsWith('    ')) {
        contentStart += 4;
        style = style.merge(const MarkdownTextStyle(code: true));
      }

      final horizontalRule = RegExp(
        r'^\s{0,3}((\*\s*){3,}|(-\s*){3,}|(_\s*){3,})$',
      ).hasMatch(source.substring(contentStart, contentEnd));
      if (horizontalRule) {
        _appendGenerated('────────', contentStart, contentEnd, style);
      } else {
        _appendInline(
          contentStart,
          contentEnd,
          style,
          blocked: style.code,
        );
      }
      _appendLineEnding(line, style, style.code);
    }

    return _ProjectedText(
      text: _text.toString(),
      cells: List.unmodifiable(_cells),
      styles: List.unmodifiable(_styleRanges()),
      blocked: List.unmodifiable(_blockedRanges()),
    );
  }

  List<_SourceLine> _lines() {
    final result = <_SourceLine>[];
    var start = 0;
    while (start < source.length) {
      final newline = source.indexOf('\n', start);
      final end = newline < 0 ? source.length : newline + 1;
      var contentEnd = newline < 0 ? source.length : newline;
      if (contentEnd > start && source.codeUnitAt(contentEnd - 1) == 0x0d) {
        contentEnd--;
      }
      result.add(_SourceLine(start: start, contentEnd: contentEnd, end: end));
      start = end;
    }
    if (source.isEmpty) {
      result.add(const _SourceLine(start: 0, contentEnd: 0, end: 0));
    }
    return result;
  }

  void _appendInline(
    int start,
    int end,
    MarkdownTextStyle style, {
    required bool blocked,
  }) {
    var index = start;
    while (index < end) {
      if (source.startsWith('![', index)) {
        final labelEnd = source.indexOf(']', index + 2);
        if (labelEnd >= 0 && labelEnd < end) {
          final destinationEnd = _linkDestinationEnd(labelEnd + 1, end);
          if (destinationEnd != null) {
            _appendInline(
              index + 2,
              labelEnd,
              style.merge(const MarkdownTextStyle(italic: true)),
              blocked: true,
            );
            index = destinationEnd;
            continue;
          }
        }
      }
      if (source.codeUnitAt(index) == 0x5b) {
        final labelEnd = source.indexOf(']', index + 1);
        if (labelEnd >= 0 && labelEnd < end) {
          final destinationEnd = _linkDestinationEnd(labelEnd + 1, end);
          if (destinationEnd != null) {
            _appendInline(
              index + 1,
              labelEnd,
              style.merge(const MarkdownTextStyle(link: true)),
              blocked: blocked,
            );
            index = destinationEnd;
            continue;
          }
        }
      }
      if (source.codeUnitAt(index) == 0x60) {
        var markerEnd = index;
        while (markerEnd < end && source.codeUnitAt(markerEnd) == 0x60) {
          markerEnd++;
        }
        final marker = source.substring(index, markerEnd);
        final closing = source.indexOf(marker, markerEnd);
        if (closing >= markerEnd && closing < end) {
          _appendSource(
            markerEnd,
            closing,
            style.merge(const MarkdownTextStyle(code: true)),
            true,
          );
          index = closing + marker.length;
          continue;
        }
      }
      final delimiter = _styleDelimiterAt(index, end);
      if (delimiter != null) {
        final closing = source.indexOf(delimiter.marker, index + delimiter.marker.length);
        if (closing > index + delimiter.marker.length - 1 && closing < end) {
          _appendInline(
            index + delimiter.marker.length,
            closing,
            style.merge(delimiter.style),
            blocked: blocked,
          );
          index = closing + delimiter.marker.length;
          continue;
        }
      }
      if (source.codeUnitAt(index) == 0x3c) {
        final closing = source.indexOf('>', index + 1);
        if (closing > index && closing < end) {
          final inner = source.substring(index + 1, closing);
          if (inner.startsWith('http://') ||
              inner.startsWith('https://') ||
              inner.startsWith('mailto:')) {
            _appendSource(
              index + 1,
              closing,
              style.merge(const MarkdownTextStyle(link: true)),
              true,
            );
          }
          index = closing + 1;
          continue;
        }
      }
      final url = RegExp(r'(?:https?://|www\.)[^\s<>()]+').matchAsPrefix(
        source,
        index,
      );
      if (url != null && url.end <= end) {
        _appendSource(
          url.start,
          url.end,
          style.merge(const MarkdownTextStyle(link: true)),
          true,
        );
        index = url.end;
        continue;
      }
      if (source.codeUnitAt(index) == 0x5c && index + 1 < end) {
        _appendSource(index + 1, index + 2, style, blocked);
        index += 2;
        continue;
      }
      final next = _nextCodePointOffset(index, end);
      _appendSource(index, next, style, blocked);
      index = next;
    }
  }

  int? _linkDestinationEnd(int start, int end) {
    if (start >= end) return null;
    if (source.codeUnitAt(start) == 0x28) {
      var depth = 1;
      for (var index = start + 1; index < end; index++) {
        final unit = source.codeUnitAt(index);
        if (unit == 0x28) depth++;
        if (unit == 0x29 && --depth == 0) return index + 1;
      }
      return null;
    }
    if (source.codeUnitAt(start) == 0x5b) {
      final closing = source.indexOf(']', start + 1);
      return closing >= 0 && closing < end ? closing + 1 : null;
    }
    return null;
  }

  _StyleDelimiter? _styleDelimiterAt(int index, int end) {
    if (index + 1 < end && source.startsWith('**', index)) {
      return const _StyleDelimiter('**', MarkdownTextStyle(bold: true));
    }
    if (index + 1 < end && source.startsWith('__', index)) {
      return const _StyleDelimiter('__', MarkdownTextStyle(bold: true));
    }
    if (index + 1 < end && source.startsWith('~~', index)) {
      return const _StyleDelimiter(
        '~~',
        MarkdownTextStyle(strikethrough: true),
      );
    }
    if (source.codeUnitAt(index) == 0x2a) {
      return const _StyleDelimiter('*', MarkdownTextStyle(italic: true));
    }
    if (source.codeUnitAt(index) == 0x5f) {
      return const _StyleDelimiter('_', MarkdownTextStyle(italic: true));
    }
    return null;
  }

  int _nextCodePointOffset(int index, int end) {
    final first = source.codeUnitAt(index);
    if (first >= 0xd800 &&
        first <= 0xdbff &&
        index + 1 < end) {
      final second = source.codeUnitAt(index + 1);
      if (second >= 0xdc00 && second <= 0xdfff) return index + 2;
    }
    return index + 1;
  }

  void _appendSource(
    int start,
    int end,
    MarkdownTextStyle style,
    bool blocked,
  ) {
    if (end <= start) return;
    _text.write(source.substring(start, end));
    for (var index = start; index < end; index++) {
      _cells.add(
        TextColoringSourceCell(
          sourceStart: index,
          sourceEnd: index + 1,
          isExact: true,
        ),
      );
      _cellStyles.add(style);
      _blockedCells.add(blocked);
    }
  }

  void _appendGenerated(
    String text,
    int sourceStart,
    int sourceEnd,
    MarkdownTextStyle style,
  ) {
    _text.write(text);
    for (var index = 0; index < text.length; index++) {
      _cells.add(
        TextColoringSourceCell(
          sourceStart: sourceStart,
          sourceEnd: sourceEnd,
          isExact: false,
        ),
      );
      _cellStyles.add(style);
      _blockedCells.add(true);
    }
  }

  void _appendLineEnding(
    _SourceLine line,
    MarkdownTextStyle style,
    bool blocked,
  ) {
    if (line.end <= line.contentEnd) return;
    _appendSource(line.contentEnd, line.end, style, blocked);
  }

  List<MarkdownTextStyleRange> _styleRanges() {
    final result = <MarkdownTextStyleRange>[];
    var start = 0;
    while (start < _cellStyles.length) {
      final style = _cellStyles[start];
      var end = start + 1;
      while (end < _cellStyles.length && _cellStyles[end] == style) {
        end++;
      }
      if (style != const MarkdownTextStyle()) {
        result.add(MarkdownTextStyleRange(start: start, end: end, style: style));
      }
      start = end;
    }
    return result;
  }

  List<TextColoringSourceRange> _blockedRanges() {
    final result = <TextColoringSourceRange>[];
    var start = 0;
    while (start < _blockedCells.length) {
      if (!_blockedCells[start]) {
        start++;
        continue;
      }
      var end = start + 1;
      while (end < _blockedCells.length && _blockedCells[end]) {
        end++;
      }
      result.add(TextColoringSourceRange(start: start, end: end, isExact: true));
      start = end;
    }
    return result;
  }
}

class _StyleDelimiter {
  const _StyleDelimiter(this.marker, this.style);

  final String marker;
  final MarkdownTextStyle style;
}
