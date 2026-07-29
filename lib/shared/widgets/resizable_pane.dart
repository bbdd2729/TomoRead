import 'package:flutter/material.dart';

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
    final value = (_width + delta * direction)
        .clamp(widget.minWidth, widget.maxWidth)
        .toDouble();
    if (value == _width) return;
    setState(() => _width = value);
    widget.onWidthChanged(value);
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
  });

  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
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
    );
  }
}
