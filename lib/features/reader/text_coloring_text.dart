import 'package:flutter/material.dart';

import '../../domain/models/text_coloring_layout.dart';

class TextColoringSelectableText extends StatelessWidget {
  const TextColoringSelectableText({
    super.key,
    required this.layout,
    required this.style,
    this.onSelectionChanged,
  });

  final TextColoringLayout layout;
  final TextStyle style;
  final SelectionChangedCallback? onSelectionChanged;

  @override
  Widget build(BuildContext context) => SelectableText.rich(
    TextColoringTextSpanBuilder.build(
      context: context,
      layout: layout,
      baseStyle: style,
    ),
    onSelectionChanged: onSelectionChanged,
  );
}

class TextColoringTextSpanBuilder {
  const TextColoringTextSpanBuilder._();

  static TextSpan build({
    required BuildContext context,
    required TextColoringLayout layout,
    required TextStyle baseStyle,
  }) {
    if (layout.text.isEmpty) return TextSpan(text: '', style: baseStyle);
    final boundaries = <int>{0, layout.text.length};
    for (final range in layout.styles) {
      boundaries
        ..add(range.start)
        ..add(range.end);
    }
    for (final range in layout.colors) {
      boundaries
        ..add(range.start)
        ..add(range.end);
    }
    final offsets = boundaries.toList()..sort();
    final children = <InlineSpan>[];
    var styleIndex = 0;
    var colorIndex = 0;
    for (var index = 0; index + 1 < offsets.length; index++) {
      final start = offsets[index];
      final end = offsets[index + 1];
      if (end <= start) continue;
      while (styleIndex < layout.styles.length &&
          layout.styles[styleIndex].end <= start) {
        styleIndex++;
      }
      while (colorIndex < layout.colors.length &&
          layout.colors[colorIndex].end <= start) {
        colorIndex++;
      }
      final markdownStyle = styleIndex < layout.styles.length &&
              layout.styles[styleIndex].start <= start &&
              layout.styles[styleIndex].end >= end
          ? layout.styles[styleIndex].style
          : null;
      final colorRange = colorIndex < layout.colors.length &&
              layout.colors[colorIndex].start <= start &&
              layout.colors[colorIndex].end >= end
          ? layout.colors[colorIndex]
          : null;
      var style = _applyMarkdownTextStyle(
        context: context,
        baseStyle: baseStyle,
        markdownStyle: markdownStyle,
      );
      if (colorRange != null) {
        style = style.copyWith(color: _colorFromHex(colorRange.hexColor));
      }
      children.add(
        TextSpan(text: layout.text.substring(start, end), style: style),
      );
    }
    return TextSpan(style: baseStyle, children: children);
  }

  static TextStyle _applyMarkdownTextStyle({
    required BuildContext context,
    required TextStyle baseStyle,
    required MarkdownTextStyle? markdownStyle,
  }) {
    if (markdownStyle == null) return baseStyle;
    final theme = Theme.of(context);
    final headingScale = switch (markdownStyle.headingLevel) {
      1 => 1.7,
      2 => 1.45,
      3 => 1.28,
      4 => 1.16,
      5 => 1.08,
      6 => 1.0,
      _ => 1.0,
    };
    final decorations = <TextDecoration>[
      if (markdownStyle.link) TextDecoration.underline,
      if (markdownStyle.strikethrough) TextDecoration.lineThrough,
    ];
    return baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 16) * headingScale,
      fontWeight: markdownStyle.bold || markdownStyle.headingLevel != null
          ? FontWeight.w700
          : baseStyle.fontWeight,
      fontStyle: markdownStyle.italic || markdownStyle.quote
          ? FontStyle.italic
          : baseStyle.fontStyle,
      fontFamily: markdownStyle.code ? 'monospace' : baseStyle.fontFamily,
      color: markdownStyle.link
          ? theme.colorScheme.primary
          : markdownStyle.quote
          ? theme.colorScheme.onSurfaceVariant
          : baseStyle.color,
      backgroundColor: markdownStyle.code
          ? theme.colorScheme.surfaceContainerHighest
          : baseStyle.backgroundColor,
      decoration: decorations.isEmpty
          ? baseStyle.decoration
          : TextDecoration.combine(decorations),
    );
  }

  static Color _colorFromHex(String value) => Color(
    0xff000000 | int.parse(value.substring(1), radix: 16),
  );
}
