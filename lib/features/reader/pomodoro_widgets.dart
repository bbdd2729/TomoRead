import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/models/pomodoro.dart';
import 'pomodoro_controller.dart';

class PomodoroToolbarButton extends ConsumerWidget {
  const PomodoroToolbarButton({
    super.key,
    required this.bookId,
    this.onOpen,
  });

  final String bookId;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(pomodoroControllerProvider);
    final value = timer.value;
    return TextButton.icon(
      key: const Key('reader-pomodoro'),
      onPressed: () {
        onOpen?.call();
        showDialog<void>(
          context: context,
          builder: (context) => PomodoroDialog(bookId: bookId),
        );
      },
      icon: Icon(value?.isRunning == true ? Icons.timer : Icons.timer_outlined),
      label: Text(
        value == null || value.isIdle
            ? '专注'
            : '${value.phase.label} ${formatPomodoroDuration(value.remainingMillis)}',
      ),
    );
  }
}

class PomodoroBreakBanner extends ConsumerWidget {
  const PomodoroBreakBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(pomodoroControllerProvider).value;
    if (timer == null || !timer.isBreak || !timer.isRunning) {
      return const SizedBox.shrink();
    }
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.self_improvement),
            const SizedBox(width: 10),
            Text(
              '${timer.phase.label} · ${formatPomodoroDuration(timer.remainingMillis)}',
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => ref
                  .read(pomodoroControllerProvider.notifier)
                  .skipBreak(),
              child: const Text('提前结束'),
            ),
          ],
        ),
      ),
    );
  }
}

class PomodoroDialog extends HookConsumerWidget {
  const PomodoroDialog({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(pomodoroControllerProvider);
    return AlertDialog(
      title: const Text('阅读专注计时'),
      content: SizedBox(
        width: 440,
        child: timerState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('无法加载计时器：$error'),
          data: (timer) => _PomodoroDialogBody(timer: timer, bookId: bookId),
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

class _PomodoroDialogBody extends HookConsumerWidget {
  const _PomodoroDialogBody({required this.timer, required this.bookId});

  final PomodoroTimerState timer;
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusMinutes = useState(timer.config.focusMinutes);
    final shortBreakMinutes = useState(timer.config.shortBreakMinutes);
    final longBreakMinutes = useState(timer.config.longBreakMinutes);
    final longBreakEvery = useState(timer.config.longBreakEvery);
    final controller = ref.read(pomodoroControllerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            timer.isIdle
                ? '准备开始一轮专注'
                : '${timer.phase.label} · ${formatPomodoroDuration(timer.remainingMillis)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '已完成 ${timer.completedFocusCount} 轮专注',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!timer.isRunning)
              FilledButton.icon(
                onPressed: () => controller.startOrResume(bookId: bookId),
                icon: const Icon(Icons.play_arrow),
                label: Text(timer.isIdle ? '开始专注' : '继续${timer.phase.label}'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: controller.pause,
                icon: const Icon(Icons.pause),
                label: const Text('暂停'),
              ),
            if (!timer.isIdle)
              OutlinedButton.icon(
                onPressed: controller.stop,
                icon: const Icon(Icons.stop),
                label: const Text('停止'),
              ),
            if (timer.isBreak)
              TextButton(
                onPressed: controller.skipBreak,
                child: const Text('提前结束休息'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        Text('计时设置', style: Theme.of(context).textTheme.titleMedium),
        _MinuteSlider(
          label: '专注',
          value: focusMinutes.value,
          minimum: 1,
          maximum: 90,
          onChanged: timer.isIdle ? (value) => focusMinutes.value = value : null,
        ),
        _MinuteSlider(
          label: '短休息',
          value: shortBreakMinutes.value,
          minimum: 1,
          maximum: 30,
          onChanged: timer.isIdle
              ? (value) => shortBreakMinutes.value = value
              : null,
        ),
        _MinuteSlider(
          label: '长休息',
          value: longBreakMinutes.value,
          minimum: 1,
          maximum: 60,
          onChanged: timer.isIdle
              ? (value) => longBreakMinutes.value = value
              : null,
        ),
        Row(
          children: [
            const Expanded(child: Text('长休息间隔')),
            DropdownButton<int>(
              value: longBreakEvery.value,
              items: [2, 3, 4, 5, 6]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text('$value 轮'),
                    ),
                  )
                  .toList(),
              onChanged: timer.isIdle
                  ? (value) {
                      if (value != null) longBreakEvery.value = value;
                    }
                  : null,
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: timer.isIdle
                ? () => controller.saveConfig(
                    PomodoroConfig(
                      focusMinutes: focusMinutes.value,
                      shortBreakMinutes: shortBreakMinutes.value,
                      longBreakMinutes: longBreakMinutes.value,
                      longBreakEvery: longBreakEvery.value,
                    ),
                  )
                : null,
            child: const Text('保存设置'),
          ),
        ),
      ],
    );
  }
}

class _MinuteSlider extends StatelessWidget {
  const _MinuteSlider({
    required this.label,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int minimum;
  final int maximum;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 72, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min: minimum.toDouble(),
          max: maximum.toDouble(),
          divisions: maximum - minimum,
          label: '$value 分钟',
          onChanged: onChanged == null
              ? null
              : (next) => onChanged!(next.round()),
        ),
      ),
      SizedBox(width: 56, child: Text('$value 分钟')),
    ],
  );
}

String formatPomodoroDuration(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).ceil().clamp(0, 86400);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
