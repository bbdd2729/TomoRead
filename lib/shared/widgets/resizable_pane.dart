import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ResizablePaneEdge { leading, trailing }

class ResizablePane extends StatefulWidget {
  const ResizablePane({
    super.key,
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.child,
    required this.onWidthChanged,
    this.onWidthChangeEnd,
    this.defaultWidth,
    this.edge = ResizablePaneEdge.trailing,
  }) : assert(minWidth <= maxWidth),
       assert(width >= minWidth && width <= maxWidth);

  final double width;
  final double minWidth;
  final double maxWidth;
  final Widget child;
  final ValueChanged<double> onWidthChanged;
  final ValueChanged<double>? onWidthChangeEnd;
  final double? defaultWidth;
  final ResizablePaneEdge edge;

  @override
  State<ResizablePane> createState() => _ResizablePaneState();
}

class _ResizablePaneState extends State<ResizablePane> {
  late double _width;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _width = widget.width;
  }

  @override
  void didUpdateWidget(covariant ResizablePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && oldWidget.width != widget.width) {
      _width = widget.width;
    }
  }

  void _updateWidth(double delta) {
    final direction = widget.edge == ResizablePaneEdge.trailing ? 1 : -1;
    _setWidth(_width + delta * direction);
  }

  bool _setWidth(double targetWidth) {
    final value = targetWidth
        .clamp(widget.minWidth, widget.maxWidth)
        .toDouble();
    if (value == _width) return false;
    setState(() => _width = value);
    widget.onWidthChanged(value);
    return true;
  }

  void _changeWidthByKeyboard(double delta) {
    if (_setWidth(_width + delta)) {
      widget.onWidthChangeEnd?.call(_width);
    }
  }

  void _resetWidth() {
    final value =
        (widget.defaultWidth ?? (widget.minWidth + widget.maxWidth) / 2)
            .clamp(widget.minWidth, widget.maxWidth)
            .toDouble();
    setState(() => _width = value);
    widget.onWidthChanged(value);
    widget.onWidthChangeEnd?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final handle = _ResizeHandle(
      onDragStart: () => setState(() => _isDragging = true),
      onDragUpdate: _updateWidth,
      onDragEnd: () {
        setState(() => _isDragging = false);
        widget.onWidthChangeEnd?.call(_width);
      },
      onDoubleTap: _resetWidth,
      onIncrease: () => _changeWidthByKeyboard(8),
      onDecrease: () => _changeWidthByKeyboard(-8),
      value: _width,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
    );
    final pane = SizedBox(width: _width, child: widget.child);

    return switch (widget.edge) {
      ResizablePaneEdge.leading => Row(children: [handle, pane]),
      ResizablePaneEdge.trailing => Row(children: [pane, handle]),
    };
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDoubleTap,
    required this.onIncrease,
    required this.onDecrease,
    required this.value,
    required this.minWidth,
    required this.maxWidth,
  });

  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDoubleTap;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final double value;
  final double minWidth;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Resize panel',
      slider: true,
      value: '${value.round()} pixels',
      increasedValue: '${(value + 8).clamp(minWidth, maxWidth).round()} pixels',
      decreasedValue: '${(value - 8).clamp(minWidth, maxWidth).round()} pixels',
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      child: FocusableActionDetector(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _IncreasePanelSizeIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _DecreasePanelSizeIntent(),
        },
        actions: {
          _IncreasePanelSizeIntent: CallbackAction<_IncreasePanelSizeIntent>(
            onInvoke: (_) {
              onIncrease();
              return null;
            },
          ),
          _DecreasePanelSizeIntent: CallbackAction<_DecreasePanelSizeIntent>(
            onInvoke: (_) {
              onDecrease();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: onDoubleTap,
            onHorizontalDragStart: (_) => onDragStart(),
            onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
            onHorizontalDragEnd: (_) => onDragEnd(),
            onHorizontalDragCancel: onDragEnd,
            child: SizedBox(
              width: 8,
              child: Center(
                child: Container(width: 1, color: colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IncreasePanelSizeIntent extends Intent {
  const _IncreasePanelSizeIntent();
}

class _DecreasePanelSizeIntent extends Intent {
  const _DecreasePanelSizeIntent();
}
