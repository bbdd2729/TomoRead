class ReaderTextSelection {
  const ReaderTextSelection({
    required this.href,
    required this.text,
    required this.startOffset,
    required this.endOffset,
  });

  final String href;
  final String text;
  final int startOffset;
  final int endOffset;

  String get locator => '$startOffset:$endOffset';
}
