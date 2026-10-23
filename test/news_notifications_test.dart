import 'package:bd2/announcements/news_notifications.dart';
import 'package:bd2/announcements/official_news.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NewsNotifications.channel, (call) async {
          calls.add(call);
          if (call.method == 'status') {
            return {
              'enabled': false,
              'permission': false,
              'reminders': [],
              'alerts': [],
            };
          }
          if (call.method == 'requestPermission') return false;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NewsNotifications.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'Notification permission denial remains false and never enables implicitly',
    () async {
      final notifications = NewsNotifications();
      expect(await notifications.requestPermission(), false);
      expect(calls.map((call) => call.method), ['requestPermission']);
    },
  );
  test(
    'Background and foreground share the official ID, locale and epoch revision',
    () async {
      final item = OfficialNews(
        id: 'id',
        title: 'Post',
        content: 'pick-up',
        tag: 'notice',
        locale: 'en-us',
        updatedAt: DateTime.utc(2026, 10, 16, 4),
      );
      await NewsNotifications().observe([item]);
      final record =
          ((calls.single.arguments as Map)['items'] as List).single as Map;
      expect(record['locale'], 'en-us');
      expect(
        record['revision'],
        DateTime.utc(2026, 10, 16, 4).millisecondsSinceEpoch.toString(),
      );
      expect(record['url'], 'https://www.browndust2.com/en-us/news/view?id=id');
      expect(record['categories'], contains('banners'));
    },
  );
  test(
    'Reminder sends an absolute instant independent of phone time zone',
    () async {
      final item = OfficialNews(
        id: 'id',
        title: 'Post',
        content: '',
        tag: '',
        locale: 'zh-cn',
      );
      final at = DateTime.parse('2026-10-17T00:00:00+08:00');
      await NewsNotifications().schedule(item, at);
      expect(calls.single.method, 'schedule');
      expect(
        (calls.single.arguments as Map)['at'],
        DateTime.utc(2026, 10, 16, 16).millisecondsSinceEpoch,
      );
      await NewsNotifications().cancel('id');
      expect(calls.last.method, 'cancelReminder');
      expect(calls.last.arguments, {'id': 'id'});
    },
  );
  test('Other platforms do not invoke Android notification methods', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(await NewsNotifications().status(), {'supported': false});
    expect(await NewsNotifications().requestPermission(), false);
    await NewsNotifications().observe([]);
    expect(calls, isEmpty);
  });
  test(
    'Two units from one post receive independent reminder IDs and names',
    () async {
      final item = OfficialNews(
        id: 'post',
        title: 'Patch notice',
        content: '',
        tag: '',
        locale: 'en-us',
      );
      final at = DateTime.utc(2026, 10, 17);
      final notifications = NewsNotifications();
      await notifications.schedule(
        item,
        at,
        reminderId: 'banner:post:alice',
        title: 'Moonlight Alice',
      );
      await notifications.schedule(
        item,
        at,
        reminderId: 'banner:post:beth',
        title: 'Forest Beth',
      );
      expect((calls[0].arguments as Map)['id'], 'banner:post:alice');
      expect((calls[1].arguments as Map)['id'], 'banner:post:beth');
      expect((calls[0].arguments as Map)['title'], 'Moonlight Alice');
      expect((calls[1].arguments as Map)['title'], 'Forest Beth');
      expect(
        (calls[0].arguments as Map)['url'],
        (calls[1].arguments as Map)['url'],
      );
    },
  );
}
