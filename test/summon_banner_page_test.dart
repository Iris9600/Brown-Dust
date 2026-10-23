import 'package:bd2/announcements/summon_banner.dart';
import 'package:bd2/announcements/summon_banner_page.dart';
import 'package:bd2/app_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'summon_banner_test.dart' as fixtures;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Undated banners can be dismissed and stay dismissed after reopening',
    (tester) async {
      final banners = extractSummonBanners([
        fixtures.post(
          '<img src="/alice.jpg">',
          title: 'New Pickup - Moonlight Alice',
        ),
      ]);
      Widget page() => MaterialApp(
        home: Scaffold(
          body: SummonBannerPage(
            banners: banners,
            loading: false,
            onRefresh: () async {},
            onSource: (_) {},
            onRemind: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('Moonlight Alice'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('dismiss:${banners.single.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Moonlight Alice'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('Moonlight Alice'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Unit artwork, name and MYT schedule fit width $width without patch content',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final banners = extractSummonBanners([
          fixtures.post(fixtures.twoBanners),
        ]);
        SummonBanner? reminded;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.theme,
            home: Scaffold(
              body: SummonBannerPage(
                banners: banners,
                loading: false,
                now: () => DateTime.utc(2026, 10, 16),
                onRefresh: () async {},
                onSource: (_) {},
                onRemind: (banner) => reminded = banner,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Moonlight Alice'), findsOneWidget);
        expect(find.text('2026/10/15 08:00 MYT'), findsOneWidget);
        expect(find.text('2026/10/30 07:59 MYT'), findsOneWidget);
        expect(find.text('Maintenance update'), findsNothing);
        expect(find.text('Other update text'), findsNothing);
        final image = tester.widget<Image>(
          find.byKey(ValueKey('banner-image:${banners.first.id}')),
        );
        expect(
          (image.image as NetworkImage).url,
          'https://www.browndust2.com/images/alice.jpg',
        );
        await tester.ensureVisible(find.text('卡池提醒').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('卡池提醒').first);
        expect(reminded?.id, banners.first.id);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Expired banners are hidden without an option to show history', (
    tester,
  ) async {
    final banners = extractSummonBanners([fixtures.post(fixtures.twoBanners)]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme,
        home: Scaffold(
          body: SummonBannerPage(
            banners: banners,
            loading: false,
            now: () => DateTime.utc(2026, 11, 1),
            onRefresh: () async {},
            onSource: (_) {},
            onRemind: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Moonlight Alice'), findsNothing);
    expect(find.text('Forest Beth'), findsNothing);
    expect(find.text('全部卡池'), findsNothing);
    expect(find.text('已结束'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Upcoming banners remain visible until their end time', (
    tester,
  ) async {
    final banners = extractSummonBanners([fixtures.post(fixtures.twoBanners)]);
    var now = DateTime.utc(2026, 10, 14);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme,
        home: Scaffold(
          body: SummonBannerPage(
            banners: banners,
            loading: false,
            now: () => now,
            onRefresh: () async {},
            onSource: (_) {},
            onRemind: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Moonlight Alice'), findsOneWidget);
    expect(find.text('即将开启'), findsWidgets);

    now = DateTime.utc(2026, 10, 15);
    await tester.pump(const Duration(days: 1));
    expect(find.text('Moonlight Alice'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);

    now = DateTime.utc(2026, 10, 29, 23, 58, 59);
    await tester.pump(now.difference(DateTime.utc(2026, 10, 15)));
    expect(find.text('Moonlight Alice'), findsOneWidget);

    now = DateTime.utc(2026, 10, 29, 23, 59);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Moonlight Alice'), findsNothing);
    expect(find.text('Forest Beth'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Official poster opens an enlargeable view to read its printed period',
    (tester) async {
      final banners = extractSummonBanners([
        fixtures.post(
          '<img src="/uploads/alice.jpg">',
          title: 'New Pickup - Moonlight Alice',
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme,
          home: Scaffold(
            body: SummonBannerPage(
              banners: banners,
              loading: false,
              now: () => DateTime.utc(2026, 10, 16),
              onRefresh: () async {},
              onSource: (_) {},
              onRemind: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('官方海报排期'), findsOneWidget);
      await tester.tap(find.byTooltip('放大官方卡池海报'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('关闭海报'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
