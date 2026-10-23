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
  Future<void> observe(List<OfficialNews> items) async {
    if (supported && items.isNotEmpty) {
      await channel.invokeMethod<void>('observe', {
        'items': items.map((e) => e.notificationData()).toList(),
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
