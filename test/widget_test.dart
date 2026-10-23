import 'dart:convert';
import 'package:bd2/main.dart';
import 'package:bd2/resource_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets('Fantasy theme fits phone and reward keyboard at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final reward = find.text('0 钻石 · 填写实际奖励').first;
      await tester.ensureVisible(reward);
      await tester.pumpAndSettle();
      await tester.tap(reward);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'MYT midnight resets daily checks, persists data and keeps weekly rewards',
    (tester) async {
      var now = DateTime.utc(2026, 10, 16, 15, 59, 59);
      SharedPreferences.setMockInitialValues({
        'checklist_v1': jsonEncode({
          'dailyDate': '2026-10-16',
          'done': ['0:1', '1:0'],
          'amounts': {'0:1': 75},
          'resources': <String, dynamic>{},
          'completedDates': {'0:1': '2026-10-16', '1:0': '2026-10-16'},
          'history': {
            '2026-10-16': {'钻石': 275},
          },
        }),
      });
      await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
      await tester.pumpAndSettle();
      expect(find.text('1/16 完成'), findsOneWidget);
      now = DateTime.utc(2026, 10, 16, 16);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('0/16 完成'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '275 钻石',
      );
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('checklist_v1')!) as Map;
      expect(saved['dailyDate'], '2026-10-17');
      expect(saved['done'], ['1:0']);
      expect((saved['amounts'] as Map).containsKey('0:1'), false);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: MissionPage(now: () => now)));
      await tester.pumpAndSettle();
      expect(find.text('0/16 完成'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '275 钻石',
      );
    },
  );

  testWidgets('Opening after missed midnight catches up and saves reset', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'checklist_v1': jsonEncode({
        'dailyDate': '2026-10-15',
        'done': ['0:1'],
        'amounts': <String, int>{},
        'resources': <String, dynamic>{},
        'completedDates': {'0:1': '2026-10-15'},
        'history': {
          '2026-10-15': {'钻石': 60},
        },
      }),
    });
    await tester.pumpWidget(
      MaterialApp(home: MissionPage(now: () => DateTime.utc(2026, 10, 16, 16))),
    );
    await tester.pumpAndSettle();
    expect(find.text('0/16 完成'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
      '60 钻石',
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('checklist_v1')!) as Map;
    expect(saved['dailyDate'], '2026-10-17');
    expect(saved['done'], isEmpty);
  });
  testWidgets(
    'Expired daily records are removed from local storage on opening',
    (tester) async {
      final now = DateTime.now();
      final today = ResourceHistory.dateKey(now);
      final boundary = ResourceHistory.dateKey(
        DateTime(now.year, now.month, now.day - 6),
      );
      final expired = ResourceHistory.dateKey(
        DateTime(now.year, now.month, now.day - 7),
      );
      SharedPreferences.setMockInitialValues({
        'checklist_v1': jsonEncode({
          'done': ['0:1'],
          'amounts': <String, int>{},
          'resources': <String, dynamic>{},
          'completedDates': {'0:1': expired},
          'history': {
            expired: {'钻石': 60},
            boundary: {'钻石': 20},
            today: {'钻石': 30},
          },
        }),
      });
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '50 钻石',
      );
      expect(find.text('0/16 完成'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('checklist_v1')!) as Map;
      expect((saved['history'] as Map).containsKey(expired), false);
      expect(saved['done'], isEmpty);
      expect(saved.containsKey('archived'), false);
    },
  );

  testWidgets(
    'Legacy checked tasks migrate once and undated archive is removed',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'checklist_v1': jsonEncode({
          'done': ['0:1'],
          'amounts': <String, int>{},
          'resources': <String, dynamic>{},
          'archived': {'钻石': 10000},
        }),
      });
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '60 钻石',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '60 钻石',
      );
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('checklist_v1')!) as Map;
      expect(saved.containsKey('archived'), false);
      expect((saved['history'] as Map).length, 1);
    },
  );
  testWidgets(
    'Seven-day resources survive reset and restart without double counting',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('0 钻石 · 填写实际奖励').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '30');
      await tester.enterText(find.widgetWithText(TextFormField, '抽卡券'), '3');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('0:0')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '30 钻石',
      );
      expect(find.text('抽卡券 3'), findsOneWidget);
      await tester.tap(find.text('重置清单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
        '0 钻石',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '30 钻石',
      );
      expect(find.text('抽卡券 3'), findsOneWidget);
      await tester.tap(find.text('重置清单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '30 钻石',
      );
      expect(find.text('抽卡券 3'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('0:1')),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('0:1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '90 钻石',
      );
      await tester.tap(find.byKey(const ValueKey('0:1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('sevenDayGems'))).data,
        '30 钻石',
      );
    },
  );
  testWidgets('Fixed rewards toggle, persist and reset independently', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('0/16 完成'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('0:1')),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('0:1')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
      '60 钻石',
    );
    await tester.tap(find.text('每周任务'));
    await tester.pumpAndSettle();
    expect(find.text('0/12 完成'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('1:0')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
      '260 钻石',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
      '260 钻石',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('0:1')),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('0:1')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
      '200 钻石',
    );
    await tester.tap(find.text('重置清单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
      '200 钻石',
    );
  });

  testWidgets('Actual rewards validate and count only when checked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('0 钻石 · 填写实际奖励').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '-1');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 0 至 100000000 的整数'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '25');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
      '0 钻石',
    );
    await tester.tap(find.byKey(const ValueKey('0:0')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
      '25 钻石',
    );
    await tester.tap(find.text('重置清单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('totalGems'))).data,
      '0 钻石',
    );
    expect(find.text('25 钻石 · 填写实际奖励'), findsNothing);
  });
}
