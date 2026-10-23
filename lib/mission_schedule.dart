import 'resource_history.dart';

/// Calendar periods for checklist resets, always in Malaysia time.
abstract final class MissionSchedule {
  static String weekKey(DateTime time) {
    final utc = time.toUtc();
    final myt = utc.add(const Duration(hours: 8));
    return ResourceHistory.dateKey(
      utc.subtract(Duration(days: myt.weekday - DateTime.monday)),
    );
  }
}
