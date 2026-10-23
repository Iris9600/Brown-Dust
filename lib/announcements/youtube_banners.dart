import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'official_news.dart';
import 'summon_banner.dart';

final officialYoutubeChannel = Uri.parse(
  'https://www.youtube.com/@browndust2_en',
);
const _channelId = 'UCmnj4VhKgycXSq3-GrQhhgQ';

class _VideoNews extends OfficialNews {
  _VideoNews(this.videoId, String title, {super.publishedAt})
    : super(
        id: 'youtube:$videoId',
        title: title,
        content: '',
        tag: 'video',
        locale: 'en-us',
      );
  final String videoId;
  @override
  Uri get url => Uri.https('www.youtube.com', '/watch', {'v': videoId});
}

Map<String, dynamic> _youtubeData(String page, String variable) {
  final document = html.parse(page);
  for (final script in document.querySelectorAll('script')) {
    final match = RegExp('$variable\\s*=\\s*').firstMatch(script.text);
    if (match == null) continue;
    var value = script.text.substring(match.end).trim();
    if (!value.startsWith("'") && !value.startsWith('{')) continue;
    if (value.startsWith("'")) {
      final end = RegExp(
        r"^'((?:\\.|[^'\\])*)'",
        dotAll: true,
      ).firstMatch(value);
      if (end == null) {
        throw const FormatException('Invalid YouTube data string');
      }
      final escaped = end[1]!
          .replaceAllMapped(
            RegExp(r'\\x([0-9a-fA-F]{2})'),
            (m) => '\\u00${m[1]}',
          )
          .replaceAll(r"\'", "'");
      value = jsonDecode('"$escaped"') as String;
    } else {
      value = value.substring(0, value.lastIndexOf('}') + 1);
    }
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
  }
  throw const FormatException('YouTube data unavailable');
}

List<SummonBanner> parseYoutubeBanners(String page) {
  return _videoCandidates(_youtubeData(page, 'ytInitialData'));
}

dynamic _listingContents(Map<String, dynamic> data) =>
    data['contents'] ??
    data['onResponseReceivedActions'] ??
    data['onResponseReceivedEndpoints'];

String? _continuation(Map<String, dynamic> data) {
  String? token;
  void visit(dynamic node) {
    if (node is List) {
      for (final child in node) {
        visit(child);
      }
    }
    if (node is Map) {
      final command =
          node['continuationCommand'] ?? node['nextContinuationData'];
      if (command is Map) {
        token = (command['token'] ?? command['continuation']) as String?;
      }
      for (final child in node.values) {
        visit(child);
      }
    }
  }

  visit(_listingContents(data));
  return token;
}

List<SummonBanner> _videoCandidates(Map<String, dynamic> data) {
  final videos = <String, SummonBanner>{};
  void visit(dynamic node) {
    if (node is List) {
      for (final child in node) {
        visit(child);
      }
    } else if (node is Map) {
      final video =
          node['videoRenderer'] ??
          node['gridVideoRenderer'] ??
          node['videoWithContextRenderer'] ??
          node['lockupViewModel'];
      if (video is Map) {
        final id = (video['videoId'] ?? video['contentId'])?.toString() ?? '';
        final titleData =
            video['title'] ??
            video['headline'] ??
            video['metadata']?['lockupMetadataViewModel']?['title'];
        final title = titleData is Map
            ? (titleData['simpleText'] ??
                      titleData['content'] ??
                      (titleData['runs'] is List
                          ? (titleData['runs'] as List)
                                .whereType<Map>()
                                .map((run) => run['text'] ?? '')
                                .join()
                          : ''))
                  .toString()
                  .trim()
            : '';
        if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) &&
            RegExp(
              r'costume|\bskin\b|\bPV\b|pick[ -]?up|summon|character\s*(?:preview|trailer|introduction)',
              caseSensitive: false,
            ).hasMatch(title)) {
          videos[id] = SummonBanner(
            stableId: 'banner:youtube:$id',
            name: title,
            picture: Uri.https('i.ytimg.com', '/vi/$id/hqdefault.jpg'),
            period: '官方角色影片，召唤期间尚未确认。',
            source: _VideoNews(id, title),
            type: '官方角色影片',
            periodKind: BannerPeriodKind.artwork,
          );
        }
      }
      for (final child in node.values) {
        visit(child);
      }
    }
  }

  // Only use the channel's own uploads, not recommendations or sidebar videos.
  visit(_listingContents(data));
  return videos.values.toList();
}

DateTime parseYoutubePublication(String page, String videoId) {
  final player = _youtubeData(page, 'ytInitialPlayerResponse');
  final details = player['videoDetails'];
  if (details is! Map ||
      details['videoId'] != videoId ||
      details['channelId'] != _channelId) {
    throw const FormatException('Unexpected YouTube video or channel');
  }
  final document = html.parse(page);
  final date = document
      .querySelector('meta[itemprop="datePublished"]')
      ?.attributes['content'];
  final published = DateTime.tryParse(date ?? '');
  if (published == null) {
    throw const FormatException('Video publication date unavailable');
  }
  return published.toUtc();
}

SummonBanner _videoCard(String id, String title, DateTime published) =>
    SummonBanner(
      stableId: 'banner:youtube:$id',
      name: title,
      picture: Uri.https('i.ytimg.com', '/vi/$id/hqdefault.jpg'),
      period: '官方角色影片，召唤期间尚未确认。',
      source: _VideoNews(id, title, publishedAt: published),
      type: '官方角色影片',
      periodKind: BannerPeriodKind.artwork,
    );

class YoutubeBannerRepository extends ChangeNotifier {
  YoutubeBannerRepository({http.Client? client, this.now = DateTime.now})
    : _client = client ?? http.Client();
  final http.Client _client;
  final DateTime Function() now;
  List<SummonBanner> items = [];
  String? error;
  bool loading = false, _disposed = false;
  static const _cacheKey = 'youtube_summon_banners_v2';
  Timer? _retentionTimer;
  bool _cacheDirty = false;

  bool _recent(SummonBanner item) {
    final published = item.source.publishedAt;
    return published != null &&
        !published.isBefore(newsRetentionCutoff(now())) &&
        !published.isAfter(now().toUtc());
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _cacheKey,
      jsonEncode(
        items
            .map(
              (item) => {
                'videoId': (item.source as _VideoNews).videoId,
                'title': item.name,
                'publishedAt': item.source.publishedAt!.toIso8601String(),
              },
            )
            .toList(),
      ),
    )) {
      throw StateError('Unable to save video cache');
    }
    _cacheDirty = false;
  }

  Future<void> pruneExpired() async {
    if (_disposed) return;
    final retained = items.where(_recent).toList();
    if (retained.length == items.length && !_cacheDirty) return;
    items = retained;
    _cacheDirty = true;
    try {
      await _save();
    } catch (_) {
      error = '无法保存过期影片清理结果，将重试。';
    }
    if (!_disposed) notifyListeners();
  }

  Future<String> _get(Uri url) async {
    final response = await _client
        .get(url)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 12 * 1024 * 1024) {
      throw const FormatException('Invalid YouTube response');
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        items = (jsonDecode(cached) as List)
            .map(
              (value) => _videoCard(
                value['videoId'] as String,
                value['title'] as String,
                DateTime.parse(value['publishedAt'] as String),
              ),
            )
            .toList();
      }
      // The previous cache had no upload dates, so it cannot meet age retention.
      if (!await prefs.remove('youtube_summon_banners_v1')) {
        throw StateError('Unable to remove legacy video cache');
      }
      await pruneExpired();
    } catch (_) {
      error = '角色影片缓存无法读取，将重新获取。';
    }
    if (_disposed) return;
    _retentionTimer?.cancel();
    _retentionTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(pruneExpired()),
    );
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed || loading) return;
    loading = true;
    notifyListeners();
    try {
      await pruneExpired();
      final page = await _get(
        Uri.parse('$officialYoutubeChannel/videos?hl=en'),
      );
      var listing = _youtubeData(page, 'ytInitialData');
      final clientVersion = RegExp(
        r'"INNERTUBE_CLIENT_VERSION"\s*:\s*"([^"]+)"',
      ).firstMatch(page)?[1];
      final received = <SummonBanner>[];
      var failures = 0;
      final visited = <String>{};
      for (var pageIndex = 0; pageIndex < 100; pageIndex++) {
        var reachedCutoff = false;
        final candidates = _videoCandidates(
          listing,
        ).where((item) => visited.add(item.id)).toList();
        for (var i = 0; i < candidates.length; i += 4) {
          await Future.wait(
            candidates.skip(i).take(4).map((candidate) async {
              try {
                final id = (candidate.source as _VideoNews).videoId;
                final existing = items
                    .where((item) => item.id == candidate.id)
                    .firstOrNull;
                final published =
                    existing?.source.publishedAt ??
                    parseYoutubePublication(
                      await _get(
                        Uri.https('www.youtube.com', '/watch', {
                          'v': id,
                          'hl': 'en',
                        }),
                      ),
                      id,
                    );
                final card = _videoCard(id, candidate.name, published);
                if (published.isBefore(newsRetentionCutoff(now()))) {
                  reachedCutoff = true;
                }
                if (_recent(card)) received.add(card);
              } catch (_) {
                failures++;
              }
            }),
          );
          if (_disposed) return;
        }
        final continuation = _continuation(listing);
        if (reachedCutoff || continuation == null) break;
        if (clientVersion == null || pageIndex == 99) {
          throw const FormatException('YouTube pagination unavailable');
        }
        final response = await _client
            .post(
              Uri.https('www.youtube.com', '/youtubei/v1/browse'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'context': {
                  'client': {
                    'clientName': page.contains('videoWithContextRenderer')
                        ? 'MWEB'
                        : 'WEB',
                    'clientVersion': clientVersion,
                    'hl': 'en',
                  },
                },
                'continuation': continuation,
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 ||
            response.bodyBytes.length > 12 * 1024 * 1024) {
          throw const FormatException('Invalid YouTube continuation');
        }
        listing =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
      if (_disposed) return;
      final merged = {
        for (final item in [...items, ...received]) item.id: item,
      };
      items = merged.values.where(_recent).toList()
        ..sort(
          (a, b) => b.source.publishedAt!.compareTo(a.source.publishedAt!),
        );
      error = failures == 0 ? null : '部分影片的发布日期暂时无法确认，请刷新重试。';
      await _save();
    } catch (_) {
      if (!_disposed) error = '暂时无法同步 YouTube 角色影片，可打开官方频道查看。';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retentionTimer?.cancel();
    _client.close();
    super.dispose();
  }
}
