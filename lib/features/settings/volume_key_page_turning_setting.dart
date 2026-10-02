import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/models/reading_settings.dart';

class VolumeKeyPageTurningSetting extends StatelessWidget {
  const VolumeKeyPageTurningSetting({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final ReadingSettings settings;
  final ValueChanged<ReadingSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    return SwitchListTile(
      key: const Key('volume-key-turns-page-setting'),
      contentPadding: EdgeInsets.zero,
      value: settings.volumeKeyTurnsPage,
      onChanged: (value) =>
          onChanged(settings.copyWith(volumeKeyTurnsPage: value)),
      title: const Text('تشغيل صفحة زر مستوى الصوت'),
      subtitle: const Text('عند تشغيله، اضغط على زر رفع مستوى الصوت للانتقال إلى الصفحة السابقة، وزر خفض مستوى الصوت للانتقال إلى الصفحة التالية.'),
    );
  }
}
