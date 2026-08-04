import 'package:flutter/material.dart';

import '../../domain/models/reading_annotation.dart';

enum ReaderSelectionContextAction {
  yellow,
  green,
  blue,
  pink,
  underline,
  note,
  textColor,
  askAi,
  explainAi,
  summarizeAi,
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
