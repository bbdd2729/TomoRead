class ReaderTextSelection {
  const ReaderTextSelection({
    required this.href,
    required this.text,
    required this.startOffset,
    required this.endOffset,
    this.cfi,
  });

  final String href;
  final String text;
  final int startOffset;
  final int endOffset;
  final String? cfi;

  String get locator => cfi == null ? '$startOffset:$endOffset' : 'cfi:$cfi';
}

class ReaderSelectionContextMenu {
  const ReaderSelectionContextMenu({
    required this.selection,
    required this.x,
    required this.y,
  });

  final ReaderTextSelection selection;
  final double x;
  final double y;
}
