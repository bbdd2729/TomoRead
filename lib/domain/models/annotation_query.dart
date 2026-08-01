import 'library_book.dart';
import 'reading_annotation.dart';

enum AnnotationSort { newest, oldest, recentlyEdited }

class AnnotationQuery {
  const AnnotationQuery({
    this.text = '',
    this.bookId,
    this.colors = const {},
    this.hasNote,
    this.tags = const {},
    this.sort = AnnotationSort.newest,
    this.limit = 100,
  });

  final String text;
  final String? bookId;
  final Set<AnnotationColor> colors;
  final bool? hasNote;
  final Set<String> tags;
  final AnnotationSort sort;
  final int limit;

  AnnotationQuery copyWith({
    String? text,
    String? bookId,
    Set<AnnotationColor>? colors,
    bool? hasNote,
    bool clearHasNote = false,
    Set<String>? tags,
    AnnotationSort? sort,
    int? limit,
    bool clearBook = false,
  }) => AnnotationQuery(
    text: text ?? this.text,
    bookId: clearBook ? null : bookId ?? this.bookId,
    colors: colors ?? this.colors,
    hasNote: clearHasNote ? null : hasNote ?? this.hasNote,
    tags: tags ?? this.tags,
    sort: sort ?? this.sort,
    limit: limit ?? this.limit,
  );
}

class AnnotationListItem {
  const AnnotationListItem({required this.annotation, required this.book});

  final ReadingAnnotation annotation;
  final LibraryBook? book;
}

class AnnotationFacets {
  const AnnotationFacets({
    required this.totalCount,
    required this.noteCount,
    required this.tags,
  });

  final int totalCount;
  final int noteCount;
  final List<String> tags;
}
