import 'package:flutter/material.dart';

import '../../app/appearance.dart';
import '../../shared/widgets/page_header.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.appearance,
    required this.onAppearanceChanged,
  });

  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onAppearanceChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeader(title: '设置', subtitle: '调整应用的外观和阅读偏好。'),
        const SizedBox(height: 28),
        Text('外观', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto),
              label: Text('跟随系统'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('浅色'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('深色'),
            ),
          ],
          selected: {appearance.mode},
          onSelectionChanged: (selection) =>
              onAppearanceChanged(appearance.copyWith(mode: selection.first)),
        ),
        const SizedBox(height: 28),
        Text('主题色', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          children: ThemeSeed.values
              .map(
                (seed) => Tooltip(
                  message: seed.label,
                  child: InkWell(
                    key: Key('theme-${seed.name}'),
                    borderRadius: BorderRadius.circular(24),
                    onTap: () =>
                        onAppearanceChanged(appearance.copyWith(seed: seed)),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: seed.color,
                        child: appearance.seed == seed
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 28),
        Text('文字缩放', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('A', style: TextStyle(fontSize: 14)),
            Expanded(
              child: Slider(
                value: appearance.textScale,
                min: .85,
                max: 1.25,
                divisions: 4,
                label: '${(appearance.textScale * 100).round()}%',
                onChanged: (value) =>
                    onAppearanceChanged(appearance.copyWith(textScale: value)),
              ),
            ),
            const Text('A', style: TextStyle(fontSize: 22)),
          ],
        ),
        const SizedBox(height: 28),
        Text('阅读偏好', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const SwitchListTile(
          value: true,
          onChanged: null,
          title: Text('双栏阅读'),
          subtitle: Text('宽屏时显示双栏排版。'),
        ),
        const SwitchListTile(
          value: false,
          onChanged: null,
          title: Text('显示阅读时间'),
          subtitle: Text('在阅读器底部显示当前阅读时间。'),
        ),
      ],
    );
  }
}
