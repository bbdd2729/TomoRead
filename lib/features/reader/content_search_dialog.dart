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
      title: const Text('搜索本地正文索引'),
      content: SizedBox(
        width: (screenSize.width - 48).clamp(280, 700).toDouble(),
        height: (screenSize.height - 220).clamp(220, 580).toDouble(),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '输入关键词、短语或自然语言问题',
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
                title: const Text('包含尚未读到的章节'),
                subtitle: const Text('默认关闭以避免搜索结果剧透。'),
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
                      child: Text('关键词搜索始终可用；语义搜索需要先配置并建立向量索引。'),
                    )
                  : response.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, _) => Center(
                        child: Text('搜索失败：$error'),
                      ),
                      data: (value) => value.results.isEmpty
                          ? const Center(child: Text('没有找到匹配内容。'))
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
                                                    label: Text('关键词'),
                                                  ),
                                                if (result.sources.contains(
                                                  HybridMatchSource.semantic,
                                                ))
                                                  const Chip(
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    label: Text('语义'),
                                                  ),
                                                Text(
                                                  '相关度 ${(result.score * 100).round()}%',
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
          child: const Text('关闭'),
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
        text: '未启用向量配置，当前使用关键词搜索。',
      );
    }
    if (currentProfile.capabilityStatus != EmbeddingCapabilityStatus.ready) {
      return const _IndexMessage(
        icon: Icons.warning_amber_outlined,
        text: '当前向量配置尚未通过 Embedding 测试，关键词搜索仍可用。',
      );
    }
    if (!currentProfile.canSendContent) {
      return const _IndexMessage(
        icon: Icons.privacy_tip_outlined,
        text: '尚未允许向该远端服务发送正文，当前使用关键词搜索。',
      );
    }
    return state?.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => _IndexMessage(
            icon: Icons.warning_amber_outlined,
            text: '无法读取语义索引状态：$error',
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
                            ? '语义索引已就绪：${index!.indexedChunks} 个正文片段'
                            : indexing
                            ? '正在建立语义索引：${(index!.progress * 100).round()}%'
                            : '语义索引未就绪，当前搜索自动降级为关键词模式。',
                      ),
                    ),
                    if (indexing)
                      TextButton(
                        onPressed: () => ref
                            .read(semanticIndexControllerProvider)
                            .cancel(bookId),
                        child: const Text('取消'),
                      )
                    else ...[
                      TextButton(
                        onPressed: () => _buildIndex(
                          context,
                          ref,
                          rebuild: ready,
                        ),
                        child: Text(ready ? '重建' : '建立索引'),
                      ),
                      if (index != null)
                        IconButton(
                          tooltip: '删除当前书的向量索引',
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
          SnackBar(content: Text('无法建立语义索引：$error')),
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
        ? '混合检索 · 已限制到当前阅读进度'
        : '混合检索 · 包含全书章节';
  }
  final reason = response.semanticStatusCode == null
      ? ''
      : '（${response.semanticStatusCode}）';
  return '关键词检索 · 语义检索暂不可用$reason';
}
