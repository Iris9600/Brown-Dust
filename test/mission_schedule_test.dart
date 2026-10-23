import 'dart:convert';
import 'package:bd2/main.dart';
import 'package:bd2/mission_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> progress({
  String day = '2026-10-18',
  String? week = '2026-10-12',
}) => {
  'dailyDate': day,
  'weeklyDate': ?week,
  'done': ['0:1', '1:0'],
  'amounts': {'0:1': 75, '1:0': 240},
  'resources': {
    '0:1': {'钻石': 75, '抽卡券': 1},
    '1:0': {'钻石': 240, '抽卡券': 3},
  },
  'completedDates': {'0:1': day, '1:0': day},
  'history': {
    day: {'钻石': 315, '抽卡券': 4},
  },
};
Future<Map<String, dynamic>> saved() async =>
    jsonDecode(
          (await SharedPreferences.getInstance()).getString('checklist_v1')!,
        )
        as Map<String, dynamic>;
void seed(Map<String, dynamic> data) =>
    SharedPreferences.setMockInitialValues({'checklist_v1': jsonEncode(data)});

void main() {
  test('Weekly boundary is Monday 00:00 MYT, including year rollover', () {
    expect(
      MissionSchedule.weekKey(DateTime.utc(2026, 10, 18, 15, 59, 59)),
      '2026-10-12',
    );
    expect(
      MissionSchedule.weekKey(DateTime.utc(2026, 10, 18, 16)),
      '2026-10-19',
    );
    expect(
      MissionSchedule.weekKey(DateTime.utc(2026, 12, 31, 18)),
      '2026-12-28',
    );
    expect(MissionSchedule.weekKey(DateTime.utc(2027, 1, 3, 16)), '2027-01-04');
  });

  testWidgets(
    'Active Monday midnight resets both periods and keeps dated earnings',
    (tester) async {
      var now = DateTime.utc(2026, 10, 18, 15, 59, 59);
      seed(progress());
      await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
      await tester.pumpAndSettle();
      now = DateTime.utc(2026, 10, 18, 16);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final data = await saved();
      expect(data['dailyDate'], '2026-10-19');
      expect(data['weeklyDate'], '2026-10-19');
      expect(data['done'], isEmpty);
      expect(data['amounts'], isEmpty);
      expect(data['resources'], isEmpty);
      expect(data['completedDates'], isEmpty);
      expect(data['history'], {
        '2026-10-18': {'钻石': 315, '抽卡券': 4},
      });
      await tester.tap(find.text('每周任务'));
      await tester.pumpAndSettle();
      expect(find.text('200 钻石 · 填写实际奖励'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Non-Monday daily midnight preserves every weekly field', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 16, 15, 59, 59);
    seed(progress(day: '2026-10-16'));
    await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
    await tester.pumpAndSettle();
    now = DateTime.utc(2026, 10, 16, 16);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final data = await saved();
    expect(data['done'], ['1:0']);
    expect(data['amounts'], {'1:0': 240});
    expect(data['resources'], {
      '1:0': {'钻石': 240, '抽卡券': 3},
    });
    expect(data['completedDates'], {'1:0': '2026-10-16'});
    expect(data['weeklyDate'], '2026-10-12');
    await tester.pumpWidget(const SizedBox());
  });

  for (final legacy in [false, true]) {
    testWidgets(
      'Opening catches missed Monday, legacy=$legacy, and persists the reset',
      (tester) async {
        seed(progress(week: legacy ? null : '2026-10-12'));
        final now = DateTime.utc(2026, 10, 19, 4);
        await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
        await tester.pumpAndSettle();
        var data = await saved();
        expect(data['done'], isEmpty);
        expect(data['weeklyDate'], '2026-10-19');
        expect(data['history'], {
          '2026-10-18': {'钻石': 315, '抽卡券': 4},
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
        await tester.pumpAndSettle();
        data = await saved();
        expect(data['done'], isEmpty);
        expect(data['weeklyDate'], '2026-10-19');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final tab in [0, 1]) {
    testWidgets('Manual reset of tab $tab leaves the other checklist intact', (
      tester,
    ) async {
      seed(progress(day: '2026-10-16'));
      final now = DateTime.utc(2026, 10, 16, 4);
      await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
      await tester.pumpAndSettle();
      if (tab == 1) {
        await tester.tap(find.text('每周任务'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('重置清单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      final data = await saved();
      final otherId = tab == 0 ? '1:0' : '0:1';
      expect(data['done'], [otherId]);
      expect((data['amounts'] as Map).keys, [otherId]);
      expect((data['resources'] as Map).keys, [otherId]);
      expect((data['completedDates'] as Map).keys, [otherId]);
      expect(data['history'], {
        '2026-10-16': {'钻石': 315, '抽卡券': 4},
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'Weekly editor opened on Sunday cannot restore stale values after Monday reset',
    (tester) async {
      var now = DateTime.utc(2026, 10, 18, 15, 59, 59);
      seed(progress());
      await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('每周任务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('240 钻石 · 填写实际奖励'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '999');
      now = DateTime.utc(2026, 10, 18, 16);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final data = await saved();
      expect(data['amounts'], isEmpty);
      expect(data['done'], isEmpty);
      expect(data['weeklyDate'], '2026-10-19');
      expect(find.text('已到马来西亚新一周，请重新填写本周奖励。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Resuming after Monday catches up without waiting for a timer', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 18, 12);
    seed(progress());
    await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime.utc(2026, 10, 19, 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final data = await saved();
    expect(data['done'], isEmpty);
    expect(data['weeklyDate'], '2026-10-19');
    expect(data['history'], {
      '2026-10-18': {'钻石': 315, '抽卡券': 4},
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Weekly editor survives a daily midnight within the same week', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 16, 15, 59, 59);
    seed(progress(day: '2026-10-16'));
    await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('240 钻石 · 填写实际奖励'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '250');
    now = DateTime.utc(2026, 10, 16, 16);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final data = await saved();
    expect(data['done'], ['1:0']);
    expect(data['amounts'], {'1:0': 250});
    expect(data['completedDates'], {'1:0': '2026-10-16'});
    expect((data['history'] as Map).keys, ['2026-10-16']);
    expect((data['history'] as Map)['2026-10-16'], containsPair('钻石', 325));
    expect((data['history'] as Map)['2026-10-16'], containsPair('抽卡券', 4));
    await tester.pumpWidget(const SizedBox());
  });
}
