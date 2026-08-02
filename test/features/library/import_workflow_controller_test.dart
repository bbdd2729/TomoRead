import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/book_import_service.dart';
import 'package:tomoread/domain/models/book_import.dart';
import 'package:tomoread/features/library/import_workflow_controller.dart';

void main() {
  const source = ImportSource(
    kind: ImportSourceKind.desktopDrop,
    location: 'book.epub',
  );
  const request = BookImportRequest(
    source: source,
    sourcePath: 'book.epub',
    sizeBytes: 128,
  );
  const preview = ImportScanPreview(
    items: [
      ImportScanItem(
        source: source,
        disposition: ImportScanDisposition.supported,
        request: request,
      ),
    ],
    totalBytes: 128,
  );

  group('ImportWorkflowController', () {
    test('moves from preview to completed import with progress', () async {
      final phases = <ImportWorkflowPhase>[];
      final controller = ImportWorkflowController(
        previewLoader: (sources, token, onProgress) async {
          onProgress(1, 1);
          return preview;
        },
        executor: (preview, token, onProgress) async {
          onProgress(1, 1);
          return [BookImportResult.failed('book.epub', 'bad fixture')];
        },
      );
      controller.addListener(() => phases.add(controller.state.phase));
      addTearDown(controller.dispose);

      await controller.prepare(const [source]);
      expect(controller.state.phase, ImportWorkflowPhase.preview);
      await controller.startImport();

      expect(controller.state.phase, ImportWorkflowPhase.completed);
      expect(controller.state.completed, 1);
      expect(
        phases,
        containsAllInOrder([
          ImportWorkflowPhase.scanning,
          ImportWorkflowPhase.preview,
          ImportWorkflowPhase.importing,
          ImportWorkflowPhase.completed,
        ]),
      );
    });

    test('cancels a pending scan without exposing an import action', () async {
      final gate = Completer<void>();
      final controller = ImportWorkflowController(
        previewLoader: (sources, token, onProgress) async {
          await gate.future;
          return ImportScanPreview(
            items: const [],
            totalBytes: 0,
            cancelled: token.isCancelled,
          );
        },
        executor: (preview, token, onProgress) async => const [],
      );
      addTearDown(controller.dispose);

      final pending = controller.prepare(const [source]);
      controller.cancel();
      gate.complete();
      await pending;

      expect(controller.state.phase, ImportWorkflowPhase.cancelled);
      expect(controller.state.preview?.requests, isEmpty);
    });
  });
}
