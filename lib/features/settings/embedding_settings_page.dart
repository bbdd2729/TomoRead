import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/embedding_provider_catalog.dart';
import '../../domain/models/embedding_models.dart';
import 'embedding_settings_controller.dart';

class EmbeddingSettingsPage extends ConsumerWidget {
  const EmbeddingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(embeddingSettingsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Embedding 与语义检索', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          '向量模型与聊天模型完全独立。没有可用向量模型时，关键词搜索和原文回跳仍然可用。',
        ),
        const SizedBox(height: 8),
        const Text(
          '本地模式连接你已启动的 Ollama 或 LM Studio；TomoRead 不会伪装内置推理，也不会静默下载模型。',
        ),
        const SizedBox(height: 20),
        profiles.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('无法读取向量配置：$error'),
          data: (items) => Column(
            children: [
              if (items.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.manage_search_outlined),
                    title: Text('尚未配置向量模型'),
                    subtitle: Text('书内搜索当前使用关键词模式。'),
                  ),
                ),
              for (final profile in items)
                _EmbeddingProfileCard(profile: profile),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _showProfileDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('添加向量配置'),
        ),
      ],
    );
  }
}

class _EmbeddingProfileCard extends ConsumerWidget {
  const _EmbeddingProfileCard({required this.profile});

  final EmbeddingProviderProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                profile.mode == EmbeddingProviderMode.localService
                    ? Icons.computer_outlined
                    : Icons.cloud_outlined,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  profile.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (profile.isActive)
                const Chip(
                  avatar: Icon(Icons.check_circle_outline, size: 18),
                  label: Text('当前'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${profile.modelId} · ${profile.modelVersion}'),
          const SizedBox(height: 4),
          Text(
            profile.baseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: profile.isEnabled,
            onChanged: (value) => ref
                .read(embeddingSettingsControllerProvider.notifier)
                .setEnabled(profile.id, value),
            title: const Text('启用此向量配置'),
            subtitle: const Text('关闭后立即回退到关键词搜索，不删除已生成向量。'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(label: Text(_capabilityLabel(profile))),
              Chip(label: Text(profile.distanceMetric.name)),
              if (profile.dimensions != null)
                Chip(label: Text('${profile.dimensions} 维')),
              if (profile.mode == EmbeddingProviderMode.remote)
                Chip(
                  label: Text(
                    profile.remoteContentConsent
                        ? '已允许发送正文'
                        : '未允许发送正文',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _probe(context, ref),
                icon: const Icon(Icons.network_check),
                label: const Text('测试 Embedding'),
              ),
              TextButton.icon(
                onPressed: () => _showProfileDialog(
                  context,
                  ref,
                  profile: profile,
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
              if (!profile.isActive)
                TextButton(
                  onPressed: profile.isEnabled
                      ? () => ref
                            .read(embeddingSettingsControllerProvider.notifier)
                            .activate(profile.id)
                      : null,
                  child: const Text('设为当前'),
                ),
              TextButton.icon(
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.delete_outline),
                label: const Text('移除'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _probe(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(embeddingSettingsControllerProvider.notifier)
          .probe(profile.id);
      if (!context.mounted) return;
      final message = result.succeeded
          ? 'Embedding 可用：${result.dimensions} 维，${result.latencyMillis} ms'
                '${result.models.isEmpty ? '' : '，发现 ${result.models.length} 个模型'}'
          : 'Embedding 不可用：${result.errorCode ?? 'unknown'}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('测试失败：$error')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除向量配置？'),
        content: const Text('该配置生成的向量索引将一并删除；关键词索引不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await ref
          .read(embeddingSettingsControllerProvider.notifier)
          .delete(profile.id);
    }
  }
}

Future<void> _showProfileDialog(
  BuildContext context,
  WidgetRef ref, {
  EmbeddingProviderProfile? profile,
}) async {
  final catalog = ref.read(embeddingProviderCatalogProvider);
  var preset = catalog.byId(profile?.presetId ?? 'ollama');
  var presetId = preset.id;
  var mode = profile?.mode ?? preset.mode;
  var authType = profile?.authType ?? preset.authType;
  var distanceMetric =
      profile?.distanceMetric ?? EmbeddingDistanceMetric.cosine;
  var remoteConsent = profile?.remoteContentConsent ?? false;
  final name = TextEditingController(
    text: profile?.name ?? preset.displayName,
  );
  final baseUrl = TextEditingController(
    text: profile?.baseUrl ?? preset.baseUrl,
  );
  final model = TextEditingController(
    text: profile?.modelId ?? preset.defaultModelId,
  );
  final version = TextEditingController(
    text: profile?.modelVersion ?? 'provider-managed-v1',
  );
  final apiKey = TextEditingController();
  final maxInput = TextEditingController(
    text: '${profile?.maxInputCharacters ?? 8000}',
  );
  final batchSize = TextEditingController(
    text: '${profile?.batchSize ?? 16}',
  );
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(profile == null ? '添加向量配置' : '编辑向量配置'),
        content: SizedBox(
          width: (MediaQuery.sizeOf(dialogContext).width - 48)
              .clamp(280, 620)
              .toDouble(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: presetId,
                  decoration: const InputDecoration(labelText: '服务商预设'),
                  items: EmbeddingProviderCatalog.presets
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() {
                      final previous = preset;
                      preset = catalog.byId(id);
                      presetId = id;
                      mode = preset.mode;
                      authType = preset.authType;
                      remoteConsent = false;
                      if (name.text.isEmpty || name.text == previous.displayName) {
                        name.text = preset.displayName;
                      }
                      if (baseUrl.text.isEmpty || baseUrl.text == previous.baseUrl) {
                        baseUrl.text = preset.baseUrl;
                      }
                      if (model.text.isEmpty ||
                          model.text == previous.defaultModelId) {
                        model.text = preset.defaultModelId;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '配置名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrl,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: 'Embedding 模型 ID'),
                ),
                if (preset.recommendedModels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: preset.recommendedModels
                          .map(
                            (item) => Tooltip(
                              message:
                                  '${item.languages} · ${item.license}\n${item.sourceUrl}',
                              child: ActionChip(
                                label: Text(item.displayName),
                                onPressed: () => setState(
                                  () => model.text = item.modelId,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: version,
                  decoration: const InputDecoration(
                    labelText: '模型/部署版本',
                    helperText: '服务端更新模型后请修改此值，以使旧向量立即失效。',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKey,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: authType == EmbeddingProviderAuthType.none
                        ? 'API Key（本地服务通常不需要）'
                        : profile == null
                        ? 'API Key'
                        : 'API Key（留空保持不变）',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EmbeddingDistanceMetric>(
                  initialValue: distanceMetric,
                  decoration: const InputDecoration(labelText: '距离度量'),
                  items: EmbeddingDistanceMetric.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => distanceMetric = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: maxInput,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '单段最大字符数',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: batchSize,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '批大小'),
                      ),
                    ),
                  ],
                ),
                if (mode == EmbeddingProviderMode.remote) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remoteConsent,
                    onChanged: (value) =>
                        setState(() => remoteConsent = value),
                    title: const Text('允许向该服务商发送书籍正文片段'),
                    subtitle: const Text(
                      '只有明确开启后才能建立远端向量索引。API Key 仍只保存在系统安全存储中。',
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('本地服务必须使用 localhost/127.0.0.1，正文不会发送到远端。'),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) {
    name.dispose();
    baseUrl.dispose();
    model.dispose();
    version.dispose();
    apiKey.dispose();
    maxInput.dispose();
    batchSize.dispose();
    return;
  }
  try {
    await ref
        .read(embeddingSettingsControllerProvider.notifier)
        .save(
          profileId: profile?.id,
          presetId: presetId,
          name: name.text,
          mode: mode,
          authType: authType,
          baseUrl: baseUrl.text,
          modelId: model.text,
          modelVersion: version.text,
          apiKey: apiKey.text,
          distanceMetric: distanceMetric,
          remoteContentConsent: remoteConsent,
          maxInputCharacters: int.tryParse(maxInput.text) ?? 8000,
          batchSize: int.tryParse(batchSize.text) ?? 16,
        );
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    }
  } finally {
    name.dispose();
    baseUrl.dispose();
    model.dispose();
    version.dispose();
    apiKey.dispose();
    maxInput.dispose();
    batchSize.dispose();
  }
}

String _capabilityLabel(EmbeddingProviderProfile profile) =>
    switch (profile.capabilityStatus) {
      EmbeddingCapabilityStatus.untested => '尚未测试',
      EmbeddingCapabilityStatus.ready => 'Embedding 可用',
      EmbeddingCapabilityStatus.unavailable =>
        '不可用：${profile.capabilityErrorCode ?? 'unknown'}',
      EmbeddingCapabilityStatus.incompatible =>
        '不兼容：${profile.capabilityErrorCode ?? 'unknown'}',
    };
