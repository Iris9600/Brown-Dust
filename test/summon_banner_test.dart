import 'package:bd2/announcements/official_news.dart';
import 'package:bd2/announcements/summon_banner.dart';
import 'package:flutter_test/flutter_test.dart';

const twoBanners = '''
<h2>■ Event Update</h2><p>Unrelated event schedule</p>
<img src="https://www.browndust2.com/images/event.jpg">
<h2>■ Pick-up Information</h2>
<h3>1) Moonlight Alice Costume and Exclusive Gear Pick-up</h3>
<p>Pick-up Period: 2026/10/15 00:00 ~ 2026/10/29 23:59 (UTC)</p>
<img src="https://www.browndust2.com/images/alice.jpg" alt="Moonlight Alice">
<p>Rate: 1.5%</p><p>Exclusive Gear: Lunar Blade</p><p>Limited costume.</p>
<h3>2) Forest Beth Costume Pick-up</h3>
<p>Pick-up Period: 2026/10/16 00:00 ~ 2026/10/30 23:59 (UTC)</p>
<img src="https://www.browndust2.com/images/beth.jpg" alt="Forest Beth">
<p>This is not a limited costume.</p>
<h2>■ Bug Fixes</h2><p>Other update text</p><img src="https://www.browndust2.com/images/fix.jpg">
''';
OfficialNews post(
  String body, {
  String title = 'Maintenance update',
  String id = '1',
  DateTime? updated,
}) => OfficialNews(
  id: id,
  title: title,
  content: body,
  tag: 'notice',
  locale: 'en-us',
  updatedAt: updated,
);
void main() {
  test(
    'Extracts individual named banners and matches each unit image and time',
    () {
      final banners = extractSummonBanners([post(twoBanners)]);
      expect(banners.map((b) => b.name), ['Moonlight Alice', 'Forest Beth']);
      expect(banners.map((b) => b.picture.path), [
        '/images/alice.jpg',
        '/images/beth.jpg',
      ]);
      expect(banners.first.startsAt, DateTime.utc(2026, 10, 15));
      expect(banners.first.endsAt, DateTime.utc(2026, 10, 29, 23, 59));
      expect(banners.first.rate, 'Rate: 1.5%');
      expect(banners.first.gear, 'Exclusive Gear: Lunar Blade');
      expect(banners.first.type, '限定召唤');
      expect(banners.last.type, '服装召唤');
      expect(banners.map((b) => b.id).toSet().length, 2);
    },
  );
  test(
    'General patch notes, event images and incidental pickup mentions produce no cards',
    () {
      expect(
        extractSummonBanners([
          post(
            '<h2>Event Update</h2><p>Pick-up information will arrive later.</p><img src="https://www.browndust2.com/event.png"><p>Period: 2026/10/15 00:00 ~ 2026/10/29 00:00 UTC</p>',
          ),
        ]),
        isEmpty,
      );
    },
  );
  test('A name, associated image and explicit summon period are all required', () {
    final source =
        '''<h2>■ Pick-up Information</h2><h3>1) Moonlight Alice Costume Pick-up</h3><p>Period: 2026/10/15 00:00 ~ 2026/10/29 00:00 UTC</p>''';
    expect(extractSummonBanners([post(source)]), isEmpty);
    expect(
      extractSummonBanners([
        post('$source<img src="https://evil.example/wrong.png">'),
      ]),
      isEmpty,
    );
    expect(extractSummonBanners([post('$source<img src="">')]), isEmpty);
    expect(
      extractSummonBanners([
        post(
          '${source.replaceAll(RegExp(r'<p>.*</p>'), '')}<img src="https://www.browndust2.com/alice.png">',
        ),
      ]),
      isEmpty,
    );
  });
  test('Standalone named pickup posts support Markdown artwork', () {
    final banners = extractSummonBanners([
      post(
        '''![Alice](https://www.browndust2.com/alice.png)
Pick-up Period: 2026/10/15 00:00 ~ 2026/10/29 23:59 UTC''',
        title: 'New Pickup - Moonlight Alice',
      ),
    ]);
    expect(banners.single.name, 'Moonlight Alice');
    expect(banners.single.picture.path, '/alice.png');
  });
  test('Chinese sections and MYT schedule are supported', () {
    final banners = extractSummonBanners([
      post(
        '''<h2>■ 招募資訊</h2><h3>1）「月光」愛麗絲服裝與專用裝備登場</h3>
<p>招募期間：2026年10月15日 08:00 ～ 2026年10月30日 07:59 MYT</p><img src="/images/alice.png">''',
      ),
    ]);
    expect(banners.single.name, '月光愛麗絲');
    expect(banners.single.startsAt, DateTime.utc(2026, 10, 15));
  });
  test(
    'Maintenance boundaries remain exact official text without invented clock times',
    () {
      final banners = extractSummonBanners([
        post(
          '''<h2>■ Pick-up Information</h2><h3>1) Moonlight Alice Costume Pick-up</h3>
<p>Period: After maintenance October 15, 2026 ~ before maintenance October 29, 2026 (UTC)</p><img src="/images/alice.png">''',
        ),
      ]);
      expect(banners.single.period, contains('After maintenance'));
      expect(banners.single.startsAt, isNull);
      expect(banners.single.endsAt, isNull);
      expect(banners.single.status(DateTime.utc(2026, 10, 16)), '官方召唤');
    },
  );
  test(
    'Repeated official notices are deduplicated using the newest source',
    () {
      final banners = extractSummonBanners([
        post(twoBanners, id: 'old', updated: DateTime.utc(2026, 10, 15)),
        post(twoBanners, id: 'new', updated: DateTime.utc(2026, 10, 16)),
      ]);
      expect(banners.length, 2);
      expect(banners.first.source.id, 'new');
    },
  );
  test(
    'Explicit times support English dates, AM/PM, offsets and status boundaries',
    () {
      expect(
        parseBannerTimes(
          'October 15th 12:00 am - October 29th 11:59 pm, 2026 (UTC)',
        ),
        (DateTime.utc(2026, 10, 15), DateTime.utc(2026, 10, 29, 23, 59)),
      );
      expect(parseBannerTimes('2026/10/15 09:00 ~ 2026/10/29 09:00 UTC+9'), (
        DateTime.utc(2026, 10, 15),
        DateTime.utc(2026, 10, 29),
      ));
      expect(parseBannerTimes('2026/02/30 00:00 ~ 2026/03/02 00:00 UTC'), (
        null,
        null,
      ));
      expect(parseBannerTimes('2026/10/15 00:00 ~ 2026/10/29 00:00'), (
        null,
        null,
      ));
      expect(parseBannerTimes('2026/10/29 00:00 ~ 2026/10/15 00:00 UTC'), (
        null,
        null,
      ));
      final banner = extractSummonBanners([post(twoBanners)]).first;
      expect(banner.status(DateTime.utc(2026, 10, 14)), '即将开启');
      expect(banner.status(DateTime.utc(2026, 10, 15)), '进行中');
      expect(banner.status(DateTime.utc(2026, 10, 29, 23, 59)), '已结束');
    },
  );
  test(
    'Named official pickup posters are preserved when times are in the artwork',
    () {
      final banners = extractSummonBanners([
        post(
          '<img src="https://www.browndust2.com/uploads/alice.jpg" alt="Moonlight Alice">',
          title: 'New Pickup - Moonlight Alice',
        ),
      ]);
      expect(banners.single.name, 'Moonlight Alice');
      expect(banners.single.periodKind, BannerPeriodKind.artwork);
      expect(banners.single.startsAt, isNull);
      expect(banners.single.endsAt, isNull);
      expect(banners.single.status(DateTime.utc(2026, 10, 16)), '排期待核实');
      expect(
        extractSummonBanners([
          post(
            '<img src="https://www.browndust2.com/uploads/maintenance.jpg">',
          ),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'Official promotional deadline is kept without inventing a starting time',
    () {
      final banners = extractSummonBanners([
        post(
          '''<img src="/uploads/alice.jpg">
<p>Pickup rate UP until October 29, 2026 11:59 pm (UTC)</p>''',
          title: 'New Pickup - Moonlight Alice',
        ),
      ]);
      expect(banners.single.periodKind, BannerPeriodKind.deadline);
      expect(banners.single.startsAt, isNull);
      expect(banners.single.endsAt, DateTime.utc(2026, 10, 29, 23, 59));
    },
  );
  test(
    'Chinese official pickup subject and maintenance deadline keep source wording',
    () {
      final banners = extractSummonBanners([
        post(
          '''<img src="/uploads/alice.jpg"><p>抽抽乐概率提升至2026年10月29日维护前</p>''',
          title: '📢新Pickup – 月光爱丽丝',
        ),
      ]);
      expect(banners.single.name, '月光爱丽丝');
      expect(banners.single.periodKind, BannerPeriodKind.deadline);
      expect(banners.single.period, contains('2026年10月29日维护前'));
      expect(banners.single.endsAt, isNull);
    },
  );
}
