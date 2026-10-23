import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_design.dart';
import 'summon_banner.dart';

class SummonBannerPage extends StatefulWidget {
  const SummonBannerPage({
    super.key,
    required this.banners,
    required this.loading,
    required this.onRefresh,
    required this.onSource,
    required this.onRemind,
    this.error,
    this.lastUpdated,
    this.usingEnglish = false,
    this.onOfficialIndex,
    this.onYoutubeChannel,
    this.now = DateTime.now,
  });
  final List<SummonBanner> banners;
  final VoidCallback? onOfficialIndex;
  final VoidCallback? onYoutubeChannel;
  final bool loading, usingEnglish;
  final String? error;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;
  final void Function(SummonBanner) onSource, onRemind;
  final DateTime Function() now;
  @override
  State<SummonBannerPage> createState() => _SummonBannerPageState();
}

String _myt(DateTime value) {
  final date = value.toUtc().add(const Duration(hours: 8));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)} ${two(date.hour)}:${two(date.minute)} MYT';
}

class _SummonBannerPageState extends State<SummonBannerPage> {
  Timer? _boundaryTimer;
  final _dismissed = <String>{};
  String? _dismissError;
  static const _dismissKey = 'dismissed_summon_banners_v1';

  @override
  void initState() {
    super.initState();
    unawaited(_loadDismissed());
  }

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _dismissed.addAll(prefs.getStringList(_dismissKey) ?? []));
    } catch (_) {
      if (mounted) setState(() => _dismissError = '无法读取已移除的卡池。');
    }
  }

  Future<void> _dismiss(SummonBanner banner) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = {..._dismissed, banner.id};
      if (!await prefs.setStringList(_dismissKey, ids.toList())) {
        throw StateError('Unable to save dismissal');
      }
      if (mounted) {
        setState(() {
          _dismissed.add(banner.id);
          _dismissError = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _dismissError = '无法保存移除操作，请重试。');
    }
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    super.dispose();
  }

  void _scheduleBoundary(DateTime now) {
    _boundaryTimer?.cancel();
    final boundaries =
        widget.banners
            .expand((banner) => [banner.startsAt, banner.endsAt])
            .whereType<DateTime>()
            .where((time) => time.isAfter(now))
            .toList()
          ..sort();
    if (boundaries.isNotEmpty) {
      _boundaryTimer = Timer(boundaries.first.difference(now), () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    _scheduleBoundary(now);
    final banners = widget.banners
        .where(
          (item) =>
              !item.ended(now) &&
              (item.endsAt != null || !_dismissed.contains(item.id)),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'SUMMON BANNERS',
            style: TextStyle(
              fontSize: 12,
              color: AppDesign.gold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '角色 · 服装 · 召唤时间',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (widget.onYoutubeChannel != null)
            const Text(
              'YouTube 角色影片仅保留最近两个月。',
              style: TextStyle(color: AppDesign.muted, fontSize: 12),
            ),
          if (_dismissError != null) Text(_dismissError!),
          if (widget.onYoutubeChannel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onYoutubeChannel,
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: const Text('官方 YouTube 角色影片'),
              ),
            ),
          if (widget.onOfficialIndex != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onOfficialIndex,
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('官方中文公告来源'),
              ),
            ),
          if (widget.lastUpdated != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '同步：${_myt(widget.lastUpdated!)}',
                style: const TextStyle(fontSize: 12, color: AppDesign.muted),
              ),
            ),
          if (widget.usingEnglish)
            const Text(
              '当前使用官方英文卡池资料。',
              style: TextStyle(color: AppDesign.gold, fontSize: 12),
            ),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (widget.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.error!,
                      style: const TextStyle(color: AppDesign.gold),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onRefresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (banners.isEmpty && !widget.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 44,
                    color: AppDesign.gold,
                  ),
                  SizedBox(height: 16),
                  Text('暂无可确认的召唤卡池', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text(
                    '尚未取得可匹配的角色图片、名称和召唤期间。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppDesign.muted),
                  ),
                ],
              ),
            ),
          for (final banner in banners)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      _poster(banner),
                      if (banner.endsAt == null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton.filled(
                            key: ValueKey('dismiss:${banner.id}'),
                            tooltip: '移除此卡池',
                            onPressed: () => _dismiss(banner),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Chip(label: Text(banner.type)),
                            Chip(label: Text(banner.status(now))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          banner.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: AppDesign.gold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (banner.source.tag == 'video' &&
                            banner.source.publishedAt != null) ...[
                          _timeRow('发布', _myt(banner.source.publishedAt!)),
                          const SizedBox(height: 8),
                        ],
                        if (banner.startsAt != null &&
                            banner.endsAt != null) ...[
                          _timeRow('开始', _myt(banner.startsAt!)),
                          const SizedBox(height: 6),
                          _timeRow('结束', _myt(banner.endsAt!)),
                        ] else if (banner.endsAt != null) ...[
                          _timeRow('截止', _myt(banner.endsAt!)),
                        ] else ...[
                          Text(
                            banner.source.tag == 'video'
                                ? '召唤期间待确认'
                                : banner.periodKind == BannerPeriodKind.artwork
                                ? '官方海报排期'
                                : banner.periodKind == BannerPeriodKind.deadline
                                ? '召唤截止'
                                : '召唤期间',
                            style: TextStyle(
                              color: AppDesign.crystal,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            banner.period,
                            style: const TextStyle(height: 1.6),
                          ),
                        ],
                        if (banner.rate != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(banner.rate!),
                          ),
                        if (banner.gear != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              banner.gear!,
                              style: const TextStyle(color: AppDesign.muted),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            if (banner.source.tag != 'video')
                              FilledButton.icon(
                                onPressed: () => widget.onRemind(banner),
                                icon: const Icon(
                                  Icons.notification_add_outlined,
                                  size: 18,
                                ),
                                label: const Text('卡池提醒'),
                              ),
                            TextButton.icon(
                              onPressed: () => widget.onSource(banner),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(
                                banner.source.tag == 'video'
                                    ? '观看官方影片'
                                    : '官方卡池说明',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _artwork(SummonBanner banner, {bool fullScreen = false}) =>
      Image.network(
        banner.picture.toString(),
        key: fullScreen ? null : ValueKey('banner-image:${banner.id}'),
        semanticLabel: '${banner.name} 官方召唤卡池海报',
        fit: BoxFit.contain,
        loadingBuilder: (context, image, progress) => progress == null
            ? image
            : const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, stack) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                color: AppDesign.muted,
                size: 32,
              ),
              SizedBox(height: 8),
              Text('角色图片暂时无法加载', style: TextStyle(color: AppDesign.muted)),
            ],
          ),
        ),
      );
  Widget _poster(SummonBanner banner) => banner.source.tag == 'video'
      ? Tooltip(
          message: '观看官方影片',
          child: InkWell(
            key: ValueKey('video-preview:${banner.id}'),
            onTap: () => widget.onSource(banner),
            child: Stack(
              children: [
                AspectRatio(aspectRatio: 16 / 9, child: _artwork(banner)),
                const Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 64,
                      color: AppDesign.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
      : Tooltip(
          message: '放大官方卡池海报',
          child: InkWell(
            onTap: () => _showPoster(banner),
            child: Stack(
              children: [
                ColoredBox(
                  color: const Color(0xFF101A23),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _artwork(banner),
                  ),
                ),
                const Positioned(
                  bottom: 8,
                  right: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xCC11171D),
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Row(
                        children: [
                          Icon(Icons.zoom_in, size: 18, color: AppDesign.gold),
                          SizedBox(width: 4),
                          Text(
                            '放大海报',
                            style: TextStyle(
                              color: AppDesign.gold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
  void _showPoster(SummonBanner banner) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: const Color(0xFF10171C),
          appBar: AppBar(
            leading: IconButton(
              tooltip: '关闭海报',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              banner.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18),
            ),
          ),
          body: SafeArea(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(child: _artwork(banner, fullScreen: true)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeRow(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 42,
        child: Text(label, style: const TextStyle(color: AppDesign.muted)),
      ),
      Expanded(
        child: Text(value, style: const TextStyle(color: AppDesign.crystal)),
      ),
    ],
  );
}
