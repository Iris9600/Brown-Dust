import 'package:html/parser.dart' as html;
import 'official_news.dart';

enum BannerPeriodKind { range, deadline, artwork }

class SummonBanner {
  SummonBanner({
    required this.name,
    required this.picture,
    required this.period,
    required this.source,
    required this.type,
    this.startsAt,
    this.endsAt,
    this.rate,
    this.gear,
    this.periodKind = BannerPeriodKind.range,
    this.stableId,
  });
  final String name, period, type;
  final BannerPeriodKind periodKind;
  final Uri picture;
  final OfficialNews source;
  final DateTime? startsAt, endsAt;
  final String? rate, gear;
  final String? stableId;
  String get id =>
      stableId ?? 'banner:${source.id}:${Uri.encodeComponent(name)}';
  Map<String, dynamic> toCache() => {
    'name': name,
    'picture': picture.toString(),
    'period': period,
    'source': {...source.toJson(), 'content': ''},
    'type': type,
    'startsAt': startsAt?.toIso8601String(),
    'endsAt': endsAt?.toIso8601String(),
    'rate': rate,
    'gear': gear,
    'periodKind': periodKind.name,
    'stableId': stableId,
  };
  static SummonBanner fromCache(Map<String, dynamic> value) => SummonBanner(
    name: value['name'] as String,
    picture: Uri.parse(value['picture'] as String),
    period: value['period'] as String,
    source: OfficialNews.fromCache(
      Map<String, dynamic>.from(value['source'] as Map),
    ),
    type: value['type'] as String,
    startsAt: DateTime.tryParse(value['startsAt'] as String? ?? ''),
    endsAt: DateTime.tryParse(value['endsAt'] as String? ?? ''),
    rate: value['rate'] as String?,
    gear: value['gear'] as String?,
    periodKind: BannerPeriodKind.values.byName(value['periodKind'] as String),
    stableId: value['stableId'] as String?,
  );
  bool ended(DateTime now) => endsAt != null && !now.toUtc().isBefore(endsAt!);
  String status(DateTime now) => ended(now)
      ? '已结束'
      : periodKind == BannerPeriodKind.artwork
      ? '排期待核实'
      : startsAt != null && now.toUtc().isBefore(startsAt!)
      ? '即将开启'
      : startsAt != null && endsAt != null
      ? '进行中'
      : '官方召唤';
}

class _Picture {
  const _Picture(this.uri, this.alt);
  final Uri uri;
  final String alt;
}

final _pickup = RegExp(
  r'pick[ -]?up|summon|抽卡|抽抽乐|抽抽樂|卡池|招募|召唤|召喚',
  caseSensitive: false,
);
final _section = RegExp(
  r'^(?:[■◆●#*\s]+)?(?:pick[ -]?up\s*(?:information|info|update)|(?:召唤|召喚|抽卡|抽抽乐|抽抽樂|卡池|招募)(?:相关|相關)?(?:信息|资讯|資訊|情报|情報))\s*[:：]?\s*$',
  caseSensitive: false,
);
final _major = RegExp(r'^\s*(?:[■◆●]|#{1,3}\s)');
final _period = RegExp(
  r'(?:pick[ -]?up\s*)?(?:period|duration|schedule)\s*[:：]|(?:抽卡|卡池|招募|召唤|召喚)?(?:期间|期間|时间|時間)\s*[:：]',
  caseSensitive: false,
);

String _clean(String value) => value
    .replaceAll(RegExp(r'^[\s#*■◆●\-–📢📣⭐✨]+'), '')
    .replaceAll(RegExp(r'^\d+\s*[.)、）]\s*'), '')
    .replaceAll(RegExp(r'\*\*|__'), '')
    .trim();
String? _unitName(String value) {
  var line = _clean(value);
  if (line.contains('@@IMAGE') || _period.hasMatch(line) || line.length > 300) {
    return null;
  }
  if (RegExp(
        r'exclusive gear|专用装备|專用裝備|专属装备|專屬裝備',
        caseSensitive: false,
      ).hasMatch(line) &&
      !RegExp(r'costume|服装|服裝', caseSensitive: false).hasMatch(line)) {
    return null;
  }
  final matches = [
    RegExp(
      r'^(?:【|\[)?(?:全新|新|复刻|復刻|限定)?\s*(?:Pick[ -]?up|抽抽乐|抽抽樂|召唤|召喚|卡池|招募)(?:】|\])?\s*[:：–—-]\s*(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(.+?)(?:服装|服裝)?(?:卡池|招募|召唤|召喚)(?:登场|登場|开启|開啟|开放|開放)?[!！]?$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:new\s+)?(?:limited\s+)?(?:re-?run\s+)?(?:pick[ -]?up|summon)(?:\s+banner)?\s*[:：–—-]\s*(.+)$',
      caseSensitive: false,
    ),
    RegExp(r'^(.+?)\s+costume\b', caseSensitive: false),
    RegExp(
      r'^(.+?)\s+(?:pick[ -]?up|summon)(?:\s+banner)?\b',
      caseSensitive: false,
    ),
    RegExp(r'^(?:角色|服装|服裝)\s*[:：]\s*(.+)$'),
    RegExp(r'^(.+?)(?:服装|服裝)(?:与|與|及|和|的|、|抽|召|招|登|[ :：]|$)'),
    RegExp(r'^(?:新|限定|复刻|復刻)?(?:卡池|召唤|召喚|招募)\s*[:：–—-]\s*(.+)$'),
  ];
  String? name;
  for (final pattern in matches) {
    final match = pattern.firstMatch(line);
    if (match != null) {
      name = match.group(1);
      break;
    }
  }
  if (name == null) return null;
  name = name
      .replaceAll(
        RegExp(
          r'^(?:new|limited|re-?run|★\s*5|5[- ]star)\s+',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'\s*\((?:limited|re-?run)\)\s*', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'[“”"「」『』]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (name.length < 2 ||
      name.length > 90 ||
      RegExp(
        r'^(?:information|info|event|period|costume|exclusive gear|banner|rate|details|limited|new|rerun|this|the|all|服装|服裝|信息|資訊|活动|活動|概率|機率)$',
        caseSensitive: false,
      ).hasMatch(name) ||
      RegExp(
        r'\b(?:will|available|released|schedule)\b',
        caseSensitive: false,
      ).hasMatch(name)) {
    return null;
  }
  return name;
}

Uri? _safePicture(String value) {
  if (value.trim().isEmpty) return null;
  final uri = Uri.https('www.browndust2.com', '/').resolve(value.trim());
  return uri.scheme == 'https' &&
          (uri.host == 'www.browndust2.com' ||
              uri.host.endsWith('.browndust2.com'))
      ? uri
      : null;
}

/// Only extracts named costume banners inside explicit pickup sections (or
/// standalone named pickup posts). Images and periods never cross unit blocks.
List<SummonBanner> extractSummonBanners(Iterable<OfficialNews> posts) {
  final unique = <String, SummonBanner>{};
  final ordered = posts.toList()
    ..sort(
      (a, b) => (b.updatedAt ?? b.publishedAt ?? DateTime.utc(1970)).compareTo(
        a.updatedAt ?? a.publishedAt ?? DateTime.utc(1970),
      ),
    );
  for (final post in ordered) {
    final pictures = <_Picture>[];
    String imageToken(String src, String alt) {
      final uri = _safePicture(src);
      if (uri == null) return '\n';
      pictures.add(_Picture(uri, alt));
      return '\n@@IMAGE:${pictures.length - 1}@@\n';
    }

    var content = post.content.replaceAllMapped(
      RegExp(r'<img\b[^>]*>', caseSensitive: false),
      (match) {
        final element = html
            .parseFragment(match.group(0)!)
            .querySelector('img');
        return imageToken(
          element?.attributes['src'] ?? element?.attributes['data-src'] ?? '',
          element?.attributes['alt'] ?? '',
        );
      },
    );
    content = content.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\(([^\s)]+)\)'),
      (match) => imageToken(match.group(2)!, match.group(1)!),
    );
    content = content.replaceAll(
      RegExp(
        r'</?(?:p|div|br|li|h[1-6]|tr|section)\b[^>]*>',
        caseSensitive: false,
      ),
      '\n',
    );
    final document = html.parse(content);
    document
        .querySelectorAll('script,style')
        .forEach((element) => element.remove());
    final lines = (document.body?.text ?? '')
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final sections = <(int, int)>[];
    for (var i = 0; i < lines.length; i++) {
      if (!_section.hasMatch(lines[i].replaceAll('**', ''))) continue;
      var end = i + 1;
      while (end < lines.length &&
          !(_major.hasMatch(lines[end]) &&
              !_pickup.hasMatch(lines[end]) &&
              _unitName(lines[end]) == null)) {
        end++;
      }
      sections.add((i + 1, end));
      i = end - 1;
    }
    final titleName = _pickup.hasMatch(post.title)
        ? _unitName(post.title)
        : null;
    if (sections.isEmpty && titleName != null) sections.add((0, lines.length));
    for (final section in sections) {
      final candidates = <(int, String)>[];
      for (var i = section.$1; i < section.$2; i++) {
        final line = lines[i];
        if (!RegExp(
              r'^[\s#*■◆●\-–]*\d+[.)、）]|^[\s#*■◆●\-–📢📣⭐✨]+|^(?:角色|服装|服裝)[:：]',
            ).hasMatch(line) &&
            !_pickup.hasMatch(line)) {
          continue;
        }
        final name = _unitName(line);
        if (name != null &&
            (candidates.isEmpty ||
                candidates.last.$2.toLowerCase() != name.toLowerCase())) {
          candidates.add((i, name));
        }
      }
      if (candidates.isEmpty && titleName != null) {
        candidates.add((section.$1, titleName));
      }
      for (var index = 0; index < candidates.length; index++) {
        final candidate = candidates[index];
        final end = index + 1 < candidates.length
            ? candidates[index + 1].$1
            : section.$2;
        final block = lines.sublist(candidate.$1, end);
        final imageIndices = block
            .expand((line) => RegExp(r'@@IMAGE:(\d+)@@').allMatches(line))
            .map((m) => int.parse(m.group(1)!))
            .toList();
        if (imageIndices.isEmpty) continue;
        final image = imageIndices
            .map((i) => pictures[i])
            .firstWhere(
              (pic) =>
                  pic.alt.toLowerCase().contains(candidate.$2.toLowerCase()),
              orElse: () => pictures[imageIndices.first],
            );
        final periodIndex = block.indexWhere((line) => _period.hasMatch(line));
        var period = '';
        var periodKind = BannerPeriodKind.range;
        if (periodIndex >= 0) {
          period = _clean(block[periodIndex]).replaceFirst(_period, '').trim();
          for (
            var i = periodIndex + 1;
            i < block.length && i <= periodIndex + 2;
            i++
          ) {
            if (block[i].contains('@@IMAGE') ||
                _period.hasMatch(block[i]) ||
                RegExp(
                  r'^(?:[-*]\s*)?(?:rate|exclusive|costume|概率|機率|专|專)',
                  caseSensitive: false,
                ).hasMatch(block[i])) {
              break;
            }
            if (!RegExp(
              r'\d|maintenance|维护|維護|UTC|MYT',
              caseSensitive: false,
            ).hasMatch(block[i])) {
              break;
            }
            period = '$period ${_clean(block[i])}'.trim();
          }
          if (period.isEmpty ||
              !RegExp(r'\d').hasMatch(period) ||
              !RegExp(
                r'~|～|–|—|\s-\s|\bto\b|\buntil\b|至|到',
                caseSensitive: false,
              ).hasMatch(period)) {
            continue;
          }
        } else {
          // Official standalone pickup promotions often publish only a closing
          // date, or put the schedule in the poster rather than a text field.
          final deadline = block
              .where(
                (line) =>
                    RegExp(
                      r'pick[ -]?up\s+(?:rate\s*)?(?:up\s*)?until\b|pick[ -]?up.*(?:提升至|截止|截至|结束|結束)|(?:抽卡|抽抽乐|抽抽樂|招募|召唤|召喚|卡池).*(?:截止|截至|结束|結束|至)',
                      caseSensitive: false,
                    ).hasMatch(line) &&
                    RegExp(r'\d').hasMatch(line),
              )
              .firstOrNull;
          if (deadline != null) {
            period = _clean(deadline);
            periodKind = BannerPeriodKind.deadline;
          } else if (titleName != null && candidates.length == 1) {
            // This exception applies only to a named official pickup post,
            // never to a generic patch/event article with an arbitrary image.
            period = '文字时间尚未提供，请放大官方海报或查看官方卡池说明。';
            periodKind = BannerPeriodKind.artwork;
          } else {
            continue;
          }
        }
        final schedule = periodKind == BannerPeriodKind.range
            ? parseBannerTimes(period)
            : (
                null,
                periodKind == BannerPeriodKind.deadline
                    ? parseBannerDeadline(period)
                    : null,
              );
        final info = block
            .where((line) => !line.contains('@@IMAGE'))
            .join('\n');
        final limited =
            RegExp(
              r'(?<!not )\blimited\b|限定',
              caseSensitive: false,
            ).hasMatch(info) &&
            !RegExp(
              r'not (?:a )?limited|非限定|非限時|非限时',
              caseSensitive: false,
            ).hasMatch(info);
        final rerun = RegExp(
          r're-?run|复刻|復刻',
          caseSensitive: false,
        ).hasMatch(info);
        String? detail(RegExp pattern) {
          for (final line in block) {
            if (line.length < 200 && pattern.hasMatch(line)) {
              return _clean(line);
            }
          }
          return null;
        }

        final banner = SummonBanner(
          name: candidate.$2,
          picture: image.uri,
          period: period,
          periodKind: periodKind,
          source: post,
          type: limited
              ? '限定召唤'
              : rerun
              ? '复刻召唤'
              : '服装召唤',
          startsAt: schedule.$1,
          endsAt: schedule.$2,
          rate: detail(
            RegExp(
              r'(?:pick[ -]?up\s*)?(?:rate|probability)\s*[:：].*\d|(?:概率|機率)\s*[:：].*\d',
              caseSensitive: false,
            ),
          ),
          gear: detail(
            RegExp(
              r'^\s*(?:[-*]\s*)?(?:exclusive gear|专用装备|專用裝備|专属装备|專屬裝備)\s*[:：]',
              caseSensitive: false,
            ),
          ),
        );
        final key =
            '${banner.name.toLowerCase().replaceAll(RegExp(r'\s'), '')}|${banner.period.toLowerCase().replaceAll(RegExp(r'\s'), '')}';
        unique.putIfAbsent(key, () => banner);
      }
    }
  }
  return unique.values.toList();
}

/// Requires explicit clock times and a timezone; maintenance/date-only periods
/// remain verbatim instead of inventing a precise launch or ending time.
List<DateTime> _explicitBannerDates(String period) {
  var offsetMinutes = 0;
  final offset = RegExp(
    r'(?:UTC|GMT)\s*([+-])\s*(\d{1,2})(?::(\d{2}))?',
    caseSensitive: false,
  ).firstMatch(period);
  if (offset != null) {
    final hours = int.parse(offset.group(2)!);
    final minutes = int.parse(offset.group(3) ?? '0');
    if (hours > 14 || minutes > 59) return [];
    offsetMinutes = (hours * 60 + minutes) * (offset.group(1) == '-' ? -1 : 1);
  } else if (RegExp(r'\bMYT\b', caseSensitive: false).hasMatch(period)) {
    offsetMinutes = 480;
  } else if (!RegExp(
    r'\bUTC\b|\bGMT\b',
    caseSensitive: false,
  ).hasMatch(period)) {
    return [];
  }
  DateTime? make(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    String? ampm,
  ) {
    if (ampm != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (ampm.toLowerCase().startsWith('p') ? 12 : 0);
    }
    if (hour > 23 ||
        minute > 59 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    final value = DateTime.utc(year, month, day, hour, minute);
    if (value.month != month || value.day != day) return null;
    return value.subtract(Duration(minutes: offsetMinutes));
  }

  final numeric = RegExp(
    r'(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})日?[ T\s]+(\d{1,2})[:：](\d{2})\s*(AM|PM)?',
    caseSensitive: false,
  ).allMatches(period).toList();
  final times = <DateTime?>[];
  if (numeric.isNotEmpty && numeric.length <= 2) {
    for (final m in numeric) {
      times.add(
        make(
          int.parse(m[1]!),
          int.parse(m[2]!),
          int.parse(m[3]!),
          int.parse(m[4]!),
          int.parse(m[5]!),
          m[6],
        ),
      );
    }
  } else {
    final named = RegExp(
      r'(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\s+(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)',
      caseSensitive: false,
    ).allMatches(period).toList();
    final years = RegExp(
      r'\b(20\d{2})\b',
    ).allMatches(period).map((m) => int.parse(m[1]!)).toSet();
    const months = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];
    if (named.isEmpty || named.length > 2) return [];
    for (final m in named) {
      final year = m[3] == null
          ? (years.length == 1 ? years.single : null)
          : int.parse(m[3]!);
      if (year == null) return [];
      times.add(
        make(
          year,
          months.indexOf(m[1]!.toLowerCase().substring(0, 3)) + 1,
          int.parse(m[2]!),
          int.parse(m[4]!),
          int.parse(m[5] ?? '0'),
          m[6],
        ),
      );
    }
  }
  if (times.any((time) => time == null)) return [];
  return times.cast<DateTime>();
}

(DateTime?, DateTime?) parseBannerTimes(String period) {
  final times = _explicitBannerDates(period);
  if (times.length != 2 || !times.last.isAfter(times.first)) {
    return (null, null);
  }
  return (times.first, times.last);
}

DateTime? parseBannerDeadline(String period) {
  final times = _explicitBannerDates(period);
  return times.length == 1 ? times.single : null;
}
