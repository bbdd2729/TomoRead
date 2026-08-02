class TextColoringSourceCell {
  const TextColoringSourceCell({
    required this.sourceStart,
    required this.sourceEnd,
    required this.isExact,
  });

  final int sourceStart;
  final int sourceEnd;
  final bool isExact;
}

class TextColoringSourceRange {
  const TextColoringSourceRange({
    required this.start,
    required this.end,
    required this.isExact,
  });

  final int start;
  final int end;
  final bool isExact;
}

class MarkdownTextStyle {
  const MarkdownTextStyle({
    this.headingLevel,
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.quote = false,
    this.link = false,
    this.strikethrough = false,
  });

  final int? headingLevel;
  final bool bold;
  final bool italic;
  final bool code;
  final bool quote;
  final bool link;
  final bool strikethrough;

  MarkdownTextStyle merge(MarkdownTextStyle other) => MarkdownTextStyle(
    headingLevel: other.headingLevel ?? headingLevel,
    bold: bold || other.bold,
    italic: italic || other.italic,
    code: code || other.code,
    quote: quote || other.quote,
    link: link || other.link,
    strikethrough: strikethrough || other.strikethrough,
  );

  @override
  bool operator ==(Object other) =>
      other is MarkdownTextStyle &&
      headingLevel == other.headingLevel &&
      bold == other.bold &&
      italic == other.italic &&
      code == other.code &&
      quote == other.quote &&
      link == other.link &&
      strikethrough == other.strikethrough;

  @override
  int get hashCode => Object.hash(
    headingLevel,
    bold,
    italic,
    code,
    quote,
    link,
    strikethrough,
  );
}

class MarkdownTextStyleRange {
  const MarkdownTextStyleRange({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final MarkdownTextStyle style;
}

class TextColoringRange {
  const TextColoringRange({
    required this.start,
    required this.end,
    required this.rawStart,
    required this.rawEnd,
    required this.colorKey,
    required this.hexColor,
  });

  final int start;
  final int end;
  final int rawStart;
  final int rawEnd;
  final String colorKey;
  final String hexColor;
}

class TextColoringLayout {
  const TextColoringLayout({
    required this.text,
    required this.displaySourceLength,
    required this.sourceCells,
    required this.styles,
    required this.colors,
  });

  factory TextColoringLayout.plain(String text) => TextColoringLayout(
    text: text,
    displaySourceLength: text.length,
    sourceCells: const [],
    styles: const [],
    colors: const [],
  );

  final String text;
  final int displaySourceLength;
  final List<TextColoringSourceCell> sourceCells;
  final List<MarkdownTextStyleRange> styles;
  final List<TextColoringRange> colors;

  TextColoringSourceRange visibleToDisplay(int start, int end) {
    final safeStart = start.clamp(0, text.length).toInt();
    final safeEnd = end.clamp(safeStart, text.length).toInt();
    if (sourceCells.isEmpty) {
      return TextColoringSourceRange(
        start: safeStart,
        end: safeEnd,
        isExact: true,
      );
    }
    if (safeStart == safeEnd) {
      final offset = safeStart == sourceCells.length
          ? displaySourceLength
          : sourceCells[safeStart].sourceStart;
      return TextColoringSourceRange(
        start: offset,
        end: offset,
        isExact: true,
      );
    }
    final cells = sourceCells.sublist(safeStart, safeEnd);
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
}
