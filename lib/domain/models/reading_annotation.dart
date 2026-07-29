enum AnnotationColor { yellow, green, blue, pink }

extension AnnotationColorLabel on AnnotationColor {
  String get label => switch (this) {
    AnnotationColor.yellow => '黄色',
    AnnotationColor.green => '绿色',
    AnnotationColor.blue => '蓝色',
    AnnotationColor.pink => '粉色',
  };
}

class ReadingAnnotation {
  const ReadingAnnotation({
    required this.id,
    required this.bookId,
    required this.href,
    required this.locator,
    required this.selectedText,
    required this.color,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String bookId;
  final String href;
  final String locator;
  final String selectedText;
  final String? note;
  final AnnotationColor color;
  final DateTime createdAt;
}
