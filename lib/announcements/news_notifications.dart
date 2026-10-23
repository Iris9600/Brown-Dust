import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'official_news.dart';

class NewsNotifications {
  static const channel = MethodChannel('bd2/announcements');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<Map<String, dynamic>> status() async {
    if (!supported) return {'supported': false};
    final value = await channel.invokeMapMethod<String, dynamic>('status');
    return {'supported': true, ...?value};
  }

  Future<bool> requestPermission() async =>
      supported &&
      await channel.invokeMethod<bool>('requestPermission') == true;
  Future<void> setEnabled(bool enabled) async {
    if (!supported) throw UnsupportedError('Android only');
    await channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
  }

  Future<void> setCategory(String category, bool enabled) async =>
      channel.invokeMethod<void>('setCategory', {
        'category': category,
        'enabled': enabled,
      });
  /// The native side accepts at most this many posts, matching the newest-100
  /// window its background job fetches.
  static const observeLimit = 100;

  Future<void> observe(List<OfficialNews> items) async {
    if (supported && items.isNotEmpty) {
      final newest = [...items]
        ..sort(
          (a, b) => (b.publishedAt ?? DateTime.utc(1970)).compareTo(
            a.publishedAt ?? DateTime.utc(1970),
          ),
        );
      await channel.invokeMethod<void>('observe', {
        'items': newest
            .take(observeLimit)
            .map((e) => e.notificationData())
            .toList(),
      });
    }
  }

  Future<void> schedule(
    OfficialNews item,
    DateTime time, {
    String? reminderId,
    String? title,
  }) async {
    await channel.invokeMethod<void>('schedule', {
      'id': reminderId ?? item.id,
      'title': title ?? item.title,
      'url': item.url.toString(),
      'at': time.millisecondsSinceEpoch,
    });
  }

  Future<void> cancel(String id) async =>
      channel.invokeMethod<void>('cancelReminder', {'id': id});
  Future<void> test() async => channel.invokeMethod<void>('test');
  Future<void> settings() async => channel.invokeMethod<void>('settings');
}
