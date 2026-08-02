import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/models/tts.dart';
import 'tts_controller.dart';

class TtsToolbarButton extends StatelessWidget {
  const TtsToolbarButton({
    super.key,
    required this.controller,
    this.onBeforeOpen,
  });

  final TtsPlaybackController controller;
  final VoidCallback? onBeforeOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      return IconButton(
        key: const Key('reader-tts'),
        tooltip: _toolbarTooltip(state),
        isSelected: state.status == TtsPlaybackStatus.playing,
        onPressed: () {
          onBeforeOpen?.call();
          unawaited(showTtsControls(context, controller));
        },
        icon: Icon(_toolbarIcon(state.status)),
      );
    },
  );
}

Future<void> showTtsControls(
  BuildContext context,
  TtsPlaybackController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: TtsControlPanel(controller: controller),
    ),
  ),
);

class TtsControlPanel extends StatelessWidget {
  const TtsControlPanel({super.key, required this.controller});

  final TtsPlaybackController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final segment = state.currentSegment;
      final busy = state.status == TtsPlaybackStatus.loading;
      final playing = state.status == TtsPlaybackStatus.playing;
      final languages = <String>{
        state.settings.language,
        for (final voice in state.voices) voice.locale,
      }.toList()..sort();
      final matchingVoices = state.voices
          .where((voice) => voice.locale == state.settings.language)
          .toList();
      final selectedVoiceId = matchingVoices.any(
        (voice) => voice.id == state.settings.voiceId,
      )
          ? state.settings.voiceId
          : null;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_toolbarIcon(state.status)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('系统朗读', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      _statusLabel(state.status),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                segment?.text ??
                    (busy ? '正在准备当前章节的朗读队列…' : '当前章节暂无可朗读正文。'),
                key: const Key('tts-current-sentence'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              key: const Key('tts-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: '上一句',
                onPressed: state.canPlay && state.currentIndex > 0
                    ? () => unawaited(controller.previous())
                    : null,
                icon: const Icon(Icons.skip_previous),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                key: const Key('tts-play-pause'),
                tooltip: playing ? '暂停' : '播放',
                iconSize: 32,
                onPressed: state.canPlay && !busy
                    ? () => unawaited(controller.playPause())
                    : null,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                tooltip: '下一句',
                onPressed: state.canPlay &&
                        state.currentIndex + 1 < state.segments.length
                    ? () => unawaited(controller.next())
                    : null,
                icon: const Icon(Icons.skip_next),
              ),
              const SizedBox(width: 12),
              IconButton(
                key: const Key('tts-stop'),
                tooltip: '停止',
                onPressed: state.status == TtsPlaybackStatus.idle || busy
                    ? null
                    : () => unawaited(controller.stop()),
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ),
          const Divider(height: 32),
          _TtsSettingSlider(
            key: const Key('tts-rate'),
            value: state.settings.rate.clamp(.1, 1).toDouble(),
            min: .1,
            max: 1,
            divisions: 18,
            title: '语速',
            valueLabel: (value) => '${(value * 2).toStringAsFixed(1)}×',
            enabled: state.availability.available,
            onCommitted: (value) => unawaited(
              controller.updateSettings(state.settings.copyWith(rate: value)),
            ),
          ),
          _TtsSettingSlider(
            key: const Key('tts-volume'),
            value: state.settings.volume.clamp(0, 1).toDouble(),
            min: 0,
            max: 1,
            divisions: 20,
            title: '音量',
            valueLabel: (value) => '${(value * 100).round()}%',
            enabled: state.availability.available,
            onCommitted: (value) => unawaited(
              controller.updateSettings(
                state.settings.copyWith(volume: value),
              ),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('tts-language-${state.settings.language}'),
            initialValue: state.settings.language,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '语言',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final language in languages)
                DropdownMenuItem(value: language, child: Text(language)),
            ],
            onChanged: state.availability.available
                ? (language) {
                    if (language == null) return;
                    unawaited(
                      controller.updateSettings(
                        state.settings.copyWith(
                          language: language,
                          clearVoice: true,
                        ),
                      ),
                    );
                  }
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey(
              'tts-voice-${state.settings.language}-$selectedVoiceId',
            ),
            initialValue: selectedVoiceId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '系统声音',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('系统默认'),
              ),
              for (final voice in matchingVoices)
                DropdownMenuItem<String?>(
                  value: voice.id,
                  child: Text(voice.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: state.availability.available
                ? (voiceId) => unawaited(
                    controller.updateSettings(
                      voiceId == null
                          ? state.settings.copyWith(clearVoice: true)
                          : state.settings.copyWith(voiceId: voiceId),
                    ),
                  )
                : null,
          ),
          SwitchListTile(
            key: const Key('tts-keep-awake'),
            contentPadding: EdgeInsets.zero,
            title: const Text('朗读时保持屏幕唤醒'),
            subtitle: const Text('暂停、停止、完成或发生错误时会立即释放。'),
            value: state.settings.keepAwake,
            onChanged: (value) => unawaited(
              controller.updateSettings(
                state.settings.copyWith(keepAwake: value),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _TtsSettingSlider extends StatefulWidget {
  const _TtsSettingSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.title,
    required this.valueLabel,
    required this.enabled,
    required this.onCommitted,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String title;
  final String Function(double value) valueLabel;
  final bool enabled;
  final ValueChanged<double> onCommitted;

  @override
  State<_TtsSettingSlider> createState() => _TtsSettingSliderState();
}

class _TtsSettingSliderState extends State<_TtsSettingSlider> {
  double? _draft;

  @override
  Widget build(BuildContext context) {
    final value = (_draft ?? widget.value)
        .clamp(widget.min, widget.max)
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${widget.title} ${widget.valueLabel(value)}'),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: widget.valueLabel(value),
          onChanged: widget.enabled
              ? (next) => setState(() => _draft = next)
              : null,
          onChangeEnd: widget.enabled
              ? (next) {
                  setState(() => _draft = null);
                  widget.onCommitted(next);
                }
              : null,
        ),
      ],
    );
  }
}

IconData _toolbarIcon(TtsPlaybackStatus status) => switch (status) {
  TtsPlaybackStatus.playing => Icons.volume_up,
  TtsPlaybackStatus.paused => Icons.pause_circle_outline,
  TtsPlaybackStatus.loading => Icons.hourglass_top,
  TtsPlaybackStatus.failed => Icons.record_voice_over_outlined,
  _ => Icons.headphones_outlined,
};

String _toolbarTooltip(TtsPlaybackState state) => switch (state.status) {
  TtsPlaybackStatus.playing => '系统朗读：正在播放',
  TtsPlaybackStatus.paused => '系统朗读：已暂停',
  TtsPlaybackStatus.loading => '系统朗读：正在准备',
  _ => '系统朗读',
};

String _statusLabel(TtsPlaybackStatus status) => switch (status) {
  TtsPlaybackStatus.idle => '已停止',
  TtsPlaybackStatus.loading => '正在准备正文与系统声音',
  TtsPlaybackStatus.playing => '正在朗读当前章节',
  TtsPlaybackStatus.paused => '已暂停',
  TtsPlaybackStatus.completed => '当前章节朗读完成',
  TtsPlaybackStatus.failed => '系统朗读不可用',
};
