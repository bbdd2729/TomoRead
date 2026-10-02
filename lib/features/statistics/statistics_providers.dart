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
          label: 'مدة القراءة',
          value: formatReadingDuration(summary.activeMillis),
          icon: 'time',
        ),
        StatsMetricViewModel(
          label: 'أيام النشاط',
          value: '${summary.activeDays}يوم',
          icon: 'calendar',
        ),
        StatsMetricViewModel(
          label: 'تيار مستمر',
          value: '${summary.currentStreak}يوم',
          icon: 'streak',
        ),
        StatsMetricViewModel(
          label: 'قراءة كتاب',
          value: '${summary.booksTouched}حجز',
          icon: 'books',
        ),
      ],
    );
  });
});

String formatReadingDuration(int milliseconds) {
  final minutes = (milliseconds / 60000).round();
  if (minutes < 60) return '$minutes دقيقة';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours ساعة' : '$hours ساعة $rest دقيقة';
}
