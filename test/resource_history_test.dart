import 'package:bd2/resource_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Keeps exactly the calendar window across month and year boundaries',
    () {
      final history = ResourceHistory({
        '2025-12-25': {'钻石': 1000},
        '2025-12-26': {'钻石': 10},
        '2025-12-31': {'钻石': 20, '抽卡券': 2},
        '2026-01-01': {'钻石': 30},
        '2026-01-02': {'钻石': 999},
      });
      history.prune(DateTime.utc(2026, 1, 1, 15, 59));
      expect(
        history.days.keys,
        unorderedEquals(['2025-12-26', '2025-12-31', '2026-01-01']),
      );
      expect(history.total('钻石'), 60);
      expect(history.total('抽卡券'), 2);
      history.prune(DateTime.utc(2026, 1, 1, 16));
      expect(history.days.containsKey('2025-12-26'), false);
      expect(history.total('钻石'), 50);
      history.prune(DateTime(2026, 2, 1));
      expect(history.days, isEmpty);
    },
  );

  test('Corrections affect original date without moving rewards to today', () {
    final history = ResourceHistory();
    history.adjust('2026-10-15', {'钻石': 60, '抽卡券': 2}, 1);
    history.adjust('2026-10-15', {'钻石': 60, '抽卡券': 2}, -1);
    history.adjust('2026-10-15', {'钻石': 80, '抽卡券': 3}, 1);
    history.adjust('2026-10-16', {'钻石': 200}, 1);
    expect(history.days['2026-10-15']!['钻石'], 80);
    expect(history.total('钻石'), 280);
    expect(history.total('抽卡券'), 3);
  });

  test('Malaysia midnight is 16:00 UTC regardless of device time zone', () {
    final before = DateTime.utc(2026, 10, 16, 15, 59, 59);
    final after = DateTime.utc(2026, 10, 16, 16);
    expect(ResourceHistory.dateKey(before), '2026-10-16');
    expect(ResourceHistory.dateKey(after), '2026-10-17');
    expect(ResourceHistory.untilMidnight(before), const Duration(seconds: 1));
    expect(ResourceHistory.untilMidnight(after), const Duration(days: 1));
  });
}
