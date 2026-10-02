import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/embedding_models.dart';
import '../assistant/semantic_index_controller.dart';

class ContentSearchDialog extends HookConsumerWidget {
  const ContentSearchDialog({
    super.key,
    required this.bookId,
    required this.maxChapterIndex,
    required this.maxRawOffset,
  });

  final String bookId;
  final int? maxChapterIndex;
  final int? maxRawOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = useState('');
    final query = useState('');
    final includeFutureChapters = useState(false);
    useEffect(() {
      final timer = Timer(const Duration(milliseconds: 350), () {
        query.value = draft.value.trim();
      });
      return timer.cancel;
    }, [draft.value]);
    final activeProfile = ref.watch(activeEmbeddingProfileProvider);
    final effectiveMaxChapter = includeFutureChapters.value
        ? null
        : maxChapterIndex == null || maxRawOffset != null
        ? maxChapterIndex
        : maxChapterIndex! - 1;
    final request = (
      bookId: bookId,
      query: query.value,
      maxChapterIndex: effectiveMaxChapter,
      maxRawOffset: includeFutureChapters.value ? null : maxRawOffset,
      limit: 50,
    );
    final response = ref.watch(hybridSearchProvider(request));
    final profile = activeProfile.value;
    final semanticState = profile == null
        ? null
        : ref.watch(
            semanticIndexStateProvider((
              bookId: bookId,
              profileId: profile.id,
            )),
          );
    final screenSize = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text('البحث في فهرس الجسم المحلي'),
      content: SizedBox(
        width: (screenSize.width - 48).clamp(280, 700).toDouble(),
        height: (screenSize.height - 220).clamp(220, 580).toDouble(),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'أدخل الكلمات الرئيسية أو العبارات أو أسئلة اللغة الطبيعية',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => draft.value = value,
              onSubmitted: (value) => query.value = value.trim(),
            ),
            if (maxChapterIndex != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: includeFutureChapters.value,
                onChanged: (value) => includeFutureChapters.value = value,
                title: const Text('قم بتضمين الفصول التي لم تقرأها بعد'),
                subtitle: const Text('قم بإيقاف التشغيل افتراضيًا لتجنب المفسدين في نتائج البحث.'),
              ),
            _SemanticIndexBanner(
              bookId: bookId,
              profile: profile,
              state: semanticState,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: query.value.isEmpty
                  ? const Center(
                      child: Text('عمليات البحث عن الكلمات الرئيسية متاحة دائمًا ؛ يجب تكوين عمليات البحث الدلالية وفهرستها أولاً.'),
                    )
                  : response.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, _) => Center(
                        child: Text('فشل البحث: $error'),
                      ),
                      data: (value) => value.results.isEmpty
                          ? const Center(child: Text('لم يتم العثور على تطابقات.'))
                          : Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(_modeDescription(value)),
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: value.results.length,
                                    itemBuilder: (context, index) {
                                      final result = value.results[index];
                                      return ListTile(
                                        title: Text(result.chapterTitle),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              result.excerpt,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 6,
                                              children: [
                                                if (result.sources.contains(
                                                  HybridMatchSource.keyword,
                                                ))
                                                  const Chip(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    label: Text('الكلمات الأساسية'),
                                                  ),
                                                if (result.sources.contains(
                                                  HybridMatchSource.semantic,
                                                ))
                                                  const Chip(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    label: Text('علم الدلالة'),
                                                  ),
                                                Text(
                                                  'الملاءمة${(result.score * 100).round()}%',
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        onTap: () =>
                                            Navigator.pop(context, result),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('مغلق'),
        ),
      ],
    );
  }
}

class _SemanticIndexBanner extends ConsumerWidget {
  const _SemanticIndexBanner({
    required this.bookId,
    required this.profile,
    required this.state,
  });

  final String bookId;
  final EmbeddingProviderProfile? profile;
  final AsyncValue<SemanticIndexState?>? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentProfile = profile;
    if (currentProfile == null) {
      return const _IndexMessage(
        icon: Icons.info_outline,
        text: 'لم يتم تمكين تكوين المتجه، يتم استخدام البحث عن الكلمات الرئيسية حاليًا.',
      );
    }
    if (currentProfile.capabilityStatus != EmbeddingCapabilityStatus.ready) {
      return const _IndexMessage(
        icon: Icons.warning_amber_outlined,
        text: 'لم يجتاز تكوين المتجه الحالي اختبار التضمين، ولا يزال البحث عن الكلمات الرئيسية متاحًا.',
      );
    }
    if (!currentProfile.canSendContent) {
      return const _IndexMessage(
        icon: Icons.privacy_tip_outlined,
        text: 'لم يتم السماح بإرسال النص إلى هذه الخدمة البعيدة، حاليًا باستخدام البحث عن الكلمات الرئيسية.',
      );
    }
    return state?.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => _IndexMessage(
            icon: Icons.warning_amber_outlined,
            text: 'تعذر قراءة حالة الفهرس الدلالي: $error',
          ),
          data: (index) {
            final controller = ref.read(semanticIndexControllerProvider);
            final indexing =
                index?.status == SemanticIndexStatus.indexing &&
                controller.isRunning(bookId);
            final ready = index?.status == SemanticIndexStatus.ready;
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ready
                            ? 'الفهرسة الدلالية جاهزة:${index!.indexedChunks}شظايا الجسم'
                            : indexing
                            ? 'إنشاء فهرس دلالي:${(index!.progress * 100).round()}%'
                            : 'الفهرس الدلالي غير جاهز، ويتم تخفيض مستوى البحث الحالي تلقائيًا إلى وضع الكلمات الرئيسية.',
                      ),
                    ),
                    if (indexing)
                      TextButton(
                        onPressed: () => ref
                            .read(semanticIndexControllerProvider)
                            .cancel(bookId),
                        child: const Text('إلغاء'),
                      )
                    else ...[
                      TextButton(
                        onPressed: () => _buildIndex(
                          context,
                          ref,
                          rebuild: ready,
                        ),
                        child: Text(ready ? '`7` إعادة الإعمار' : 'الفهرسة'),
                      ),
                      if (index != null)
                        IconButton(
                          tooltip: 'حذف فهرس المتجهات للكتاب الحالي',
                          onPressed: () => ref
                              .read(semanticIndexControllerProvider)
                              .deleteIndex(bookId),
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        ) ??
        const SizedBox.shrink();
  }

  Future<void> _buildIndex(
    BuildContext context,
    WidgetRef ref, {
    required bool rebuild,
  }) async {
    try {
      final controller = ref.read(semanticIndexControllerProvider);
      if (rebuild) {
        await controller.rebuildBook(bookId);
      } else {
        await controller.indexBook(bookId);
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إنشاء فهرس دلالي: $error')),
        );
      }
    }
  }
}

class _IndexMessage extends StatelessWidget {
  const _IndexMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

String _modeDescription(HybridSearchResponse response) {
  if (response.mode == SemanticSearchMode.hybrid) {
    return response.spoilerLimited
        ? 'استرجاع هجين · يقتصر على تقدم القراءة الحالية'
        : 'استرجاع هجين · يتضمن أقسام الموسوعة';
  }
  final reason = response.semanticStatusCode == null
      ? ''
      : '（${response.semanticStatusCode}）';
  return 'استرجاع الكلمات الرئيسية · الاسترجاع الدلالي غير متاح مؤقتًا $reason';
}
