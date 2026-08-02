class ImportCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class ImportCancelledException implements Exception {
  const ImportCancelledException();

  @override
  String toString() => 'Import operation cancelled';
}
