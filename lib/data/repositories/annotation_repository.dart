import '../../domain/models/reading_annotation.dart';
import '../database/app_database.dart';

class AnnotationRepository {
  AnnotationRepository(this._database);

  final AppDatabase _database;

  Future<List<ReadingAnnotation>> listForBook(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'reading_annotations',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<ReadingAnnotation> add({
    required String bookId,
    required String href,
    required String locator,
    required String selectedText,
    required AnnotationColor color,
    String? note,
  }) async {
    final annotation = ReadingAnnotation(
      id: 'annotation-${DateTime.now().microsecondsSinceEpoch}-$bookId',
      bookId: bookId,
      href: href,
      locator: locator,
      selectedText: selectedText,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      color: color,
      createdAt: DateTime.now(),
    );
    final database = await _database.database;
    await database.insert('reading_annotations', {
      'id': annotation.id,
      'book_id': annotation.bookId,
      'href': annotation.href,
      'locator': annotation.locator,
      'selected_text': annotation.selectedText,
      'note': annotation.note,
      'color': annotation.color.name,
      'created_at': annotation.createdAt.millisecondsSinceEpoch,
    });
    return annotation;
  }

  Future<void> remove(String annotationId) async {
    final database = await _database.database;
    await database.delete(
      'reading_annotations',
      where: 'id = ?',
      whereArgs: [annotationId],
    );
  }

  ReadingAnnotation _fromRow(Map<String, Object?> row) => ReadingAnnotation(
    id: row['id']! as String,
    bookId: row['book_id']! as String,
    href: row['href']! as String,
    locator: row['locator']! as String,
    selectedText: row['selected_text']! as String,
    note: row['note'] as String?,
    color: AnnotationColor.values.byName(row['color']! as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );
}
