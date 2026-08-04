import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/ai_provider_catalog.dart';
import '../../domain/models/chat_models.dart';
import 'chat_controller.dart';

Future<void> configureAiProvider(
  BuildContext context,
  WidgetRef ref,
  AiProviderProfile? profile,
) async {
  final catalog = ref.read(aiProviderCatalogProvider);
  final profiles = await ref.read(aiProviderRepositoryProvider).listProfiles();
  if (!context.mounted) return;
  var editing = profile;
  var preset = catalog.byId(profile?.presetId ?? 'openai');
  final name = TextEditingController(text: profile?.name ?? preset.displayName);
  final baseUrl = TextEditingController(
    text: profile?.baseUrl ?? preset.baseUrl,
  );
  final model = TextEditingController(text: profile?.modelId ?? '');
  final key = TextEditingController();
  var selectedProfileId = profile?.id;
  var selectedPresetId = preset.id;
  var toolsEnabled = profile?.toolsEnabled ?? preset.toolsByDefault;
  var reasoningEnabled = profile?.reasoningEnabled ?? preset.reasoningByDefault;
  var probeStatus = '';
  var fetchedModels = const <String>[];
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('AI 服务商与模型'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: selectedProfileId,
                  decoration: const InputDecoration(labelText: '配置方案'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('新建配置'),
                    ),
                    ...profiles.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item.id,
                        child: Text(
                          '${item.name}${item.isActive ? '（当前）' : ''}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (id) {
                    final next = id == null
                        ? null
                        : profiles.where((item) => item.id == id).firstOrNull;
                    setState(() {
                      editing = next;
                      selectedProfileId = next?.id;
                      preset = catalog.byId(next?.presetId ?? 'openai');
                      selectedPresetId = preset.id;
                      name.text = next?.name ?? preset.displayName;
                      baseUrl.text = next?.baseUrl ?? preset.baseUrl;
                      model.text = next?.modelId ?? '';
                      toolsEnabled =
                          next?.toolsEnabled ?? preset.toolsByDefault;
                      reasoningEnabled =
                          next?.reasoningEnabled ?? preset.reasoningByDefault;
                      key.clear();
                      probeStatus = '';
                      fetchedModels = const [];
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('provider-preset-$selectedPresetId'),
                  initialValue: selectedPresetId,
                  decoration: const InputDecoration(labelText: '服务商预设'),
                  items: AiProviderCatalog.presets
                      .where((item) => !item.deprecated)
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
                      final previousName = preset.displayName;
                      final previousUrl = preset.baseUrl;
                      preset = catalog.byId(id);
                      selectedPresetId = id;
                      if (name.text.trim().isEmpty ||
                          name.text == editing?.name ||
                          name.text == previousName) {
                        name.text = preset.displayName;
                      }
                      if (baseUrl.text.trim().isEmpty ||
                          baseUrl.text == previousUrl) {
                        baseUrl.text = preset.baseUrl;
                      }
                      toolsEnabled = preset.toolsByDefault;
                      reasoningEnabled = preset.reasoningByDefault;
                      probeStatus = '';
                      fetchedModels = const [];
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrl,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    hintText: '可手动输入，或从服务拉取',
                  ),
                ),
                if (fetchedModels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: fetchedModels
                          .take(12)
                          .map(
                            (id) => ActionChip(
                              label: Text(id),
                              onPressed: () => setState(() => model.text = id),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: preset.authType == AiProviderAuthType.none
                        ? 'API Key（本地服务通常不需要）'
                        : editing == null
                        ? 'API Key'
                        : 'API Key（留空保持不变）',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Agent 工具'),
                  subtitle: const Text('允许模型读取目录、标注和书中原文'),
                  value: toolsEnabled,
                  onChanged: (value) => setState(() => toolsEnabled = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('思考摘要'),
                  subtitle: const Text('显示服务返回的可见 reasoning 内容'),
                  value: reasoningEnabled,
                  onChanged: (value) =>
                      setState(() => reasoningEnabled = value),
                ),
                if (probeStatus.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(probeStatus),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (editing != null)
            TextButton.icon(
              onPressed: () async {
                setState(() => probeStatus = '正在测试连接…');
                try {
                  final result = await ref
                      .read(chatControllerProvider.notifier)
                      .probeProvider(editing!.id);
                  if (!context.mounted) return;
                  setState(() {
                    fetchedModels = result.models;
                    probeStatus = result.succeeded
                        ? '连接成功 · HTTP ${result.statusCode} · ${result.latencyMillis} ms${result.models.isEmpty ? '' : ' · ${result.models.length} 个模型'}'
                        : '连接失败：${result.errorCode} · HTTP ${result.statusCode ?? '-'}';
                  });
                } on Object catch (error) {
                  if (context.mounted) {
                    setState(() => probeStatus = '连接失败：$error');
                  }
                }
              },
              icon: const Icon(Icons.network_check),
              label: const Text('测试并拉取模型'),
            ),
          if (editing != null && !editing!.isActive)
            TextButton(
              onPressed: () async {
                await ref
                    .read(chatControllerProvider.notifier)
                    .activateProvider(editing!.id);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: const Text('设为当前'),
            ),
          if (editing != null)
            TextButton(
              onPressed: () async {
                await ref
                    .read(chatControllerProvider.notifier)
                    .setProviderEnabled(editing!.id, !editing!.isEnabled);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: Text(editing!.isEnabled ? '停用' : '启用'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) {
    name.dispose();
    baseUrl.dispose();
    model.dispose();
    key.dispose();
    return;
  }
  try {
    await ref
        .read(chatControllerProvider.notifier)
        .configureProvider(
          profileId: selectedProfileId,
          presetId:
              selectedPresetId == 'custom' ||
                  baseUrl.text.trim() != preset.baseUrl
              ? 'custom'
              : selectedPresetId,
          authType: preset.authType,
          supportsModelList: preset.supportsModelList,
          name: name.text,
          baseUrl: baseUrl.text,
          modelId: model.text,
          apiKey: key.text,
          toolsEnabled: toolsEnabled,
          reasoningEnabled: reasoningEnabled,
        );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存模型配置失败：$error')));
    }
  } finally {
    name.dispose();
    baseUrl.dispose();
    model.dispose();
    key.dispose();
  }
}
