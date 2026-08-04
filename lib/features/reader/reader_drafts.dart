import '../../domain/models/reading_annotation.dart';

/// A reader-position update waiting for the debounced persistence callback.
class PendingReaderProgress {
  const PendingReaderProgress({
    required this.chapterIndex,
    required this.progress,
    required this.locator,
  });

  final int chapterIndex;
  final double progress;
  final String locator;
}

/// The values collected before creating a text annotation.
class AnnotationDraft {
  const AnnotationDraft({required this.color, this.note});

  final AnnotationColor color;
  final String? note;
}

/// The edited note text returned from the annotation note dialog.
class AnnotationNoteDraft {
  const AnnotationNoteDraft(this.note);

  final String note;
}
