import 'dart:convert';
import 'dart:io';
import 'package:bd2/announcements/news_hub.dart';
import 'package:bd2/announcements/news_notifications.dart';
import 'package:bd2/announcements/official_news.dart';
import 'package:bd2/announcements/youtube_banners.dart';
import 'package:bd2/app_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'official_news_test.dart' as fixtures;

class FakeYoutube extends YoutubeBannerRepository {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
}

class FakeNotifications extends NewsNotifications {
  bool permission = true, enabled = false;
  int enableCalls = 0, observed = 0;
  final categories = <String, bool>{};
  @override
  bool get supported => true;
  @override
  Future<Map<String, dynamic>> status() async => {
    'supported': true,
    'permission': permission,
    'enabled': enabled,
    ...categories,
    'reminders': [],
    'alerts': [],
  };
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> setEnabled(bool value) async {
    enabled = value;
    enableCalls++;
  }

  @override
  Future<void> setCategory(String category, bool value) async {
    categories[category] = value;
  }

  @override
  Future<void> observe(List<OfficialNews> items) async {
    observed++;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('October API announcements appear in Events and Updates', (
    tester,
  ) async {
    final fixture = File(
      'test/fixtures/official_notices.json',
    ).readAsStringSync();
    final rows = (jsonDecode(fixture)['items'] as List).cast<Map>();
    final repository = NewsRepository(
      now: () => DateTime.utc(2026, 10, 19),
      client: MockClient((request) async {
        if (request.url.path == '/api/notices') {
          return http.Response.bytes(utf8.encode(fixture), 200);
        }
        final item = rows.singleWhere(
          (row) => row['id'] == request.url.path.split('/').last,
        );
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({...item, 'content': 'Complete announcement'}),
          ),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme,
        home: NewsHub(
          repository: repository,
          notifications: FakeNotifications(),
          youtubeRepository: FakeYoutube(),
          now: () => DateTime.utc(2026, 10, 19),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final event =
        rows.singleWhere((row) => row['category'] == 'event')['subject']
            as String;
    final notice =
        rows.singleWhere((row) => row['category'] == 'notice')['subject']
            as String;
    final maintenance =
        rows.singleWhere((row) => row['category'] == 'inspection')['subject']
            as String;
    expect(find.text(event.trim()), findsOneWidget);
    expect(find.text(notice.trim()), findsNothing);
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.text(notice.trim()), findsOneWidget);
    expect(find.text(maintenance.trim()), findsOneWidget);
    expect(find.text(event.trim()), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Official pages, detail and notification controls fit width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = NewsRepository(
          client: MockClient(
            (request) async => http.Response(
              fixtures.feed([
                fixtures.row(
                  '1',
                  'Event announcement',
                  tag: 'event',
                  content: 'Event dates in original notice',
                ),
                fixtures.row(
                  '2',
                  'Patch notice',
                  content: 'Event update and pick-up information',
                ),
              ]),
              200,
            ),
          ),
        );
        final notifications = FakeNotifications();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme,
            home: NewsHub(
              repository: repository,
              notifications: notifications,
              now: () => DateTime.utc(2026, 10, 19),
              youtubeRepository: FakeYoutube(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Event announcement'), findsOneWidget);
        await tester.tap(find.text('更新'));
        await tester.pumpAndSettle();
        expect(find.text('Patch notice'), findsOneWidget);
        await tester.tap(find.text('召唤卡池'));
        await tester.pumpAndSettle();
        expect(find.text('Patch notice'), findsNothing);
        expect(find.text('暂无可确认的召唤卡池'), findsOneWidget);
        await tester.tap(find.text('更新'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Patch notice'));
        await tester.pumpAndSettle();
        expect(find.text('打开官方原文'), findsOneWidget);
        expect(find.text('设置提醒'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('通知'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(SwitchListTile, '自动公告通知'));
        await tester.pumpAndSettle();
        expect(notifications.enabled, true);
        expect(notifications.enableCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Denied permission never enables background announcements', (
    tester,
  ) async {
    final notifications = FakeNotifications()..permission = false;
    final repository = NewsRepository(
      client: MockClient(
        (request) async =>
            http.Response(fixtures.feed([fixtures.row('1', 'Notice')]), 200),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme,
        home: NewsHub(
          initialTab: 3,
          youtubeRepository: FakeYoutube(),
          repository: repository,
          notifications: notifications,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '自动公告通知'));
    await tester.pumpAndSettle();
    expect(notifications.enabled, false);
    expect(notifications.enableCalls, 0);
    expect(find.text('通知权限未开启。可前往系统设置允许通知。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
