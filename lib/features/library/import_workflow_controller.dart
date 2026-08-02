import 'package:flutter/foundation.dart';

import '../../data/services/book_import_service.dart';
import '../../data/services/import_cancellation_token.dart';
import '../../domain/models/book_import.dart';

enum ImportWorkflowPhase {
  idle,
  scanning,
  preview,
  importing,
  completed,
  cancelled,
  failed,
}

class ImportWorkflowState {
  const ImportWorkflowState({
    this.phase = ImportWorkflowPhase.idle,
    this.preview,
    this.results = const [],
    this.completed = 0,
    this.total = 0,
    this.error,
  });

  final ImportWorkflowPhase phase;
  final ImportScanPreview? preview;
  final List<BookImportResult> results;
  final int completed;
  final int total;
  final Object? error;
}

typedef ImportPreviewLoader = Future<ImportScanPreview> Function(
  Iterable<ImportSource> sources,
  ImportCancellationToken cancellationToken,
  void Function(int completed, int total) onProgress,
);

typedef ImportPreviewExecutor = Future<List<BookImportResult>> Function(
  ImportScanPreview preview,
  ImportCancellationToken cancellationToken,
  void Function(int completed, int total) onProgress,
);

class ImportWorkflowController extends ChangeNotifier {
  ImportWorkflowController({
    required this.previewLoader,
    required this.executor,
  });

  factory ImportWorkflowController.forService(BookImportService service) =>
      ImportWorkflowController(
        previewLoader: (sources, token, onProgress) => service.previewSources(
          sources,
          cancellationToken: token,
          onHashProgress: onProgress,
        ),
        executor: (preview, token, onProgress) => service.importPreview(
          preview,
          cancellationToken: token,
          onProgress: onProgress,
        ),
      );

  final ImportPreviewLoader previewLoader;
  final ImportPreviewExecutor executor;
  ImportCancellationToken? _token;
  ImportWorkflowState _state = const ImportWorkflowState();
  bool _disposed = false;

  ImportWorkflowState get state => _state;

  Future<void> prepare(Iterable<ImportSource> sources) async {
    _token?.cancel();
    final token = ImportCancellationToken();
    _token = token;
    _setState(const ImportWorkflowState(phase: ImportWorkflowPhase.scanning));
    try {
      final preview = await previewLoader(sources, token, (completed, total) {
        _setState(
          ImportWorkflowState(
            phase: ImportWorkflowPhase.scanning,
            completed: completed,
            total: total,
          ),
        );
      });
      if (token.isCancelled || preview.cancelled) {
        _setState(
          ImportWorkflowState(
            phase: ImportWorkflowPhase.cancelled,
            preview: preview,
          ),
        );
        return;
      }
      _setState(
        ImportWorkflowState(
          phase: ImportWorkflowPhase.preview,
          preview: preview,
          completed: preview.supportedCount + preview.duplicateCount,
          total: preview.items.length,
        ),
      );
    } on Object catch (error) {
      _setState(
        ImportWorkflowState(
          phase: ImportWorkflowPhase.failed,
          error: error,
        ),
      );
    }
  }

  Future<void> startImport() async {
    final preview = _state.preview;
    if (_state.phase != ImportWorkflowPhase.preview ||
        preview == null ||
        preview.requests.isEmpty) {
      return;
    }
    final token = ImportCancellationToken();
    _token = token;
    _setState(
      ImportWorkflowState(
        phase: ImportWorkflowPhase.importing,
        preview: preview,
        total: preview.requests.length,
      ),
    );
    try {
      final results = await executor(preview, token, (completed, total) {
        _setState(
          ImportWorkflowState(
            phase: ImportWorkflowPhase.importing,
            preview: preview,
            completed: completed,
            total: total,
          ),
        );
      });
      _setState(
        ImportWorkflowState(
          phase: token.isCancelled
              ? ImportWorkflowPhase.cancelled
              : ImportWorkflowPhase.completed,
          preview: preview,
          results: List.unmodifiable(results),
          completed: results.length,
          total: preview.requests.length,
        ),
      );
    } on Object catch (error) {
      _setState(
        ImportWorkflowState(
          phase: ImportWorkflowPhase.failed,
          preview: preview,
          error: error,
        ),
      );
    }
  }

  void cancel() {
    _token?.cancel();
  }

  void reset() {
    _token?.cancel();
    _token = null;
    _setState(const ImportWorkflowState());
  }

  void _setState(ImportWorkflowState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
