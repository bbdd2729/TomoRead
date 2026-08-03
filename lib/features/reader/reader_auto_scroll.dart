import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/models/reader_commands.dart';

enum AutoScrollStopReason {
  explicit,
  userInput,
  selection,
  dialog,
  chapterChange,
  lifecycle,
  layoutUnavailable,
  reachedEnd,
}

class ReaderAutoScrollController extends ChangeNotifier {
  factory ReaderAutoScrollController({
    AutoScrollPreference preference = const AutoScrollPreference(),
  }) => ReaderAutoScrollController._(preference);

  ReaderAutoScrollController._(this._preference);

  AutoScrollPreference _preference;
  bool _active = false;
  AutoScrollStopReason? _lastStopReason;

  AutoScrollPreference get preference => _preference;
  bool get active => _active;
  AutoScrollStopReason? get lastStopReason => _lastStopReason;

  void updatePreference(AutoScrollPreference value) {
    if (_preference.unit == value.unit && _preference.speed == value.speed) {
      return;
    }
    _preference = value;
    notifyListeners();
  }

  void start() {
    if (_active) return;
    _active = true;
    _lastStopReason = null;
    notifyListeners();
  }

  void stop([AutoScrollStopReason reason = AutoScrollStopReason.explicit]) {
    if (!_active) return;
    _active = false;
    _lastStopReason = reason;
    notifyListeners();
  }

  void toggle() => active ? stop() : start();
}

class ReaderAutoScrollRegion extends StatefulWidget {
  const ReaderAutoScrollRegion({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.lineExtent,
    required this.child,
  });

  final ReaderAutoScrollController controller;
  final ScrollController scrollController;
  final double lineExtent;
  final Widget child;

  @override
  State<ReaderAutoScrollRegion> createState() =>
      _ReaderAutoScrollRegionState();
}

class _ReaderAutoScrollRegionState extends State<ReaderAutoScrollRegion>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _startOffset = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.controller.addListener(_syncTicker);
  }

  @override
  void didUpdateWidget(covariant ReaderAutoScrollRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncTicker);
      widget.controller.addListener(_syncTicker);
      _ticker.stop();
      _syncTicker();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncTicker);
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker() {
    if (!widget.controller.active) {
      _ticker.stop();
      return;
    }
    if (!widget.scrollController.hasClients) {
      widget.controller.stop(AutoScrollStopReason.layoutUnavailable);
      return;
    }
    if (_ticker.isActive) _ticker.stop();
    _startOffset = widget.scrollController.offset;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    if (!widget.controller.active || !widget.scrollController.hasClients) {
      return;
    }
    final position = widget.scrollController.position;
    final preference = widget.controller.preference;
    final pixelsPerSecond = switch (preference.unit) {
      AutoScrollUnit.linesPerMinute =>
        widget.lineExtent * preference.speed / 60,
      AutoScrollUnit.screensPerMinute =>
        position.viewportDimension * preference.speed / 60,
    };
    final target = _startOffset +
        pixelsPerSecond * elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (target >= position.maxScrollExtent) {
      position.jumpTo(position.maxScrollExtent);
      widget.controller.stop(AutoScrollStopReason.reachedEnd);
      return;
    }
    position.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _stopForPointer(PointerEvent _) =>
      widget.controller.stop(AutoScrollStopReason.userInput);

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _stopForPointer,
    onPointerSignal: (event) {
      if (event is PointerScrollEvent) _stopForPointer(event);
    },
    child: NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.dragDetails != null) {
          widget.controller.stop(AutoScrollStopReason.userInput);
        }
        return false;
      },
      child: widget.child,
    ),
  );
}
