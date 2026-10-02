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
        title: const Text('مقدمو ونماذج خدمات الذكاء الاصطناعي'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: selectedProfileId,
                  decoration: const InputDecoration(labelText: 'تكوين السيناريوهات'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('تكوين جديد'),
                    ),
                    ...profiles.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item.id,
                        child: Text(
                          '${item.name}${item.isActive ? 'الوضع الراهن' : ''}',
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
                  decoration: const InputDecoration(labelText: 'الإعدادات المسبقة لمقدم الخدمة'),
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
                  decoration: const InputDecoration(labelText: 'الاسم'),
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
                    labelText: 'النموذج',
                    hintText: 'يمكن إدخالها يدويًا أو سحبها من الخدمة',
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
                        ? 'مفتاح واجهة برمجة التطبيقات (عادةً غير مطلوب للخدمات المحلية)'
                        : editing == null
                        ? 'API Key'
                        : 'مفتاح واجهة برمجة التطبيقات (اتركه فارغًا لتركه دون تغيير)',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('أدوات الوكيل'),
                  subtitle: const Text('يسمح للنموذج بقراءة الكتالوجات والتعليقات التوضيحية والنص الأصلي في الكتب'),
                  value: toolsEnabled,
                  onChanged: (value) => setState(() => toolsEnabled = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ملخص التفكير'),
                  subtitle: const Text('عرض محتوى الاستدلال المرئي الذي أرجعته الخدمة'),
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
                setState(() => probeStatus = 'جارٍ اختبار الاتصال...');
                try {
                  final result = await ref
                      .read(chatControllerProvider.notifier)
                      .probeProvider(editing!.id);
                  if (!context.mounted) return;
                  setState(() {
                    fetchedModels = result.models;
                    probeStatus = result.succeeded
                        ? 'تم الاتصال بنجاح · HTTP${result.statusCode} · ${result.latencyMillis} ms${result.models.isEmpty ? '' : ' · ${result.models.length} نماذج'}'
                        : 'فشل اتصال!${result.errorCode} · HTTP ${result.statusCode ?? '-'}';
                  });
                } on Object catch (error) {
                  if (context.mounted) {
                    setState(() => probeStatus = 'فشل الاتصال: $error');
                  }
                }
              },
              icon: const Icon(Icons.network_check),
              label: const Text('اختبار النموذج وسحبه'),
            ),
          if (editing != null && !editing!.isActive)
            TextButton(
              onPressed: () async {
                await ref
                    .read(chatControllerProvider.notifier)
                    .activateProvider(editing!.id);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: const Text('تعيين كتيار'),
            ),
          if (editing != null)
            TextButton(
              onPressed: () async {
                await ref
                    .read(chatControllerProvider.notifier)
                    .setProviderEnabled(editing!.id, !editing!.isEnabled);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: Text(editing!.isEnabled ? 'تعطيل' : 'تمكين '),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
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
      ).showSnackBar(SnackBar(content: Text('فشل حفظ تكوين النموذج: $error')));
    }
  } finally {
    name.dispose();
    baseUrl.dispose();
    model.dispose();
    key.dispose();
  }
}
