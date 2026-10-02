import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/book_import_service.dart';
import 'text_encoding_dialog.dart';

Future<List<BookImportResult>> resolveImportResults(
  BuildContext context,
  WidgetRef ref,
  List<BookImportResult> initialResults,
) async {
  final results = <BookImportResult>[];
  for (final result in initialResults) {
    if (result.status != BookImportStatus.needsEncoding || !context.mounted) {
      results.add(result);
      continue;
    }
    final encoding = await showDialog<String>(
      context: context,
      builder: (context) => TextEncodingDialog(result: result),
    );
    if (encoding == null || !context.mounted) {
      results.add(result);
      continue;
    }
    results.add(
      await ref
          .read(libraryBooksProvider.notifier)
          .importTextWithEncoding(result.sourcePath, encoding),
    );
  }
  return List.unmodifiable(results);
}

void showImportSummary(BuildContext context, List<BookImportResult> results) {
  if (results.isEmpty) return;
  final imported = results
      .where((result) => result.status == BookImportStatus.imported)
      .length;
  final duplicates = results
      .where((result) => result.status == BookImportStatus.duplicate)
      .length;
  final failed = results
      .where((result) => result.status == BookImportStatus.failed)
      .length;
  final pendingEncoding = results
      .where((result) => result.status == BookImportStatus.needsEncoding)
      .length;
  final message = [
    if (imported > 0) '$imported مستورد',
    if (duplicates > 0) '$duplicates موجود بالفعل',
    if (failed > 0) '$failed فشل هذا الاستيراد',
    if (pendingEncoding > 0) '$pendingEncoding في انتظار رمز التأكيد',
  ].join('，');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
