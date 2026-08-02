import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/annotation_query.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
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
    final tags = await _loadTags(
      database,
      rows.map((row) => row['id']! as String),
    );
    return rows
        .map((row) => _fromRow(row, tags[row['id']] ?? const []))
        .toList();
  }

  Future<List<AnnotationListItem>> query(AnnotationQuery query) async {
    final database = await _database.database;
    final where = <String>[];
    final arguments = <Object?>[];
    final normalizedText = query.text.trim().toLowerCase();
    if (normalizedText.isNotEmpty) {
      where.add('''
        (LOWER(a.selected_text) LIKE ? ESCAPE '\\'
          OR LOWER(COALESCE(a.note, '')) LIKE ? ESCAPE '\\'
          OR LOWER(b.title) LIKE ? ESCAPE '\\'
          OR LOWER(b.author) LIKE ? ESCAPE '\\')
      ''');
      final value = '%${_escapeLike(normalizedText)}%';
      arguments.addAll([value, value, value, value]);
    }
    if (query.bookId != null) {
      where.add('a.book_id = ?');
      arguments.add(query.bookId);
    }
    if (query.colors.isNotEmpty) {
      where.add(
        'a.color IN (${List.filled(query.colors.length, '?').join(', ')})',
      );
      arguments.addAll(query.colors.map((color) => color.name));
    }
    if (query.hasNote != null) {
      where.add(
        query.hasNote!
            ? "a.note IS NOT NULL AND TRIM(a.note) <> ''"
            : "(a.note IS NULL OR TRIM(a.note) = '')",
      );
    }
    for (final tag in query.tags) {
      where.add('''
        EXISTS (
          SELECT 1 FROM annotation_tags at
          WHERE at.annotation_id = a.id AND at.normalized_tag = ?
        )
      ''');
      arguments.add(_normalizeTag(tag));
    }
    final orderBy = switch (query.sort) {
      AnnotationSort.newest => 'a.created_at DESC, a.id DESC',
      AnnotationSort.oldest => 'a.created_at ASC, a.id ASC',
      AnnotationSort.recentlyEdited =>
        'COALESCE(a.updated_at, a.created_at) DESC, a.id DESC',
    };
    arguments.add(query.limit.clamp(1, 500));
    final rows = await database.rawQuery('''
      SELECT a.*
      FROM reading_annotations a
      INNER JOIN books b ON b.id = a.book_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY $orderBy
      LIMIT ?
    ''', arguments);
    if (rows.isEmpty) return const [];

    final annotationIds = rows.map((row) => row['id']! as String).toList();
    final tags = await _loadTags(database, annotationIds);
    final bookIds = rows
        .map((row) => row['book_id']! as String)
        .toSet()
        .toList();
    final books = await _loadBooks(database, bookIds);
    return rows
        .map(
          (row) => AnnotationListItem(
            annotation: _fromRow(row, tags[row['id']! as String] ?? const []),
            book: books[row['book_id']! as String],
          ),
        )
        .toList();
  }

  Future<AnnotationFacets> loadFacets() async {
    final database = await _database.database;
    final counts = await database.rawQuery('''
      SELECT COUNT(*) AS total_count,
        SUM(CASE WHEN note IS NOT NULL AND TRIM(note) <> '' THEN 1 ELSE 0 END)
          AS note_count
      FROM reading_annotations
    ''');
    final tagRows = await database.rawQuery('''
      SELECT display_tag, COUNT(*) AS usage_count
      FROM annotation_tags
      GROUP BY normalized_tag, display_tag
      ORDER BY usage_count DESC, display_tag ASC
      LIMIT 50
    ''');
    final row = counts.single;
    return AnnotationFacets(
      totalCount: row['total_count'] as int? ?? 0,
      noteCount: row['note_count'] as int? ?? 0,
      tags: tagRows.map((value) => value['display_tag']! as String).toList(),
    );
  }

  Future<ReadingAnnotation> add({
    required String bookId,
    required String href,
    required String locator,
    required String selectedText,
    required AnnotationColor color,
    AnnotationRenderStyle renderStyle = AnnotationRenderStyle.highlight,
    String? note,
    int? chapterIndex,
    String? chapterTitle,
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final annotation = ReadingAnnotation(
      id: 'annotation-${now.microsecondsSinceEpoch}-$bookId',
      bookId: bookId,
      href: href,
      locator: locator,
      selectedText: selectedText,
      note: _normalizeNote(note),
      color: color,
      renderStyle: renderStyle,
      createdAt: now,
      updatedAt: now,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      tags: _prepareTags(tags).map((entry) => entry.$2).toList(),
    );
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.insert('reading_annotations', {
        'id': annotation.id,
        'book_id': annotation.bookId,
        'href': annotation.href,
        'locator': annotation.locator,
        'selected_text': annotation.selectedText,
        'note': annotation.note,
        'color': annotation.color.name,
        'render_style': annotation.renderStyle.name,
        'created_at': annotation.createdAt.millisecondsSinceEpoch,
        'updated_at': annotation.updatedAt.millisecondsSinceEpoch,
        'chapter_index': annotation.chapterIndex,
        'chapter_title': annotation.chapterTitle,
      });
      await _replaceTags(transaction, annotation.id, tags, now);
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

  Future<void> updateNote(String annotationId, String? note) async {
    final database = await _database.database;
    await database.update(
      'reading_annotations',
      {
        'note': _normalizeNote(note),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [annotationId],
    );
  }

  Future<void> replaceTags(String annotationId, List<String> tags) async {
    final database = await _database.database;
    final now = DateTime.now();
    await database.transaction((transaction) async {
      await _replaceTags(transaction, annotationId, tags, now);
      await transaction.update(
        'reading_annotations',
        {'updated_at': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [annotationId],
      );
    });
  }

  Future<void> updateLocationMetadata({
    required String annotationId,
    required int chapterIndex,
    required String chapterTitle,
  }) async {
    final database = await _database.database;
    await database.update(
      'reading_annotations',
      {
        'chapter_index': chapterIndex,
        'chapter_title': chapterTitle,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [annotationId],
    );
  }

  Future<Map<String, List<String>>> _loadTags(
    DatabaseExecutor database,
    Iterable<String> annotationIds,
  ) async {
    final ids = annotationIds.toList(growable: false);
    if (ids.isEmpty) return const {};
    final rows = await database.rawQuery('''
        SELECT annotation_id, display_tag
        FROM annotation_tags
        WHERE annotation_id IN (${List.filled(ids.length, '?').join(', ')})
        ORDER BY display_tag ASC
      ''', ids);
    final result = <String, List<String>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['annotation_id']! as String, () => <String>[])
          .add(row['display_tag']! as String);
    }
    return result;
  }

  Future<Map<String, LibraryBook>> _loadBooks(
    DatabaseExecutor database,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final rows = await database.query(
      'books',
      where: 'id IN (${List.filled(ids.length, '?').join(', ')})',
      whereArgs: ids,
    );
    return {for (final row in rows) row['id']! as String: _bookFromRow(row)};
  }

  Future<void> _replaceTags(
    DatabaseExecutor database,
    String annotationId,
    List<String> tags,
    DateTime now,
  ) async {
    await database.delete(
      'annotation_tags',
      where: 'annotation_id = ?',
      whereArgs: [annotationId],
    );
    for (final entry in _prepareTags(tags)) {
      await database.insert('annotation_tags', {
        'annotation_id': annotationId,
        'normalized_tag': entry.$1,
        'display_tag': entry.$2,
        'created_at': now.millisecondsSinceEpoch,
      });
    }
  }

  List<(String, String)> _prepareTags(List<String> tags) {
    final result = <String, String>{};
    for (final rawTag in tags.take(12)) {
      final display = rawTag.trim();
      if (display.isEmpty || display.length > 32) continue;
      result.putIfAbsent(_normalizeTag(display), () => display);
    }
    return result.entries.map((entry) => (entry.key, entry.value)).toList();
  }

  String _normalizeTag(String value) => value.trim().toLowerCase();
  String? _normalizeNote(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  ReadingAnnotation _fromRow(Map<String, Object?> row, List<String> tags) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      row['created_at']! as int,
    );
    return ReadingAnnotation(
      id: row['id']! as String,
      bookId: row['book_id']! as String,
      href: row['href']! as String,
      locator: row['locator']! as String,
      selectedText: row['selected_text']! as String,
      note: row['note'] as String?,
      color: AnnotationColor.values.byName(row['color']! as String),
      renderStyle: AnnotationRenderStyle.values.byName(
        row['render_style'] as String? ?? AnnotationRenderStyle.highlight.name,
      ),
      createdAt: createdAt,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int? ?? row['created_at']! as int,
      ),
      chapterIndex: row['chapter_index'] as int?,
      chapterTitle: row['chapter_title'] as String?,
      tags: tags,
    );
  }

  LibraryBook _bookFromRow(Map<String, Object?> row) => LibraryBook(
    id: row['id']! as String,
    fileHash: row['file_hash'] as String? ?? row['id']! as String,
    title: row['title']! as String,
    author: row['author']! as String,
    filePath: row['file_path'] as String? ?? '',
    coverPath: row['cover_path'] as String?,
    description: row['description'] as String?,
    category: row['category'] as String?,
    tags: _bookTags(row['tags_json']),
    isFavorite: (row['is_favorite'] as int? ?? 0) == 1,
    progress: (row['progress']! as num).toDouble(),
    importedAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    format: row['format'] as String? ?? 'epub',
    chapterCount: row['chapter_count'] as int? ?? 0,
    chapterIndex: row['chapter_index'] as int? ?? 0,
    locator: row['locator'] as String?,
    direction: ReadingDirection.values.byName(
      row['read_direction'] as String? ?? ReadingDirection.ltr.name,
    ),
  );

  List<String> _bookTags(Object? source) {
    if (source is! String || source.isEmpty) return const [];
    try {
      return (jsonDecode(source) as List<Object?>).whereType<String>().toList();
    } on Object {
      return const [];
    }
  }
}
