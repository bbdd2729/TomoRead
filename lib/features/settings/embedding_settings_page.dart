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
        Text('التضمين والاسترجاع الدلالي', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'نموذج المتجه مستقل تمامًا عن نموذج الدردشة. لا تزال عمليات البحث عن الكلمات الرئيسية والنسخ الاحتياطية متاحة عندما لا يكون هناك نموذج متجه متاح.',
        ),
        const SizedBox(height: 8),
        const Text(
          'يتصل الوضع المحلي بـ Ollama أو LM Studio الذي تم إطلاقه ؛ لا تتنكر TomoRead على أنها استدلال مدمج، ولا تقوم بتنزيل النماذج بصمت.',
        ),
        const SizedBox(height: 20),
        profiles.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('تعذر قراءة تكوين المتجه: $error'),
          data: (items) => Column(
            children: [
              if (items.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.manage_search_outlined),
                    title: Text('لم يتم تكوين طراز المتجه'),
                    subtitle: Text('وضع الكلمات الرئيسية المستخدم حاليًا لعمليات البحث داخل الكتاب.'),
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
          label: const Text('إضافة تكوين متجه'),
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
                  label: Text('الوضع الراهن'),
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
            title: const Text('تمكين تكوين المتجه هذا'),
            subtitle: const Text('الرجوع إلى البحث عن الكلمات الرئيسية مباشرة بعد الإغلاق دون حذف المتجه الذي تم إنشاؤه.'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(label: Text(_capabilityLabel(profile))),
              Chip(label: Text(profile.distanceMetric.name)),
              if (profile.dimensions != null)
                Chip(label: Text('${profile.dimensions}الأبعاد')),
              if (profile.mode == EmbeddingProviderMode.remote)
                Chip(
                  label: Text(
                    profile.remoteContentConsent
                        ? 'يسمح بإرسال الجثة'
                        : 'لا يُسمح بإرسال الجثة',
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
                label: const Text('اختبار التضمين'),
              ),
              TextButton.icon(
                onPressed: () => _showProfileDialog(
                  context,
                  ref,
                  profile: profile,
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('تحرير'),
              ),
              if (!profile.isActive)
                TextButton(
                  onPressed: profile.isEnabled
                      ? () => ref
                            .read(embeddingSettingsControllerProvider.notifier)
                            .activate(profile.id)
                      : null,
                  child: const Text('تعيين كتيار'),
                ),
              TextButton.icon(
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.delete_outline),
                label: const Text('أزِل'),
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
          ? 'التضمين متاح:${result.dimensions}البُعد،${result.latencyMillis} ms'
                '${result.models.isEmpty ? '' : '، تم العثور على ${result.models.length} نموذج'}'
          : 'التضمين غير متاح:${result.errorCode ?? 'unknown'}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الاختبار: $error')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('هل تريد إزالة تكوين المتجه ؟'),
        content: const Text('سيتم أيضًا حذف فهارس المتجهات التي تم إنشاؤها بواسطة هذا التكوين ؛ لن تتأثر فهارس الكلمات الرئيسية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('أزِل'),
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
        title: Text(profile == null ? 'إضافة تكوين متجه' : 'تحرير تكوين المتجه'),
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
                  decoration: const InputDecoration(labelText: 'الإعدادات المسبقة لمقدم الخدمة'),
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
                  decoration: const InputDecoration(labelText: 'اسم التشكيل الجانبي'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrl,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: 'معرّف نموذج التضمين'),
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
                    labelText: 'إصدار النموذج/النشر',
                    helperText: 'قم بتعديل هذه القيمة بعد أن يقوم الخادم بتحديث النموذج لجعل المتجه القديم غير صالح على الفور.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKey,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: authType == EmbeddingProviderAuthType.none
                        ? 'مفتاح واجهة برمجة التطبيقات (عادةً غير مطلوب للخدمات المحلية)'
                        : profile == null
                        ? 'API Key'
                        : 'مفتاح واجهة برمجة التطبيقات (اتركه فارغًا لتركه دون تغيير)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EmbeddingDistanceMetric>(
                  initialValue: distanceMetric,
                  decoration: const InputDecoration(labelText: 'مقياس المسافة'),
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
                          labelText: 'الحد الأقصى لعدد الأحرف لكل مقطع',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: batchSize,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'حجم الدفعة'),
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
                    title: const Text('السماح بإرسال قصاصات نص الكتاب إلى هذا المزود'),
                    subtitle: const Text(
                      'لا يمكن إنشاء فهرسة المتجهات عن بُعد إلا إذا تم تشغيلها بشكل صريح. لا يزال مفتاح واجهة برمجة التطبيقات مخزنًا فقط في المتجر الآمن للنظام.',
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('يجب أن تستخدم الخدمة المحلية المضيف المحلي/127.0.0.1 ولن يتم إرسال الجسم إلى الطرف البعيد.'),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ'),
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
        SnackBar(content: Text('فشل عملية الحفظ: $error')),
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
      EmbeddingCapabilityStatus.untested => 'لم يتم اختباره بعد',
      EmbeddingCapabilityStatus.ready => 'التضمين متاح',
      EmbeddingCapabilityStatus.unavailable =>
        'Not available${profile.capabilityErrorCode ?? 'unknown'}',
      EmbeddingCapabilityStatus.incompatible =>
        'غير متوافق:${profile.capabilityErrorCode ?? 'unknown'}',
    };
