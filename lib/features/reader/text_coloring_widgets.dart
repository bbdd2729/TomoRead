import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/models/text_coloring.dart';
import 'text_coloring_controller.dart';

class TextColoringSettingsPanel extends StatelessWidget {
  const TextColoringSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    this.loading = false,
  });

  final TextColoringSettings settings;
  final ValueChanged<TextColoringSettings> onChanged;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('text-coloring-enabled'),
          contentPadding: EdgeInsets.zero,
          value: settings.enabled,
          onChanged: loading
              ? null
              : (value) => onChanged(settings.copyWith(enabled: value)),
          title: const Text('启用文本前景色'),
          subtitle: const Text('只改变阅读展示，不修改书籍原文、标注或 AI 引用。'),
        ),
        const SizedBox(height: 8),
        for (final token in TextColorSemanticToken.values)
          _TokenColorRow(
            token: token,
            style: settings.tokens[token]!,
            enabled: !loading && settings.enabled,
            onChanged: (style) => onChanged(
              settings.updateToken(token, style),
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: const Text('自定义词条色板'),
          subtitle: const Text('选中正文添加词条时使用的亮色/暗色前景色。'),
          children: [
            for (final tone in TextColorTermTone.values)
              _PaletteColorRow(
                label: tone.label,
                colors: settings.termPalette[tone]!,
                enabled: !loading,
                onChanged: (colors) => onChanged(
                  settings.updateTermTone(tone, colors),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: loading
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (context) => TextColorTermsManagerDialog(
                        settings: settings,
                        title: '全局文字词条',
                      ),
                    ),
              icon: const Icon(Icons.format_color_text_outlined),
              label: const Text('管理全局词条'),
            ),
            TextButton.icon(
              onPressed: loading
                  ? null
                  : () => onChanged(TextColoringSettings.defaults()),
              icon: const Icon(Icons.restart_alt),
              label: const Text('恢复默认文本颜色'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TokenColorRow extends StatelessWidget {
  const _TokenColorRow({
    required this.token,
    required this.style,
    required this.enabled,
    required this.onChanged,
  });

  final TextColorSemanticToken token;
  final TextColorTokenStyle style;
  final bool enabled;
  final ValueChanged<TextColorTokenStyle> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: style.enabled,
            onChanged: enabled
                ? (value) => onChanged(style.copyWith(enabled: value))
                : null,
            title: Text(token.label),
            subtitle: Text(token.description),
          ),
        ),
        _ColorPairButtons(
          colors: style.colors,
          enabled: enabled && style.enabled,
          onChanged: (colors) => onChanged(style.copyWith(colors: colors)),
        ),
      ],
    ),
  );
}

class _PaletteColorRow extends StatelessWidget {
  const _PaletteColorRow({
    required this.label,
    required this.colors,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final TextColorPair colors;
  final bool enabled;
  final ValueChanged<TextColorPair> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        _ColorPairButtons(
          colors: colors,
          enabled: enabled,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _ColorPairButtons extends StatelessWidget {
  const _ColorPairButtons({
    required this.colors,
    required this.enabled,
    required this.onChanged,
  });

  final TextColorPair colors;
  final bool enabled;
  final ValueChanged<TextColorPair> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _ColorButton(
        tooltip: '亮色主题：${colors.light}',
        value: colors.light,
        enabled: enabled,
        onChanged: (value) => onChanged(colors.copyWith(light: value)),
      ),
      const SizedBox(width: 6),
      _ColorButton(
        tooltip: '暗色主题：${colors.dark}',
        value: colors.dark,
        enabled: enabled,
        dark: true,
        onChanged: (value) => onChanged(colors.copyWith(dark: value)),
      ),
    ],
  );
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.tooltip,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.dark = false,
  });

  final String tooltip;
  final String value;
  final bool enabled;
  final bool dark;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled
          ? () async {
              final result = await showDialog<String>(
                context: context,
                builder: (context) => _HexColorDialog(initialValue: value),
              );
              if (result != null) onChanged(result);
            }
          : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _colorFromHex(value),
          shape: BoxShape.circle,
          border: Border.all(
            color: dark ? Colors.white38 : Colors.black26,
            width: 2,
          ),
        ),
        child: Icon(
          dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          size: 16,
          color: _foregroundFor(_colorFromHex(value)),
        ),
      ),
    ),
  );
}

class _HexColorDialog extends StatefulWidget {
  const _HexColorDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_HexColorDialog> createState() => _HexColorDialogState();
}

class _HexColorDialogState extends State<_HexColorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('设置文字颜色'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'HEX 颜色',
          hintText: '#2E6B8A',
          border: OutlineInputBorder(),
        ),
        validator: (value) => RegExp(
          r'^#[0-9a-fA-F]{6}$',
        ).hasMatch(value?.trim() ?? '')
            ? null
            : '请输入 #RRGGBB 格式的颜色。',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          Navigator.pop(context, _controller.text.trim().toUpperCase());
        },
        child: const Text('确定'),
      ),
    ],
  );
}

class TextColorTermDraft {
  const TextColorTermDraft({required this.global, required this.tone});

  final bool global;
  final TextColorTermTone tone;
}

class TextColorTermChoiceDialog extends StatefulWidget {
  const TextColorTermChoiceDialog({
    super.key,
    required this.text,
    required this.settings,
  });

  final String text;
  final TextColoringSettings settings;

  @override
  State<TextColorTermChoiceDialog> createState() =>
      _TextColorTermChoiceDialogState();
}

class _TextColorTermChoiceDialogState
    extends State<TextColorTermChoiceDialog> {
  var _global = false;
  var _tone = TextColorTermTone.blue;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加文字颜色'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text.trim().replaceAll(RegExp(r'\s+'), ' '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('仅本书')),
              ButtonSegment(value: true, label: Text('全部书籍')),
            ],
            selected: {_global},
            onSelectionChanged: (value) => setState(
              () => _global = value.first,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final tone in TextColorTermTone.values)
                ChoiceChip(
                  selected: tone == _tone,
                  label: Text(tone.label),
                  avatar: CircleAvatar(
                    backgroundColor: _colorFromHex(
                      Theme.of(context).brightness == Brightness.dark
                          ? widget.settings.termPalette[tone]!.dark
                          : widget.settings.termPalette[tone]!.light,
                    ),
                  ),
                  onSelected: (_) => setState(() => _tone = tone),
                ),
            ],
          ),
          if (!widget.settings.enabled) ...[
            const SizedBox(height: 16),
            Text(
              '词条会保存，但需在“设置 → 阅读”中启用文本前景色后显示。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
          TextColorTermDraft(global: _global, tone: _tone),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}

class TextColorTermsManagerDialog extends ConsumerWidget {
  const TextColorTermsManagerDialog({
    super.key,
    required this.settings,
    required this.title,
    this.bookId,
  });

  final TextColoringSettings settings;
  final String title;
  final String? bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(
      textColorTermsProvider((bookId: bookId, includeGlobal: false)),
    );
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: terms.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('无法加载文字词条：$error')),
          data: (items) => items.isEmpty
              ? const Center(child: Text('还没有文字词条。请在阅读器中选中文字添加。'))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final term = items[index];
                    final pair = settings.termPalette[term.tone]!;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _colorFromHex(
                          Theme.of(context).brightness == Brightness.dark
                              ? pair.dark
                              : pair.light,
                        ),
                      ),
                      title: Text(
                        term.term,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(term.tone.label),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref
                            .read(textColoringControllerProvider)
                            .removeTerm(term.id),
                      ),
                    );
                  },
                ),
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

Color _colorFromHex(String value) => Color(
  int.parse('FF${value.replaceFirst('#', '')}', radix: 16),
);

Color _foregroundFor(Color background) =>
    background.computeLuminance() > .45 ? Colors.black87 : Colors.white;
