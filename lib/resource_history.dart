/// Malaysia calendar-day earnings, independent of the device's time zone.
class ResourceHistory {
  ResourceHistory([Map<String, Map<String, int>>? records])
    : days = records ?? {};

  final Map<String, Map<String, int>> days;

  static String dateKey(DateTime time) {
    final local = time.toUtc().add(const Duration(hours: 8));
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static List<String> retainedDates(DateTime now) {
    final local = now.toUtc().add(const Duration(hours: 8));
    return List.generate(
      7,
      (offset) => dateKey(
        DateTime.utc(
          local.year,
          local.month,
          local.day - offset,
        ).subtract(const Duration(hours: 8)),
      ),
    );
  }

  static Duration untilMidnight(DateTime now) {
    final malaysia = now.toUtc().add(const Duration(hours: 8));
    final midnight = DateTime.utc(
      malaysia.year,
      malaysia.month,
      malaysia.day + 1,
    ).subtract(const Duration(hours: 8));
    return midnight.difference(now.toUtc());
  }

  void prune(DateTime now) {
    final retained = retainedDates(now).toSet();
    days.removeWhere((date, _) => !retained.contains(date));
  }

  void adjust(String date, Map<String, int> rewards, int direction) {
    final day = days.putIfAbsent(date, () => {});
    for (final reward in rewards.entries) {
      final amount = (day[reward.key] ?? 0) + direction * reward.value;
      if (amount < 0) throw StateError('Negative daily resource balance');
      day[reward.key] = amount;
    }
  }

  int total(String resource) =>
      days.values.fold(0, (sum, day) => sum + (day[resource] ?? 0));
}
