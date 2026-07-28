import 'package:flutter/foundation.dart';

import '../../data/repositories/book_repository.dart';
import '../../data/services/book_import_service.dart';
import '../../domain/models/library_book.dart';

class LibraryController extends ChangeNotifier {
  LibraryController({required this.repository, required this.importService});

  final BookRepository repository;
  final BookImportService importService;

  List<LibraryBook> _books = const [];
  List<LibraryBook> get books => _books;
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  bool _isImporting = false;
  bool get isImporting => _isImporting;
  String? _error;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _books = await repository.listBooks();
    } catch (error) {
      _error = '无法读取书库：$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<BookImportResult>> importFromPicker() async {
    _isImporting = true;
    _error = null;
    notifyListeners();
    try {
      final results = await importService.pickAndImportEpubs();
      await _refreshAfterImport(results);
      return results;
    } catch (error) {
      _error = '导入失败：$error';
      return const [];
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> _refreshAfterImport(List<BookImportResult> results) async {
    if (results.any((result) => result.status == BookImportStatus.imported)) {
      _books = await repository.listBooks();
    }
  }
}
