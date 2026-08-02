import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/annotation_repository.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/domain/models/annotation_query.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/reading_annotation.dart';

void main() {
  late AppDatabase database;
  late AnnotationRepository annotations;

  setUp(() async {
    database = AppDatabase.inMemory();
    annotations = AnnotationRepository(database);
    await BookRepository(database).saveImportedPdfBook(_book());
  });

  tearDown(() => database.close());

  test('queries real annotations by note, text, color, and tag', () async {
    await annotations.add(
      bookId: 'book-a',
      href: 'chapter.xhtml',
      locator: 'cfi:/6/2',
      selectedText: '主动阅读需要持续提问',
      color: AnnotationColor.blue,
      note: '联系自己的经验',
      chapterIndex: 2,
      chapterTitle: '第三章',
      tags: const ['方法', '重点'],
    );
    await annotations.add(
      bookId: 'book-a',
      href: 'chapter-2.xhtml',
      locator: 'cfi:/6/4',
      selectedText: '另一个摘录',
      color: AnnotationColor.yellow,
      renderStyle: AnnotationRenderStyle.underline,
    );

    final persisted = await annotations.listForBook('book-a');
    expect(
      persisted.singleWhere((item) => item.locator == 'cfi:/6/4').renderStyle,
      AnnotationRenderStyle.underline,
    );

    final result = await annotations.query(
      const AnnotationQuery(
        text: '经验',
        colors: {AnnotationColor.blue},
        hasNote: true,
        tags: {'方法'},
      ),
    );

    expect(result, hasLength(1));
    expect(result.single.book?.title, '测试书籍');
    expect(result.single.annotation.chapterTitle, '第三章');
    expect(result.single.annotation.tags, containsAll(['方法', '重点']));
  });
}

LibraryBook _book() => LibraryBook(
  id: 'book-a',
  fileHash: 'hash-a',
  title: '测试书籍',
  author: '作者',
  filePath: 'book.pdf',
  progress: 0,
  importedAt: DateTime(2026),
  format: 'pdf',
  chapterCount: 10,
  direction: ReadingDirection.ltr,
);
