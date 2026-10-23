import 'dart:convert';
import 'package:bd2/announcements/youtube_banners.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String page(List<(String, String)> videos) =>
    '<script>var ytInitialData = ${jsonEncode({
      'contents': [
        for (final video in videos) {
            'videoRenderer': {
              'videoId': video.$1,
              'title': {
                'runs': [
                  {'text': video.$2},
                ],
              },
            },
          },
      ],
      'sidebar': {
        'videoRenderer': {
          'videoId': 'sidebar1234',
          'title': {'simpleText': 'Costume preview'},
        },
      },
    })};</script>';

String watch(
  String id,
  String published, {
  String channel = 'UCmnj4VhKgycXSq3-GrQhhgQ',
}) =>
    '<meta itemprop="datePublished" content="$published"><script>var ytInitialPlayerResponse = ${jsonEncode({
      'videoDetails': {'videoId': id, 'channelId': channel},
    })};</script>';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('New YouTube lockup layout supplies video titles and IDs', () {
    final cards = parseYoutubeBanners(
      '<script>var ytInitialData = ${jsonEncode({
        'contents': [
          {
            'lockupViewModel': {
              'contentId': 'abcdefghijk',
              'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
              'metadata': {
                'lockupMetadataViewModel': {
                  'title': {'content': 'New Special Skin - Clumsy Wuff Tyr'},
                },
              },
            },
          },
        ],
      })};</script>',
    );
    expect(cards.single.name, 'New Special Skin - Clumsy Wuff Tyr');
    expect(cards.single.source.url.queryParameters['v'], 'abcdefghijk');
  });
  test('Continuation pages are fetched until uploads pass the cutoff', () async {
    var continued = false;
    final repository = YoutubeBannerRepository(
      now: () => DateTime.utc(2027, 1, 19),
      client: MockClient((request) async {
        if (request.url.path == '/watch') {
          final id = request.url.queryParameters['v']!;
          return http.Response(
            watch(
              id,
              id == 'abcdefghijk'
                  ? '2027-01-10T00:00:00Z'
                  : '2026-11-18T00:00:00Z',
            ),
            200,
          );
        }
        final video = {
          'videoRenderer': {
            'videoId': continued ? 'oldvideo123' : 'abcdefghijk',
            'title': {'simpleText': 'Costume PV'},
          },
        };
        final more = {
          'continuationItemRenderer': {
            'continuationEndpoint': {
              'continuationCommand': {'token': 'next-page'},
            },
          },
        };
        if (request.method == 'POST') {
          expect(jsonDecode(request.body)['continuation'], 'next-page');
          continued = true;
          return http.Response(
            jsonEncode({
              'onResponseReceivedActions': [
                {
                  'appendContinuationItemsAction': {
                    'continuationItems': [
                      {
                        'videoRenderer': {
                          'videoId': 'oldvideo123',
                          'title': {'simpleText': 'Old Costume PV'},
                        },
                      },
                      more,
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          '<script>var ytcfg = {"INNERTUBE_CLIENT_VERSION":"2.test"};</script><script>var ytInitialData = ${jsonEncode({
            'contents': [video, more],
          })};</script>',
          200,
        );
      }),
    );
    await repository.initialize();
    expect(repository.error, isNull);
    expect(continued, isTrue);
    expect(
      repository.items.single.source.url.queryParameters['v'],
      'abcdefghijk',
    );
    repository.dispose();
  });
  test('Mobile escaped data and special skin titles are supported', () {
    final json = jsonEncode({
      'contents': [
        {
          'videoWithContextRenderer': {
            'videoId': 'abcdefghijk',
            'headline': {
              'runs': [
                {'text': 'New Special Skin - Clumsy Wuff Tyr'},
              ],
            },
          },
        },
      ],
    });
    final escaped = json.codeUnits
        .map((unit) => '\\u${unit.toRadixString(16).padLeft(4, '0')}')
        .join();
    final cards = parseYoutubeBanners(
      "<script>var ytInitialData = '$escaped';</script>",
    );
    expect(cards.single.name, 'New Special Skin - Clumsy Wuff Tyr');
  });
  test(
    'Exact upload dates enforce the January cutoff and expired cache is deleted offline',
    () async {
      var now = DateTime.utc(2027, 1, 19);
      final dates = {
        'abcdefghijk': '2027-01-18T00:00:00Z',
        'boundary123': '2026-11-19T00:00:00Z',
        'oldvideo123': '2026-11-18T23:59:59Z',
      };
      SharedPreferences.setMockInitialValues({
        'youtube_summon_banners_v1': 'Legacy undated cache',
      });
      final repository = YoutubeBannerRepository(
        now: () => now,
        client: MockClient((request) async {
          if (request.url.path == '/watch') {
            final id = request.url.queryParameters['v']!;
            return http.Response(watch(id, dates[id]!), 200);
          }
          return http.Response(
            page([for (final id in dates.keys) (id, 'Costume PV $id')]),
            200,
          );
        }),
      );
      await repository.initialize();
      expect(repository.error, isNull);
      expect(
        repository.items.map((item) => item.source.url.queryParameters['v']),
        ['abcdefghijk', 'boundary123'],
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('youtube_summon_banners_v1'), isFalse);
      expect(
        prefs.getString('youtube_summon_banners_v2'),
        isNot(contains('oldvideo123')),
      );
      repository.dispose();
      now = DateTime.utc(2027, 1, 20);
      final offline = YoutubeBannerRepository(
        now: () => now,
        client: MockClient((_) async => http.Response('Offline', 503)),
      );
      await offline.initialize();
      expect(
        offline.items.single.source.url.queryParameters['v'],
        'abcdefghijk',
      );
      expect(
        prefs.getString('youtube_summon_banners_v2'),
        isNot(contains('boundary123')),
      );
      offline.dispose();
    },
  );
  test(
    'Publication metadata must match both the video and official channel',
    () {
      expect(
        () => parseYoutubePublication(
          watch(
            'abcdefghijk',
            '2026-10-09T00:00:00Z',
            channel: 'another-channel',
          ),
          'abcdefghijk',
        ),
        throwsFormatException,
      );
      expect(
        () => parseYoutubePublication(
          watch('abcdefghijk', '2026-10-09T00:00:00Z'),
          'another1234',
        ),
        throwsFormatException,
      );
    },
  );
  test('Only summon-related uploads become undated cards with video links', () {
    final banners = parseYoutubeBanners(
      page([
        ('abcdefghijk', 'Moonlight Alice Costume PV'),
        ('abcdefghijk', 'Moonlight Alice Costume PV'),
        ('123456789ab', 'Anniversary livestream'),
        ('bad-id', 'Costume preview'),
      ]),
    );
    expect(banners.length, 1);
    expect(banners.single.endsAt, isNull);
    expect(banners.single.id, 'banner:youtube:abcdefghijk');
    expect(
      parseYoutubeBanners(
        page([('abcdefghijk', 'Updated Alice Costume PV')]),
      ).single.id,
      banners.single.id,
    );
    expect(
      banners.single.source.url.toString(),
      'https://www.youtube.com/watch?v=abcdefghijk',
    );
    expect(banners.single.picture.host, 'i.ytimg.com');
  });
  test(
    'Consent or changed pages are errors instead of empty successful feeds',
    () {
      expect(
        () => parseYoutubeBanners('<html>Consent required</html>'),
        throwsFormatException,
      );
    },
  );
  test('Videos persist after refresh and remain available offline', () async {
    var calls = 0;
    final repository = YoutubeBannerRepository(
      client: MockClient((request) async {
        if (request.url.path == '/watch') {
          return http.Response(
            watch(request.url.queryParameters['v']!, '2026-10-09T03:00:00Z'),
            200,
          );
        }
        expect(request.url.path, '/@browndust2_en/videos');
        calls++;
        return http.Response(
          page(calls == 1 ? [('abcdefghijk', 'Alice Costume PV')] : []),
          200,
        );
      }),
    );
    await repository.initialize();
    expect(repository.items.length, 1);
    await repository.refresh();
    expect(repository.items.length, 1);
    repository.dispose();
    final offline = YoutubeBannerRepository(
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );
    await offline.initialize();
    expect(offline.items.single.name, 'Alice Costume PV');
    expect(offline.error, isNotNull);
    offline.dispose();
  });
}
