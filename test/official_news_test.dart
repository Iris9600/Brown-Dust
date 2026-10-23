import 'dart:convert';
import 'dart:io';
import 'package:bd2/announcements/official_news.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> row(
  String id,
  String title, {
  String tag = 'notice',
  String content = '',
  String date = '2026-10-16T04:00:00.000Z',
}) => {
  'id': id,
  'attributes': {
    'subject': title,
    'tag': tag,
    'content': content,
    'publishedAt': date,
  },
};
String feed(List<Map<String, dynamic>> rows) => jsonEncode({'data': rows});
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Active news cache deletes messages when the cutoff advances', (
    tester,
  ) async {
    var now = DateTime.utc(2027, 1, 19);
    final repository = NewsRepository(
      now: () => now,
      client: MockClient(
        (_) async => http.Response(
          feed([
            row('boundary', 'Boundary notice', date: '2026-11-19T00:00:00Z'),
            row('recent', 'Recent notice', date: '2027-01-18T00:00:00Z'),
          ]),
          200,
        ),
      ),
    );
    await repository.initialize();
    expect(repository.items.length, 2);
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(repository.items.map((item) => item.id), ['recent']);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('official_news_cache_v1'),
      isNot(contains('Boundary notice')),
    );
    repository.dispose();
  });
  test(
    'Old cached messages are deleted offline and as the calendar advances',
    () async {
      var now = DateTime.utc(2027, 1, 19);
      final posts = parseOfficialNews(
        feed([
          row('old', 'Old event', tag: 'event', date: '2026-11-18T23:59:59Z'),
          row('boundary', 'Boundary notice', date: '2026-11-19T00:00:00Z'),
          row('recent', 'January notice', date: '2027-01-18T00:00:00Z'),
        ]),
      );
      SharedPreferences.setMockInitialValues({
        'official_news_cache_v1': jsonEncode({
          'savedAt': '2027-01-18T00:00:00Z',
          'items': posts.map((post) => post.toJson()).toList(),
        }),
      });
      final repository = NewsRepository(
        now: () => now,
        client: MockClient((_) async => http.Response('Offline', 503)),
      );
      await repository.initialize();
      final prefs = await SharedPreferences.getInstance();
      List<String> storedIds() =>
          (jsonDecode(prefs.getString('official_news_cache_v1')!)['items']
                  as List)
              .map((item) => item['id'] as String)
              .toList();
      expect(repository.items.map((item) => item.id), ['recent', 'boundary']);
      expect(storedIds(), ['recent', 'boundary']);
      now = DateTime.utc(2027, 1, 20);
      await repository.pruneExpired();
      expect(repository.items.map((item) => item.id), ['recent']);
      expect(storedIds(), ['recent']);
      repository.dispose();
    },
  );
  test(
    'Deleting an old article keeps its active summon card without the article body',
    () async {
      var now = DateTime.utc(2027, 1, 19);
      final source = parseOfficialNews(
        feed([
          row(
            'old-banner',
            'New Pickup - Moonlight Alice',
            date: '2026-09-01T00:00:00Z',
            content:
                '<img src="/alice.jpg"><p>Pick-up Period: 2027/01/01 00:00 ~ 2027/01/29 23:59 UTC</p>',
          ),
        ]),
      ).single;
      SharedPreferences.setMockInitialValues({
        'official_news_cache_v1': jsonEncode({
          'items': [source.toJson()],
        }),
      });
      NewsRepository repository() => NewsRepository(
        now: () => now,
        client: MockClient((_) async => http.Response('Offline', 503)),
      );
      final first = repository();
      await first.initialize();
      expect(first.items, isEmpty);
      expect(first.banners.single.name, 'Moonlight Alice');
    expect(first.banners.single.source.content, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final cached = jsonDecode(prefs.getString('official_news_cache_v1')!);
      expect(cached['items'], isEmpty);
      expect(cached['banners'].single['source']['content'], '');
      first.dispose();
      final reopened = repository();
      await reopened.initialize();
      expect(reopened.items, isEmpty);
      expect(reopened.banners.single.name, 'Moonlight Alice');
      now = DateTime.utc(2027, 1, 30);
      await reopened.pruneExpired();
      expect(reopened.banners, isEmpty);
      reopened.dispose();
    },
  );
  test(
    'Live October API shape supplies events and maintenance, not the retired May export',
    () async {
      final fixture = File(
        'test/fixtures/official_notices.json',
      ).readAsStringSync();
      final calls = <Uri>[];
      final repository = NewsRepository(
        now: () => DateTime.utc(2026, 10, 19),
        client: MockClient((request) async {
          calls.add(request.url);
          if (request.url.path != '/api/notices') {
            final id = request.url.path.split('/').last;
            final item = (jsonDecode(fixture)['items'] as List)
                .cast<Map>()
                .singleWhere((item) => item['id'] == id);
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  ...item,
                  'content': 'Full October announcement',
                  'contentHtml': '<p>Full October announcement</p>',
                }),
              ),
              200,
            );
          }
          return http.Response.bytes(utf8.encode(fixture), 200);
        }),
      );
      await repository.initialize();
      expect(repository.error, isNull);
      expect(calls.every((url) => url.host == 'webapi.browndust2.com'), isTrue);
      final events = recentNews(
        repository.items,
        category: NewsCategory.events,
        now: repository.now(),
      );
      final updates = recentNews(
        repository.items,
        category: NewsCategory.updates,
        now: repository.now(),
      );
      expect(events.length, 1);
      expect(updates.length, 2);
      expect(updates.any((item) => item.tag == 'maintenance'), isTrue);
      expect(
        repository.items.first.publishedAt,
        DateTime.parse('2026-10-17T03:00:07.129Z'),
      );
      final detail = await repository.loadDetail(events.single);
      expect(detail.text, 'Full October announcement');
      expect(detail.isPreview, isFalse);
      repository.dispose();
    },
  );
  test(
    'API pagination fetches every page up to the two-month cutoff',
    () async {
      final pages = <int>[];
      final repository = NewsRepository(
        now: () => DateTime.utc(2026, 10, 19),
        client: MockClient((request) async {
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add(page);
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': '$page',
                  'subject': 'Notice',
                  'category': 'notice',
                  'publishedAt': [
                    '2026-10-17T00:00:00Z',
                    '2026-09-01T00:00:00Z',
                    '2026-08-01T00:00:00Z',
                  ][page],
                  'contentPreview': 'Official preview',
                },
              ],
              'page': page,
              'totalPages': 30,
            }),
            200,
          );
        }),
      );
      await repository.initialize();
      expect(pages, [0, 1, 2]);
      expect(repository.items.length, 2);
      expect(
        recentNews(
          repository.items,
          category: NewsCategory.updates,
          now: repository.now(),
        ).length,
        2,
      );
      repository.dispose();
    },
  );
  for (final category in [NewsCategory.events, NewsCategory.updates]) {
    test('Recent $category uses publication dates and includes the cutoff', () {
      OfficialNews post(String id, DateTime? date) => OfficialNews(
        id: id,
        title: 'Event update',
        content: '',
        tag: category == NewsCategory.events ? 'event' : 'notice',
        locale: 'zh-cn',
        publishedAt: date,
        updatedAt: DateTime.utc(2026, 10, 19),
      );
      final now = DateTime.utc(2026, 10, 19, 8);
      final cutoff = DateTime.utc(2026, 8, 19, 8);
      final posts = [
        post('boundary', cutoff),
        post('old', cutoff.subtract(const Duration(microseconds: 1))),
        post('unknown', null),
        post('future', now.add(const Duration(seconds: 1))),
        post('newest', now),
      ];
      expect(
        recentNews(posts, category: category, now: now).map((post) => post.id),
        ['newest', 'boundary'],
      );
      expect(posts.length, 5);
    });
  }
  test('Two-month cutoff clamps month ends across a year boundary', () {
    final posts = parseOfficialNews(
      feed([
        row('before', 'Notice', date: '2026-02-28T07:59:59Z'),
        row('boundary', 'Notice', date: '2026-02-28T08:00:00Z'),
      ]),
    );
    expect(
      recentNews(
        posts,
        category: NewsCategory.updates,
        now: DateTime.utc(2026, 4, 30, 8),
      ).map((post) => post.id),
      ['boundary'],
    );
    final yearBoundary = parseOfficialNews(
      feed([row('boundary', 'Notice', date: '2025-11-19T08:00:00Z')]),
    );
    expect(
      recentNews(
        yearBoundary,
        category: NewsCategory.updates,
        now: DateTime.utc(2026, 1, 19, 8),
      ).length,
      1,
    );
  });
  test(
    'Official feed parses, deduplicates, sorts and encodes source links',
    () {
      final items = parseOfficialNews(
        feed([
          row('1', 'Older', date: '2026-10-15T04:00:00Z'),
          row(
            'x&bad',
            '<b>Newest</b> &amp; verified',
            content: '<p>Event update</p><p>Pick-up information</p>',
          ),
          row('1', 'Older duplicate', date: '2026-10-15T04:00:00Z'),
        ]),
      );
      expect(items.length, 2);
      expect(items.first.title, 'Newest & verified');
      expect(items.first.url.host, 'www.browndust2.com');
      expect(items.first.url.queryParameters['id'], 'x&bad');
      expect(items.first.categories, {
        NewsCategory.updates,
        NewsCategory.banners,
      });
      expect(
        items.first.revision,
        DateTime.utc(2026, 10, 16, 4).millisecondsSinceEpoch.toString(),
      );
    },
  );
  test('No invented news when upstream schema changes or is empty', () {
    for (final value in [
      '{}',
      '{"data":[]}',
      '{"data":[{"attributes":{}}]}',
      '<html>error</html>',
    ]) {
      expect(() => parseOfficialNews(value), throwsFormatException);
    }
  });
  test('Classification handles multilingual posts and embedded banners', () {
    expect(classifyNews('登录活动', 'event', ''), {NewsCategory.events});
    expect(classifyNews('例行维护公告', 'notice', '召唤卡池'), {
      NewsCategory.updates,
      NewsCategory.banners,
    });
    expect(
      classifyNews(
        'Patch notes',
        'notice',
        'Event update\nPick-up information',
      ),
      {NewsCategory.updates, NewsCategory.banners},
    );
    expect(classifyNews('A letter', '', ''), {NewsCategory.updates});
    expect(classifyNews('Notice about maintenance', 'event', 'Event period'), {
      NewsCategory.events,
    });
    for (final tag in ['notice', 'maintenance', 'maintance']) {
      expect(classifyNews('October event update', tag, 'Event period'), {
        NewsCategory.updates,
      });
    }
  });
  test('All recent posts survive parsing even when there are over 100', () {
    final posts = parseOfficialNews(
      feed([
        for (var index = 0; index < 130; index++)
          row('$index', 'October notice $index'),
      ]),
    );
    expect(posts.length, 130);
    expect(
      recentNews(
        posts,
        category: NewsCategory.updates,
        now: DateTime.utc(2026, 10, 19),
      ).length,
      130,
    );
  });
  test(
    'Untrusted HTML is shown as inert text and external images are excluded',
    () {
      final item = parseOfficialNews(
        feed([
          row(
            '1',
            'Post',
            content:
                '<script>bad()</script><p>One</p><p>Two &amp; three</p><img src="https://evil.example/icon.png">',
          ),
        ]),
      ).single;
      expect(item.text, contains('One\n\nTwo & three'));
      expect(item.text, isNot(contains('bad()')));
      expect(item.image, isNull);
    },
  );
  test(
    'Successful sync stores an offline cache and original publication time',
    () async {
      final repository = NewsRepository(
        client: MockClient(
          (request) async => http.Response(
            feed([row('1', 'Official event', tag: 'event')]),
            200,
          ),
        ),
      );
      await repository.initialize();
      expect(repository.error, isNull);
      expect(
        repository.items.single.publishedAt,
        DateTime.utc(2026, 10, 16, 4),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('official_news_cache_v1'), isNotNull);
      repository.dispose();
      final offline = NewsRepository(
        client: MockClient(
          (request) async => http.Response('unavailable', 503),
        ),
      );
      await offline.initialize();
      expect(offline.items.single.title, 'Official event');
      expect(offline.error, contains('上次保存'));
      expect(offline.lastUpdated, isNotNull);
      offline.dispose();
    },
  );
  test('English fallback remains official and is disclosed', () async {
    final requests = <String>[];
    final repository = NewsRepository(
      client: MockClient((request) async {
        requests.add(request.url.queryParameters['locale']!);
        expect(request.url.host, 'webapi.browndust2.com');
        expect(request.url.path, '/api/notices');
        expect(request.headers.containsKey('Cache-Control'), isFalse);
        return request.url.queryParameters['locale'] == 'zh-cn'
            ? http.Response('{}', 200)
            : http.Response(feed([row('2', 'English update')]), 200);
      }),
    );
    await repository.initialize();
    expect(requests, ['zh-cn', 'en-us']);
    expect(repository.usingEnglish, true);
    expect(repository.items.single.url.path, '/en-us/news/view');
    repository.dispose();
  });
  test(
    'Chinese news is preferred and its resource link uses the Chinese index',
    () async {
      final repository = NewsRepository(
        client: MockClient((request) async {
          final chinese = request.url.queryParameters['locale'] == 'zh-cn';
          return http.Response(
            feed([
              row('shared', chinese ? 'Chinese notice' : 'English notice'),
              row(chinese ? 'cn-only' : 'en-only', 'Pickup announcement'),
            ]),
            200,
          );
        }),
      );
      await repository.initialize();
      expect(repository.error, isNull);
      expect(repository.items.length, 2);
      expect(
        repository.items.singleWhere((item) => item.id == 'shared').locale,
        'zh-cn',
      );
      expect(repository.items.any((item) => item.id == 'en-only'), isFalse);
      expect(repository.usingEnglish, isFalse);
      expect(
        NewsRepository.officialChineseIndex.toString(),
        'https://www.browndust2.com/zh-cn/news?page=1&type=all',
      );
      final cache = (await SharedPreferences.getInstance()).getString(
        'official_news_cache_v1',
      );
      expect(cache, contains('cn-only'));
      repository.dispose();
    },
  );
  test(
    'Failed sync exposes an error without caching empty or fictional content',
    () async {
      final repository = NewsRepository(
        client: MockClient(
          (request) async => http.Response('bad gateway', 502),
        ),
      );
      await repository.initialize();
      expect(repository.error, isNotNull);
      expect(repository.items, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'official_news_cache_v1',
        ),
        isNull,
      );
      repository.dispose();
    },
  );
  test(
    'Concurrent refreshes share the current operation instead of racing caches',
    () async {
      var calls = 0;
      final repository = NewsRepository(
        client: MockClient((request) async {
          calls++;
          return http.Response(feed([row('3', 'One fetch')]), 200);
        }),
      );
      await Future.wait([repository.refresh(), repository.refresh()]);
      expect(calls, 1);
      expect(repository.items.single.id, '3');
      repository.dispose();
    },
  );
}
