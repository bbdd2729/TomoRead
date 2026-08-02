import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../data/services/reader_shortcut_service.dart';
import '../../domain/models/reader_commands.dart';
import 'reader_command_controller.dart';
import 'reader_command_shortcuts.dart';

class ReaderShortcutSettingsPanel extends ConsumerWidget {
  const ReaderShortcutSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = currentReaderShortcutPlatform();
    if (platform == null || kIsWeb) return const SizedBox.shrink();
    final state = ref.watch(readerCommandSettingsProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('无法加载阅读快捷键：$error'),
      data: (settings) => _ReaderShortcutSettingsContent(
        platform: platform,
        settings: settings,
        onChanged: (value) async {
          try {
            await ref
                .read(readerCommandSettingsProvider.notifier)
                .saveSettings(value);
          } on ReaderShortcutException catch (error) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error.message)),
            );
          }
        },
        onRestoreDefaults: () => ref
            .read(readerCommandSettingsProvider.notifier)
            .restoreDefaults(),
      ),
    );
  }
}

class _ReaderShortcutSettingsContent extends StatelessWidget {
  const _ReaderShortcutSettingsContent({
    required this.platform,
    required this.settings,
    required this.onChanged,
    required this.onRestoreDefaults,
  });

  final ReaderShortcutPlatform platform;
  final ReaderCommandSettings settings;
  final Future<void> Function(ReaderCommandSettings settings) onChanged;
  final Future<void> Function() onRestoreDefaults;

  @override
  Widget build(BuildContext context) {
    final bindings = settings.forPlatform(platform);
    final autoScroll = settings.autoScroll;
    final minSpeed = autoScroll.unit == AutoScrollUnit.linesPerMinute ? 5.0 : 0.1;
    final maxSpeed = autoScroll.unit == AutoScrollUnit.linesPerMinute ? 120.0 : 3.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '桌面阅读快捷键',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: onRestoreDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('恢复默认'),
            ),
          ],
        ),
        Text(
          platform == ReaderShortcutPlatform.windows
              ? '当前编辑 Windows 快捷键。冲突组合和系统保留组合不会保存。'
              : '当前编辑 Linux 快捷键。冲突组合和系统保留组合不会保存。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const Key('reader-shortcut-bindings'),
          tilePadding: EdgeInsets.zero,
          title: const Text('命令绑定'),
          subtitle: Text('${bindings.where((binding) => binding.enabled).length} 项已启用'),
          children: [
            for (final binding in bindings)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(binding.command.label),
                subtitle: Text(binding.chord?.label ?? '未设置'),
                leading: Switch(
                  value: binding.enabled,
                  onChanged: binding.chord == null
                      ? null
                      : (enabled) => onChanged(
                          settings.replaceBinding(
                            binding.copyWith(enabled: enabled),
                          ),
                        ),
                ),
                trailing: IconButton(
                  tooltip: '修改快捷键',
                  onPressed: !binding.userModifiable
                      ? null
                      : () async {
                          final chord = await showDialog<ReaderShortcutChord>(
                            context: context,
                            builder: (context) => _ShortcutChordDialog(
                              command: binding.command,
                              initial: binding.chord,
                            ),
                          );
                          if (chord == null) return;
                          await onChanged(
                            settings.replaceBinding(
                              binding.copyWith(chord: chord, enabled: true),
                            ),
                          );
                        },
                  icon: const Icon(Icons.keyboard_outlined),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('自动滚动速度', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<AutoScrollUnit>(
          segments: [
            for (final unit in AutoScrollUnit.values)
              ButtonSegment(value: unit, label: Text(unit.label)),
          ],
          selected: {autoScroll.unit},
          onSelectionChanged: (selection) {
            final unit = selection.first;
            unawaited(
              onChanged(
                settings.copyWith(
                  autoScroll: AutoScrollPreference(
                    unit: unit,
                    speed: unit == AutoScrollUnit.linesPerMinute ? 30 : 0.5,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Slider(
                key: const Key('reader-auto-scroll-speed'),
                value: autoScroll.speed.clamp(minSpeed, maxSpeed).toDouble(),
                min: minSpeed,
                max: maxSpeed,
                divisions: autoScroll.unit == AutoScrollUnit.linesPerMinute
                    ? 23
                    : 29,
                label: autoScroll.unit == AutoScrollUnit.linesPerMinute
                    ? autoScroll.speed.round().toString()
                    : autoScroll.speed.toStringAsFixed(1),
                onChanged: (speed) => onChanged(
                  settings.copyWith(
                    autoScroll: autoScroll.copyWith(speed: speed),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                autoScroll.unit == AutoScrollUnit.linesPerMinute
                    ? '${autoScroll.speed.round()} 行/分'
                    : '${autoScroll.speed.toStringAsFixed(1)} 屏/分',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShortcutChordDialog extends StatefulWidget {
  const _ShortcutChordDialog({required this.command, required this.initial});

  final ReaderCommand command;
  final ReaderShortcutChord? initial;

  @override
  State<_ShortcutChordDialog> createState() => _ShortcutChordDialogState();
}

class _ShortcutChordDialogState extends State<_ShortcutChordDialog> {
  late var _key = widget.initial?.key ?? 'keyA';
  late var _control = widget.initial?.control ?? true;
  late var _alt = widget.initial?.alt ?? false;
  late var _shift = widget.initial?.shift ?? false;
  late var _meta = widget.initial?.meta ?? false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.command.label),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _key,
            decoration: const InputDecoration(
              labelText: '按键',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final key in supportedReaderShortcutKeys)
                DropdownMenuItem(
                  value: key,
                  child: Text(readerShortcutKeyLabel(key)),
                ),
            ],
            onChanged: (key) {
              if (key != null) setState(() => _key = key);
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Ctrl'),
                selected: _control,
                onSelected: (value) => setState(() => _control = value),
              ),
              FilterChip(
                label: const Text('Alt'),
                selected: _alt,
                onSelected: (value) => setState(() => _alt = value),
              ),
              FilterChip(
                label: const Text('Shift'),
                selected: _shift,
                onSelected: (value) => setState(() => _shift = value),
              ),
              FilterChip(
                label: const Text('Meta'),
                selected: _meta,
                onSelected: (value) => setState(() => _meta = value),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          ReaderShortcutChord(
            key: _key,
            control: _control,
            alt: _alt,
            shift: _shift,
            meta: _meta,
          ),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}
