import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/stats_report_service.dart';
import '../../domain/models/stats_models.dart';

final statisticsSelectionProvider =
    NotifierProvider<StatisticsSelectionNotifier, StatsSelection>(
      StatisticsSelectionNotifier.new,
    );

class StatisticsSelectionNotifier extends Notifier<StatsSelection> {
  @override
  StatsSelection build() => StatsSelection(anchor: DateTime.now());

  void setDimension(StatsDimension dimension) {
    state = StatsSelection(dimension: dimension, anchor: DateTime.now());
  }

  void move(int direction) {
    if (state.dimension == StatsDimension.lifetime) return;
    state = state.copyWith(anchor: shiftStatsAnchor(state, direction));
  }

  void resetToCurrent() => state = state.copyWith(anchor: DateTime.now());
}

final statsReportProvider = FutureProvider<StatsReport>((ref) {
  ref.watch(statisticsRevisionProvider);
  final selection = ref.watch(statisticsSelectionProvider);
  return ref.watch(statsReportServiceProvider).loadReport(selection);
});

class StatsMetricViewModel {
  const StatsMetricViewModel({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final String icon;
}

class StatsPageViewModel {
  const StatsPageViewModel({required this.report, required this.metrics});

  final StatsReport report;
  final List<StatsMetricViewModel> metrics;
}

final statsViewModelProvider = Provider<AsyncValue<StatsPageViewModel>>((ref) {
  return ref.watch(statsReportProvider).whenData((report) {
    final summary = report.summary;
    return StatsPageViewModel(
      report: report,
      metrics: [
        StatsMetricViewModel(
          label: '阅读时长',
          value: formatReadingDuration(summary.activeMillis),
          icon: 'time',
        ),
        StatsMetricViewModel(
          label: '活动天数',
          value: '${summary.activeDays} 天',
          icon: 'calendar',
        ),
        StatsMetricViewModel(
          label: '当前连续',
          value: '${summary.currentStreak} 天',
          icon: 'streak',
        ),
        StatsMetricViewModel(
          label: '阅读书籍',
          value: '${summary.booksTouched} 本',
          icon: 'books',
        ),
      ],
    );
  });
});

String formatReadingDuration(int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
}
