import 'package:file_picker/file_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/reading_font.dart';

class FontCatalogState {
  const FontCatalogState({
    required this.systemFonts,
    required this.importedFonts,
  });

  final List<SystemFontFamily> systemFonts;
  final List<ImportedFont> importedFonts;
}

final fontCatalogControllerProvider =
    AsyncNotifierProvider<FontCatalogController, FontCatalogState>(
      FontCatalogController.new,
    );

class FontCatalogController extends AsyncNotifier<FontCatalogState> {
  @override
  Future<FontCatalogState> build() async {
    final results = await Future.wait<Object>([
      ref.watch(fontCatalogServiceProvider).listSystemFonts(),
      ref.watch(fontRepositoryProvider).listImported(),
    ]);
    return FontCatalogState(
      systemFonts: results[0] as List<SystemFontFamily>,
      importedFonts: results[1] as List<ImportedFont>,
    );
  }

  Future<ImportedFont?> importFromPicker({String? licenseLabel}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf', 'woff', 'woff2'],
      allowMultiple: false,
      withData: false,
    );
    final filePath = result?.files.single.path;
    if (filePath == null) return null;
    final font = await ref
        .read(fontRepositoryProvider)
        .importFile(filePath, licenseLabel: licenseLabel);
    ref.invalidateSelf();
    return font;
  }

  Future<void> delete(
    String fontId, {
    ReadingFontRef? replacement,
  }) async {
    await ref
        .read(fontRepositoryProvider)
        .delete(fontId, replacement: replacement);
    ref.invalidateSelf();
    ref.invalidate(appSettingsProvider);
  }
}
