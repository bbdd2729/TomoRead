import 'package:flutter/material.dart';

/// The amount of reader chrome that can be shown without crowding the content.
///
/// The compact layout is deliberately selected for large system text too: a
/// phone with accessibility text scaling should not turn its title into an
/// unreadable icon strip.
enum ReaderChromeSize { compact, medium, expanded }

class ReaderChromeLayout {
  const ReaderChromeLayout._(this.size);

  static const compactBreakpoint = 600.0;
  static const expandedBreakpoint = 960.0;
  static const expandedActionsBreakpoint = 1200.0;
  static const minTouchTarget = 48.0;
  static const actionGap = 8.0;

  final ReaderChromeSize size;

  bool get isCompact => size == ReaderChromeSize.compact;
  bool get isMedium => size == ReaderChromeSize.medium;
  bool get isExpanded => size == ReaderChromeSize.expanded;
  bool get usesModalPanels => !isExpanded;

  /// Keeps low-frequency actions out of the toolbar until there is enough
  /// space for both a readable title and clearly separated touch targets.
  bool usesOverflowActions(double maxWidth) =>
      isCompact || maxWidth < expandedActionsBreakpoint;

  factory ReaderChromeLayout.resolve(
    BuildContext context, {
    required double maxWidth,
  }) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final usableWidth = (maxWidth - viewPadding.left - viewPadding.right)
        .clamp(0.0, maxWidth)
        .toDouble();
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (usableWidth < compactBreakpoint || textScale >= 1.3) {
      return const ReaderChromeLayout._(ReaderChromeSize.compact);
    }
    if (usableWidth < expandedBreakpoint) {
      return const ReaderChromeLayout._(ReaderChromeSize.medium);
    }
    return const ReaderChromeLayout._(ReaderChromeSize.expanded);
  }
}

class ReaderChromeAction {
  const ReaderChromeAction({
    required this.id,
    required this.label,
    required this.icon,
    this.onPressed,
    this.key,
    this.disabledDescription,
    this.selected = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? key;
  final String? disabledDescription;
  final bool selected;

  bool get enabled => onPressed != null;
}

class ReaderChromeActionGroup {
  const ReaderChromeActionGroup({required this.title, required this.actions});

  final String title;
  final List<ReaderChromeAction> actions;
}

/// A shared, labelled overflow sheet used by all reader formats.
///
/// It intentionally uses a full-width bottom sheet instead of a narrow popup
/// menu so actions remain touch-friendly and self-explanatory on phones.
Future<void> showReaderMoreSheet(
  BuildContext context, {
  required String title,
  required List<ReaderChromeActionGroup> groups,
}) {
  final visibleGroups = groups
      .where((group) => group.actions.isNotEmpty)
      .toList(growable: false);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _ReaderActionSheet(title: title, groups: visibleGroups),
  );
}

class ReaderChromeIconButton extends StatelessWidget {
  const ReaderChromeIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tooltip,
    button: true,
    enabled: onPressed != null,
    selected: selected,
    excludeSemantics: true,
    child: IconButton(
      tooltip: tooltip,
      isSelected: selected,
      constraints: const BoxConstraints.tightFor(
        width: ReaderChromeLayout.minTouchTarget,
        height: ReaderChromeLayout.minTouchTarget,
      ),
      padding: const EdgeInsets.all(12),
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
    ),
  );
}

/// Detects a deliberate short tap in the central reading region without
/// competing with selection, scrolling, or pinch-to-zoom gestures.
class ReaderContentTapDetector extends StatefulWidget {
  const ReaderContentTapDetector({
    super.key,
    required this.onTap,
    required this.child,
  });

  final VoidCallback onTap;
  final Widget child;

  @override
  State<ReaderContentTapDetector> createState() =>
      _ReaderContentTapDetectorState();
}

class _ReaderContentTapDetectorState extends State<ReaderContentTapDetector> {
  static const _dragTolerance = 18.0;
  static const _tapTimeout = Duration(milliseconds: 320);

  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  var _activePointers = 0;
  var _didMove = false;
  var _hadMultiplePointers = false;

  void _resetGesture() {
    _pointerDownPosition = null;
    _pointerDownAt = null;
    _activePointers = 0;
    _didMove = false;
    _hadMultiplePointers = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if (_activePointers == 0) {
        _pointerDownPosition = event.localPosition;
        _pointerDownAt = DateTime.now();
        _didMove = false;
        _hadMultiplePointers = false;
      } else {
        _hadMultiplePointers = true;
      }
      _activePointers += 1;
    },
    onPointerMove: (event) {
      final start = _pointerDownPosition;
      if (start != null &&
          (event.localPosition - start).distance > _dragTolerance) {
        _didMove = true;
      }
    },
    onPointerCancel: (_) => _resetGesture(),
    onPointerUp: (event) {
      final start = _pointerDownPosition;
      final downAt = _pointerDownAt;
      final wasSingleTap =
          _activePointers == 1 &&
          !_hadMultiplePointers &&
          !_didMove &&
          start != null &&
          downAt != null &&
          DateTime.now().difference(downAt) <= _tapTimeout;
      if (wasSingleTap) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final size = box.size;
          final position = event.localPosition;
          final inCenter =
              position.dx >= size.width * .25 &&
              position.dx <= size.width * .75 &&
              position.dy >= size.height * .25 &&
              position.dy <= size.height * .75;
          if (inCenter) widget.onTap();
        }
      }
      _resetGesture();
    },
    child: widget.child,
  );
}

class ReaderCompactTopBar extends StatelessWidget {
  const ReaderCompactTopBar({
    super.key,
    required this.title,
    this.contextLabel,
    required this.onBack,
    required this.onOpenMore,
    this.backKey,
    this.moreKey,
  });

  final String title;
  final String? contextLabel;
  final VoidCallback onBack;
  final VoidCallback onOpenMore;
  final Key? backKey;
  final Key? moreKey;

  @override
  Widget build(BuildContext context) {
    final contextText = contextLabel?.trim();
    final displayTitle = contextText == null || contextText.isEmpty
        ? title
        : '$title · $contextText';
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              ReaderChromeIconButton(
                key: backKey,
                tooltip: '返回书库',
                icon: Icons.arrow_back,
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  header: true,
                  label: displayTitle,
                  child: Text(
                    displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ReaderChromeIconButton(
                key: moreKey,
                tooltip: '更多阅读操作',
                icon: Icons.more_vert,
                onPressed: onOpenMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReaderCompactNavigationBar extends StatelessWidget {
  const ReaderCompactNavigationBar({
    super.key,
    required this.positionLabel,
    required this.onOpenToc,
    required this.onPrevious,
    required this.onNext,
    required this.onOpenStyle,
    this.onOpenProgress,
    this.tocTooltip = '章节目录',
    this.styleTooltip = '阅读样式',
    this.tocKey,
    this.previousKey,
    this.positionKey,
    this.nextKey,
    this.styleKey,
  });

  final String positionLabel;
  final VoidCallback? onOpenToc;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onOpenStyle;
  final VoidCallback? onOpenProgress;
  final String tocTooltip;
  final String styleTooltip;
  final Key? tocKey;
  final Key? previousKey;
  final Key? positionKey;
  final Key? nextKey;
  final Key? styleKey;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            ReaderChromeIconButton(
              key: tocKey,
              tooltip: tocTooltip,
              icon: Icons.menu_book_outlined,
              onPressed: onOpenToc,
            ),
            const SizedBox(width: ReaderChromeLayout.actionGap),
            ReaderChromeIconButton(
              key: previousKey,
              tooltip: '上一处',
              icon: Icons.chevron_left,
              onPressed: onPrevious,
            ),
            const SizedBox(width: ReaderChromeLayout.actionGap),
            Expanded(
              child: Semantics(
                key: positionKey,
                label: onOpenProgress == null
                    ? positionLabel
                    : '$positionLabel，打开阅读进度',
                button: onOpenProgress != null,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onOpenProgress,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: ReaderChromeLayout.minTouchTarget,
                    ),
                    child: Center(
                      child: Text(
                        positionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: ReaderChromeLayout.actionGap),
            ReaderChromeIconButton(
              key: nextKey,
              tooltip: '下一处',
              icon: Icons.chevron_right,
              onPressed: onNext,
            ),
            const SizedBox(width: ReaderChromeLayout.actionGap),
            ReaderChromeIconButton(
              key: styleKey,
              tooltip: styleTooltip,
              icon: Icons.tune_outlined,
              onPressed: onOpenStyle,
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showReaderProgressSheet(
  BuildContext context, {
  required String title,
  required String positionLabel,
  required double progress,
  required ValueChanged<double> onChangeEnd,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: false,
  builder: (context) => _ReaderProgressSheet(
    title: title,
    positionLabel: positionLabel,
    progress: progress,
    onChangeEnd: onChangeEnd,
  ),
);

class _ReaderActionSheet extends StatelessWidget {
  const _ReaderActionSheet({required this.title, required this.groups});

  final String title;
  final List<ReaderChromeActionGroup> groups;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: FractionallySizedBox(
      heightFactor: .75,
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  ReaderChromeIconButton(
                    tooltip: '关闭',
                    icon: Icons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, groupIndex) {
                  final group = groups[groupIndex];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                        child: Text(
                          group.title,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      for (final action in group.actions)
                        ListTile(
                          key: action.key ?? Key('reader-action-${action.id}'),
                          minVerticalPadding: 8,
                          leading: Icon(action.icon),
                          title: Text(action.label),
                          subtitle: action.enabled
                              ? null
                              : action.disabledDescription == null
                              ? null
                              : Text(action.disabledDescription!),
                          selected: action.selected,
                          enabled: action.enabled,
                          onTap: action.onPressed == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  Future<void>.delayed(
                                    Duration.zero,
                                    action.onPressed!,
                                  );
                                },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReaderProgressSheet extends StatefulWidget {
  const _ReaderProgressSheet({
    required this.title,
    required this.positionLabel,
    required this.progress,
    required this.onChangeEnd,
  });

  final String title;
  final String positionLabel;
  final double progress;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_ReaderProgressSheet> createState() => _ReaderProgressSheetState();
}

class _ReaderProgressSheetState extends State<_ReaderProgressSheet> {
  double? _draftProgress;

  @override
  Widget build(BuildContext context) {
    final progress = (_draftProgress ?? widget.progress).clamp(0, 1).toDouble();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(widget.positionLabel),
            const SizedBox(height: 12),
            Slider(
              value: progress,
              label: '${(progress * 100).round()}%',
              semanticFormatterCallback: (value) => '${(value * 100).round()}%',
              onChanged: (value) => setState(() => _draftProgress = value),
              onChangeEnd: (value) {
                setState(() => _draftProgress = null);
                widget.onChangeEnd(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}
