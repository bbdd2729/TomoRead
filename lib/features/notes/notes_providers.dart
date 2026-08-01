import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/annotation_export_service.dart';
import '../../data/repositories/annotation_repository.dart';
import '../../domain/models/annotation_query.dart';
import '../../domain/models/reading_annotation.dart';

final annotationQueryProvider =
    NotifierProvider<AnnotationQueryNotifier, AnnotationQuery>(
      AnnotationQueryNotifier.new,
    );

class AnnotationQueryNotifier extends Notifier<AnnotationQuery> {
  @override
  AnnotationQuery build() => const AnnotationQuery();

  void update(AnnotationQuery value) => state = value;
  void reset() => state = const AnnotationQuery();
}

final annotationItemsProvider = FutureProvider<List<AnnotationListItem>>((ref) {
  ref.watch(annotationRevisionProvider);
  final query = ref.watch(annotationQueryProvider);
  return ref.watch(annotationRepositoryProvider).query(query);
});

final annotationFacetsProvider = FutureProvider<AnnotationFacets>((ref) {
  ref.watch(annotationRevisionProvider);
  return ref.watch(annotationRepositoryProvider).loadFacets();
});

final annotationControllerProvider = Provider<AnnotationController>((ref) {
  return AnnotationController(
    repository: ref.watch(annotationRepositoryProvider),
    onChanged: () => ref.read(annotationRevisionProvider.notifier).bump(),
  );
});

final annotationExportServiceProvider = Provider<AnnotationExportService>(
  (ref) => AnnotationExportService(ref.watch(annotationRepositoryProvider)),
);

class AnnotationController {
  const AnnotationController({
    required this.repository,
    required this.onChanged,
  });

  final AnnotationRepository repository;
  final void Function() onChanged;

  Future<ReadingAnnotation> add({
    required String bookId,
    required String href,
    required String locator,
    required String selectedText,
    required AnnotationColor color,
    String? note,
    int? chapterIndex,
    String? chapterTitle,
  }) async {
    final result = await repository.add(
      bookId: bookId,
      href: href,
      locator: locator,
      selectedText: selectedText,
      color: color,
      note: note,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
    );
    onChanged();
    return result;
  }

  Future<void> updateNote(String id, String? note) async {
    await repository.updateNote(id, note);
    onChanged();
  }

  Future<void> replaceTags(String id, List<String> tags) async {
    await repository.replaceTags(id, tags);
    onChanged();
  }

  Future<void> remove(String id) async {
    await repository.remove(id);
    onChanged();
  }
}
