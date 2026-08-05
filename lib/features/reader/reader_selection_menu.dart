import 'package:flutter/material.dart';

import '../../domain/models/reading_annotation.dart';

enum ReaderSelectionContextAction { highlight, underline, note, textColor, ai }

enum ReaderSelectionAiAction { ask, explain, summarize }

class ReaderSelectionActionMenuItem extends StatelessWidget {
  const ReaderSelectionActionMenuItem({
    super.key,
    required this.icon,
    required this.label,
    this.hasSubmenu = false,
  });

  final IconData icon;
  final String label;
  final bool hasSubmenu;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 168,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (hasSubmenu) const Icon(Icons.chevron_right, size: 20),
      ],
    ),
  );
}

class ReaderSelectionContextMenuItem extends StatelessWidget {
  const ReaderSelectionContextMenuItem({super.key, required this.color});

  final AnnotationColor color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(Icons.circle, color: _swatch(color), size: 18),
      const SizedBox(width: 12),
      Text('${color.label}高亮'),
    ],
  );

  Color _swatch(AnnotationColor value) => switch (value) {
    AnnotationColor.yellow => Colors.amber,
    AnnotationColor.green => Colors.green,
    AnnotationColor.blue => Colors.lightBlue,
    AnnotationColor.pink => Colors.pink,
  };
}
