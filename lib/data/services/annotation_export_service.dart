import 'dart:convert';

import '../../domain/models/annotation_query.dart';
import '../repositories/annotation_repository.dart';

class AnnotationExportService {
  const AnnotationExportService(this._repository);

  final AnnotationRepository _repository;

  Future<String> buildMarkdown(AnnotationQuery query) async {
    final items = await _repository.query(query.copyWith(limit: 500));
    final buffer = StringBuffer('# TomoRead 阅读笔记\n\n');
    String? activeBookId;
    for (final item in items) {
      final annotation = item.annotation;
      if (activeBookId != annotation.bookId) {
        activeBookId = annotation.bookId;
        buffer
          ..writeln('## ${item.book?.title ?? '已移除的书籍'}')
          ..writeln();
      }
      buffer
        ..writeln('> ${annotation.selectedText.replaceAll('\n', '\n> ')}')
        ..writeln();
      if (annotation.note != null) {
        buffer
          ..writeln(annotation.note)
          ..writeln();
      }
      final metadata = <String>[
        'style: ${annotation.renderStyle.name}',
        if (annotation.chapterTitle != null) annotation.chapterTitle!,
        if (annotation.tags.isNotEmpty)
          annotation.tags.map((tag) => '#$tag').join(' '),
        _formatDate(annotation.createdAt),
      ];
      buffer
        ..writeln('_${metadata.join(' · ')}_')
        ..writeln();
    }
    return buffer.toString();
  }

  Future<String> buildJson(AnnotationQuery query) async {
    final items = await _repository.query(query.copyWith(limit: 500));
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'annotations': items
          .map(
            (item) => {
              'id': item.annotation.id,
              'bookId': item.annotation.bookId,
              'bookTitle': item.book?.title,
              'href': item.annotation.href,
              'locator': item.annotation.locator,
              'chapterIndex': item.annotation.chapterIndex,
              'chapterTitle': item.annotation.chapterTitle,
              'selectedText': item.annotation.selectedText,
              'note': item.annotation.note,
              'color': item.annotation.color.name,
              'style': item.annotation.renderStyle.name,
              'tags': item.annotation.tags,
              'createdAt': item.annotation.createdAt.toUtc().toIso8601String(),
              'updatedAt': item.annotation.updatedAt.toUtc().toIso8601String(),
            },
          )
          .toList(),
    });
  }
}

String _formatDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
