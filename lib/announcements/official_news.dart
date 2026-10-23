import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'summon_banner.dart';

enum NewsCategory { events, updates, banners }

class OfficialNews {
  OfficialNews({
    required this.id,
    required this.title,
    required this.content,
    required this.tag,
    required this.locale,
    this.publishedAt,
    this.updatedAt,
    this.isPreview = false,
  });
  final String id, title, content, tag, locale;
  final DateTime? publishedAt, updatedAt;
  final bool isPreview;
  Uri get url =>
      Uri.https('www.browndust2.com', '/$locale/news/view', {'id': id});
  String get revision =>
      (updatedAt ?? publishedAt)?.millisecondsSinceEpoch.toString() ?? title;
  late final String text = _plainText();
  String _plainText() {
    final document = html.parse(
      content.replaceAll(
        RegExp(r'</?(?:p|div|br|li|h[1-6]|tr)\b[^>]*>', caseSensitive: false),
        '\n',
      ),
    );
    document
        .querySelectorAll('script,style')
        .forEach((element) => element.remove());
    return (document.body?.text ?? '')
        .replaceAll(RegExp(r'\n[ \t]*\n[ \t]*\n+'), '\n\n')
        .trim();
  }

  late final Set<NewsCategory> categories = classifyNews(title, tag, text);
  late final Uri? image = _image();
  Uri? _image() {
    final document = html.parse(content);
    final src =
        document.querySelector('img')?.attributes['src'] ??
        RegExp(
          r'!\[[^\]]*\]\((https://[^\s)]+)\)',
        ).firstMatch(content)?.group(1);
    final uri = src == null ? null : Uri.tryParse(src);
    return uri != null &&
            uri.scheme == 'https' &&
            (uri.host == 'www.browndust2.com' ||
                uri.host.endsWith('.browndust2.com'))
        ? uri
        : null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'tag': tag,
    'locale': locale,
    'publishedAt': publishedAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'isPreview': isPreview,
  };
  Map<String, dynamic> notificationData() => {
    'id': id,
    'title': title,
    'url': url.toString(),
    'revision': revision,
    'locale': locale,
    'categories': categories.map((e) => e.name).toList(),
  };
  static OfficialNews fromCache(Map<String, dynamic> value) => OfficialNews(
    id: value['id'] as String,
    title: value['title'] as String,
    content: value['content'] as String,
    tag: value['tag'] as String,
    locale: value['locale'] as String,
    publishedAt: DateTime.tryParse(value['publishedAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(value['updatedAt'] as String? ?? ''),
    isPreview: value['isPreview'] == true,
  );
}

Set<NewsCategory> classifyNews(String title, String tag, String body) {
  final heading = '$title $tag'.toLowerCase();
  final all = '$heading $body'.toLowerCase();
  final categories = <NewsCategory>{};
  final officialType = officialNewsTag(tag);
  final typedEvent = const {'event', '活动', '活動'}.contains(officialType);
  final typedUpdate = const {
    'notice',
    'maintenance',
    'maintance',
    'update',
    'dev_note',
    'package_deal',
    'issue',
    'goods',
    '公告',
    '维护',
    '維護',
  }.contains(officialType);
  if (typedEvent) categories.add(NewsCategory.events);
  if (typedUpdate) categories.add(NewsCategory.updates);
  final hasOfficialType = typedEvent || typedUpdate;
  if (!hasOfficialType && RegExp(r'event|活动|活動').hasMatch(heading)) {
    categories.add(NewsCategory.events);
  }
  if (RegExp(r'pick[ -]?up|summon|recruit|抽卡|卡池|招募|召唤|召喚').hasMatch(all)) {
    categories.add(NewsCategory.banners);
  }
  if (!hasOfficialType &&
      (RegExp(
            r'update|maintenance|patch|notice|dev.?note|更新|维护|維護|公告|开发|開發',
          ).hasMatch(heading) ||
          categories.isEmpty)) {
    categories.add(NewsCategory.updates);
  }
  // Official patch notes often contain the event and pickup schedules together.
  if (!hasOfficialType &&
      RegExp(r'event update|event period|活动时间|活動期間|活动更新|活動更新').hasMatch(all)) {
    categories.add(NewsCategory.events);
  }
  return categories;
}

String officialNewsTag(String category) =>
    switch (category.trim().toLowerCase()) {
      'inspection' => 'maintenance',
      'update' => 'dev_note',
      'shop' => 'package_deal',
      final value => value,
    };

List<OfficialNews> parseOfficialNews(String source, {String locale = 'zh-cn'}) {
  final decoded = jsonDecode(source);
  final rows = decoded is Map ? (decoded['items'] ?? decoded['data']) : null;
  if (rows is! List) {
    throw const FormatException('Official news data is missing');
  }
  final unique = <String, OfficialNews>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final fields = row['attributes'] is Map ? row['attributes'] as Map : row;
    final id = row['id']?.toString() ?? '';
    final title =
        (fields['subject'] ?? fields['title'])?.toString().trim() ?? '';
    if (id.isEmpty || title.isEmpty) continue;
    unique[id] = OfficialNews(
      id: id,
      title: html.parseFragment(title).text ?? title,
      content:
          [
                fields['contentHtml'],
                fields['NewContent'],
                fields['content'],
                fields['contentPreview'],
              ]
              .whereType<String>()
              .where((value) => value.isNotEmpty)
              .firstOrNull ??
          '',
      tag: officialNewsTag(
        (fields['category'] ?? fields['tag'] ?? '').toString(),
      ),
      locale: locale,
      publishedAt: DateTime.tryParse(fields['publishedAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(fields['updatedAt']?.toString() ?? ''),
      isPreview:
          fields.containsKey('contentPreview') &&
          !fields.containsKey('content'),
    );
  }
  if (unique.isEmpty) {
    throw const FormatException('Official news feed is empty or changed');
  }
  final items = unique.values.toList()
    ..sort(
      (a, b) => (b.publishedAt ?? DateTime.utc(1970)).compareTo(
        a.publishedAt ?? DateTime.utc(1970),
      ),
    );
  return items;
}

DateTime newsRetentionCutoff(DateTime now) {
  final current = now.toUtc();
  final month = DateTime.utc(current.year, current.month - 2);
  final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
  return DateTime.utc(
    month.year,
    month.month,
    current.day > lastDay ? lastDay : current.day,
    current.hour,
    current.minute,
    current.second,
    current.millisecond,
    current.microsecond,
  );
}

List<OfficialNews> recentNews(
  Iterable<OfficialNews> posts, {
  required NewsCategory category,
  required DateTime now,
}) {
  final current = now.toUtc();
  final cutoff = newsRetentionCutoff(current);
  return posts.where((post) {
    final published = post.publishedAt;
    return post.categories.contains(category) &&
        published != null &&
        !published.isBefore(cutoff) &&
        !published.isAfter(current);
  }).toList()..sort((a, b) => b.publishedAt!.compareTo(a.publishedAt!));
}

class NewsRepository extends ChangeNotifier {
  NewsRepository({http.Client? client, this.now = DateTime.now})
    : _client = client ?? http.Client();
  final http.Client _client;
  final DateTime Function() now;
  List<OfficialNews> items = [];
  List<SummonBanner> banners = [];
  Timer? _retentionTimer;
  bool _cacheDirty = false;
  DateTime? lastUpdated;
  String? error;
  bool loading = false;
  bool _disposed = false;
  bool _refreshing = false;
  static final officialChineseIndex = Uri.parse(
    'https://www.browndust2.com/zh-cn/news?page=1&type=all',
  );
  bool get usingEnglish => items.isNotEmpty && items.first.locale == 'en-us';

  Future<void> _saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      'official_news_cache_v1',
      jsonEncode({
        'savedAt': lastUpdated?.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'banners': banners.map((banner) => banner.toCache()).toList(),
      }),
    )) {
      throw StateError('Unable to save official news cache');
    }
    _cacheDirty = false;
  }

  void _rememberBanners() {
    banners = {
      for (final banner in [...banners, ...extractSummonBanners(items)])
        '${banner.name.toLowerCase().replaceAll(RegExp(r'\s'), '')}|${banner.period.toLowerCase().replaceAll(RegExp(r'\s'), '')}':
            banner,
    }.values.map((banner) => SummonBanner.fromCache(banner.toCache())).toList();
  }

  Future<void> pruneExpired() async {
    if (_disposed) return;
    final cutoff = newsRetentionCutoff(now());
    final retained = items
        .where(
          (item) =>
              item.publishedAt == null || !item.publishedAt!.isBefore(cutoff),
        )
        .toList();
    final retainedBanners = banners
        .where((banner) => !banner.ended(now()))
        .toList();
    if (retained.length == items.length &&
        retainedBanners.length == banners.length &&
        !_cacheDirty) {
      return;
    }
    items = retained;
    banners = retainedBanners;
    _cacheDirty = true;
    try {
      await _saveCache();
    } catch (_) {
      error = '无法保存过期公告清理结果，将在下次刷新时重试。';
    }
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final response = await _client
        .get(Uri.https('webapi.browndust2.com', path, query))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 12 * 1024 * 1024) {
      throw FormatException('Official API HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid official API response');
    }
    return decoded;
  }

  Future<List<OfficialNews>> _fetch(String locale) async {
    final posts = <String, OfficialNews>{};
    for (var page = 0; page < 100; page++) {
      final data = await _get('/api/notices', {
        'locale': locale,
        'page': '$page',
        'limit': '50',
      });
      final rows = data['items'] ?? data['data'];
      if (rows is! List) {
        throw const FormatException('Official news items missing');
      }
      if (rows.isEmpty) {
        if (page == 0) throw const FormatException('Official news feed empty');
        break;
      }
      final batch = parseOfficialNews(jsonEncode(data), locale: locale);
      for (final post in batch) {
        posts[post.id] = post;
      }
      final pages = data['totalPages'] as int? ?? 1;
      if (page + 1 >= pages ||
          batch.any(
            (post) =>
                post.publishedAt != null &&
                post.publishedAt!.isBefore(newsRetentionCutoff(now())),
          )) {
        break;
      }
      if (page == 99) {
        throw const FormatException('Official pagination limit reached');
      }
    }
    return posts.values.toList();
  }

  Future<OfficialNews> loadDetail(OfficialNews item) async {
    if (!item.isPreview) return item;
    final data = await _get('/api/notices/${Uri.encodeComponent(item.id)}', {
      'locale': item.locale,
    });
    final detail = parseOfficialNews(
      jsonEncode({
        'items': [data],
      }),
      locale: item.locale,
    ).single;
    if (detail.id != item.id) {
      throw const FormatException('Wrong official news detail');
    }
    return detail;
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('official_news_cache_v1');
      if (raw != null) {
        final cache = jsonDecode(raw) as Map<String, dynamic>;
        items = (cache['items'] as List)
            .map(
              (e) =>
                  OfficialNews.fromCache(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        lastUpdated = DateTime.tryParse(cache['savedAt'] as String? ?? '');
        banners = (cache['banners'] as List? ?? [])
            .map(
              (value) => SummonBanner.fromCache(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList();
        _rememberBanners();
        await pruneExpired();
      }
    } catch (_) {
      error = '本地公告缓存无法读取，将尝试从官网重新获取。';
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
    if (_refreshing || _disposed) return;
    _refreshing = true;
    await pruneExpired();
    if (_disposed) return;
    loading = true;
    notifyListeners();
    try {
      List<OfficialNews>? received;
      for (final locale in ['zh-cn', 'en-us']) {
        try {
          received = await _fetch(locale);
          break;
        } catch (_) {
          // A language may be unavailable; try the official English feed next.
        }
      }
      if (_disposed) return;
      if (received == null) {
        throw const FormatException('Official feed unavailable');
      }
      items = received;
      lastUpdated = now().toUtc();
      error = null;
      notifyListeners();
      // Pickup artwork lives in full notices, not the API's list previews.
      final candidates = items
          .where(
            (item) =>
                item.isPreview &&
                (item.tag == 'maintenance' ||
                    RegExp(
                      r'pick[ -]?up|召唤|召喚|抽抽|招募|更新',
                      caseSensitive: false,
                    ).hasMatch(item.title)),
          )
          .toList();
      final details = <String, OfficialNews>{};
      var detailFailures = 0;
      for (var i = 0; i < candidates.length; i += 4) {
        await Future.wait(
          candidates.skip(i).take(4).map((item) async {
            try {
              details[item.id] = await loadDetail(item);
            } catch (_) {
              detailFailures++;
            }
          }),
        );
        if (_disposed) return;
      }
      if (details.isNotEmpty) {
        items = items.map((item) => details[item.id] ?? item).toList();
      }
      _rememberBanners();
      await pruneExpired();
      if (detailFailures > 0) error = '公告列表已更新，部分卡池正文暂时无法加载。';
      await _saveCache();
    } catch (_) {
      error = items.isEmpty ? '暂时无法读取官方公告。请重试或打开官网。' : '刷新失败，正在显示上次保存的公告。';
    } finally {
      _refreshing = false;
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
