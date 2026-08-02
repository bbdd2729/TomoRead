import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/book_import_service.dart';
import 'package:tomoread/domain/models/book_import.dart';
import 'package:tomoread/features/library/book_import_preview_dialog.dart';
import 'package:tomoread/features/library/import_workflow_controller.dart';

void main() {
  const source = ImportSource(
    kind: ImportSourceKind.directoryPicker,
    location: 'books/book.epub',
    displayName: 'book.epub',
  );
  const preview = ImportScanPreview(
    items: [
      ImportScanItem(
        source: source,
        disposition: ImportScanDisposition.supported,
        request: BookImportRequest(
          source: source,
          sourcePath: 'books/book.epub',
          sizeBytes: 100,
        ),
      ),
      ImportScanItem(
        source: ImportSource(
          kind: ImportSourceKind.directoryPicker,
          location: 'books/cover.jpg',
          displayName: 'cover.jpg',
        ),
        disposition: ImportScanDisposition.skipped,
        reason: '不支持的文件格式',
      ),
    ],
    totalBytes: 100,
  );

  testWidgets('shows preview reasons and imports only after confirmation', (
    tester,
  ) async {
    var executions = 0;
    final controller = ImportWorkflowController(
      previewLoader: (sources, token, onProgress) async => preview,
      executor: (preview, token, onProgress) async {
        executions++;
        onProgress(1, 1);
        return [BookImportResult.failed('book.epub', 'fixture failure')];
      },
    );
    addTearDown(controller.dispose);
    await controller.prepare(const [source]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BookImportPreviewDialog(controller: controller)),
      ),
    );

    expect(find.text('确认导入内容'), findsOneWidget);
    expect(find.text('可导入 1'), findsOneWidget);
    expect(find.text('已跳过 1'), findsOneWidget);
    expect(find.text('不支持的文件格式'), findsOneWidget);
    expect(executions, 0);

    await tester.tap(find.text('开始导入 1 本'));
    await tester.pump();
    await tester.pump();

    expect(executions, 1);
    expect(find.text('导入完成'), findsOneWidget);
    expect(find.text('已导入 0'), findsOneWidget);
  });
}
