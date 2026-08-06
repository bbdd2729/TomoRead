import 'package:flutter/material.dart';

import '../../domain/models/reading_settings.dart';
import '../../domain/models/reader_chapter.dart';
import 'reader_chrome.dart';

/// Animated container for reader controls that overlay, rather than resize,
/// the reading surface.
class ReaderChromeContainer extends StatelessWidget {
  const ReaderChromeContainer({
    super.key,
    required this.visible,
    required this.hiddenOffset,
    required this.child,
  });

  final bool visible;
  final Offset hiddenOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedSlide(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : hiddenOffset,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: visible ? 1 : 0,
        child: child,
      ),
    ),
  );
}

/// Material surface shared by floating reader panels.
class ReaderOverlaySurface extends StatelessWidget {
  const ReaderOverlaySurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 4,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class ReaderArticleColumn extends StatelessWidget {
  const ReaderArticleColumn({
    super.key,
    required this.blocks,
    required this.settings,
  });

  final List<ReaderChapterBlock> blocks;
  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: blocks
        .map(
          (block) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              block.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontFamily: settings.font.fontFamily,
                fontSize: settings.fontSize,
                height: settings.lineHeight,
                fontWeight: block.isHeading ? FontWeight.w600 : null,
              ),
            ),
          ),
        )
        .toList(),
  );
}

/// Bottom reader navigation and its progress scrubber.
class ReaderFooter extends StatelessWidget {
  const ReaderFooter({
    super.key,
    required this.chapterIndex,
    required this.chapterCount,
    required this.layoutMode,
    required this.chromeLayout,
    required this.chapterProgress,
    required this.chapterProgressMeasured,
    required this.onSeekProgress,
    required this.onOpenToc,
    required this.onOpenStyle,
    required this.onOpenProgress,
    required this.onPrevious,
    required this.onNext,
  });

  final int chapterIndex;
  final int chapterCount;
  final ReaderLayoutMode layoutMode;
  final ReaderChromeLayout chromeLayout;
  final double chapterProgress;
  final bool chapterProgressMeasured;
  final ValueChanged<double> onSeekProgress;
  final VoidCallback onOpenToc;
  final VoidCallback onOpenStyle;
  final VoidCallback onOpenProgress;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final progress = chapterProgress.clamp(0, 1).toDouble();
    final positionLabel = chapterCount == 0
        ? '正在读取目录'
        : !chapterProgressMeasured
        ? '第 ${chapterIndex + 1} / $chapterCount 章 · 正在定位'
        : '第 ${chapterIndex + 1} / $chapterCount 章 · '
              '本章 ${(progress * 100).round()}%';
    if (!chromeLayout.isExpanded) {
      return ReaderCompactNavigationBar(
        key: const Key('reader-footer'),
        tocKey: const Key('reader-toc'),
        positionKey: const Key('reader-position-label'),
        styleKey: const Key('reader-book-settings'),
        positionLabel: positionLabel,
        onOpenToc: onOpenToc,
        onPrevious: onPrevious,
        onNext: onNext,
        onOpenStyle: onOpenStyle,
        onOpenProgress: onOpenProgress,
      );
    }
    return Material(
      key: const Key('reader-footer'),
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Row(
            children: [
              ReaderChromeIconButton(
                tooltip: layoutMode == ReaderLayoutMode.paginated
                    ? '上一页，或上一章'
                    : '上一章',
                icon: Icons.chevron_left,
                onPressed: onPrevious,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ReaderProgressSlider(
                  progress: progress,
                  onChanged: onSeekProgress,
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                key: const Key('reader-position-label'),
                label: '$positionLabel，打开阅读进度',
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onOpenProgress,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(positionLabel),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ReaderChromeIconButton(
                tooltip: layoutMode == ReaderLayoutMode.paginated
                    ? '下一页，或下一章'
                    : '下一章',
                icon: Icons.chevron_right,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderProgressSlider extends StatefulWidget {
  const ReaderProgressSlider({
    super.key,
    required this.progress,
    required this.onChanged,
  });

  final double progress;
  final ValueChanged<double> onChanged;

  @override
  State<ReaderProgressSlider> createState() => _ReaderProgressSliderState();
}

class _ReaderProgressSliderState extends State<ReaderProgressSlider> {
  double? _dragProgress;

  @override
  Widget build(BuildContext context) {
    final value = (_dragProgress ?? widget.progress).clamp(0, 1).toDouble();
    return Slider(
      key: const Key('reader-progress-slider'),
      value: value,
      label: '${(value * 100).round()}%',
      semanticFormatterCallback: (next) => '${(next * 100).round()}%',
      onChanged: (next) => setState(() => _dragProgress = next),
      onChangeEnd: (next) {
        setState(() => _dragProgress = null);
        widget.onChanged(next);
      },
    );
  }
}
