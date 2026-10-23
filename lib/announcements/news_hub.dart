import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_design.dart';
import 'official_news.dart';
import 'news_notifications.dart';
import 'summon_banner.dart';
import 'summon_banner_page.dart';
import 'youtube_banners.dart';

String newsTime(DateTime time) {
  final t = time.toUtc().add(const Duration(hours: 8));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} MYT';
}

class NewsHub extends StatefulWidget {
  const NewsHub({
    super.key,
    this.repository,
    this.notifications,
    this.initialTab = 0,
    this.now = DateTime.now,
    this.youtubeRepository,
  });
  final NewsRepository? repository;
  final NewsNotifications? notifications;
  final int initialTab;
  final DateTime Function() now;
  final YoutubeBannerRepository? youtubeRepository;
  @override
  State<NewsHub> createState() => _NewsHubState();
}

class _NewsHubState extends State<NewsHub> with WidgetsBindingObserver {
  late final NewsRepository _news = widget.repository ?? NewsRepository();
  late final YoutubeBannerRepository _youtube =
      widget.youtubeRepository ?? YoutubeBannerRepository();
  late final NewsNotifications _notifications =
      widget.notifications ?? NewsNotifications();
  late int _tab = widget.initialTab;
  Timer? _timer;
  Map<String, dynamic> _status = {};
  bool _busy = false;
  List<SummonBanner> get _banners => [..._news.banners, ..._youtube.items];

  static const _labels = ['活动', '更新', '召唤卡池', '通知'];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _news.addListener(_changed);
    _youtube.addListener(_changed);
    unawaited(_youtube.initialize());
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _refresh());
    unawaited(_initialize());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    await _news.initialize();
    if (!mounted) return;
    await _loadStatus();
    await _observe();
  }

  Future<void> _loadStatus() async {
    try {
      final value = await _notifications.status();
      if (mounted) setState(() => _status = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = {
            'supported': false,
            'error': 'Android 通知服务暂时不可用，请使用重新构建的应用。',
          },
        );
      }
    }
  }

  Future<void> _observe() async {
    if (_news.error != null || _news.lastUpdated == null) return;
    try {
      await _notifications.observe(_news.items);
      await _loadStatus();
    } catch (_) {
      _message('公告已加载，但通知同步失败。请在通知页重试。');
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_news.refresh(), _youtube.refresh()]);
    if (mounted) await _observe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _news.removeListener(_changed);
    _news.dispose();
    _youtube.removeListener(_changed);
    _youtube.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _loadStatus();
    } catch (_) {
      _message('操作失败，请检查系统通知权限后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _message('无法打开浏览器，请稍后重试。');
      }
    } catch (_) {
      _message('无法打开浏览器，请稍后重试。');
    }
  }

  Future<void> _remind(
    OfficialNews item, {
    String? reminderId,
    String? title,
  }) async {
    if (!_notifications.supported) {
      _message('手机系统提醒仅在 Android 应用中提供。');
      return;
    }
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final day = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: day,
      lastDate: day.add(const Duration(days: 365)),
      helpText: '选择提醒日期（MYT）',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (now.hour + 1) % 24, minute: 0),
      helpText: '选择提醒时间（MYT）',
    );
    if (time == null || !mounted) return;
    final instant = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 8));
    if (!instant.isAfter(DateTime.now().toUtc())) {
      _message('请选择未来的提醒时间。');
      return;
    }
    await _action(() async {
      if (!await _notifications.requestPermission()) {
        _message('通知权限未开启，提醒未保存。');
        return;
      }
      await _notifications.schedule(
        item,
        instant,
        reminderId: reminderId,
        title: title,
      );
      _message('已设置提醒：${newsTime(instant)}。系统省电可能延迟提醒。');
    });
  }

  Future<void> _detail(OfficialNews item) async {
    try {
      item = await _news.loadDetail(item);
    } catch (_) {
      _message('完整公告暂时无法加载，当前显示摘要，可打开官方原文。');
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('官方公告', style: TextStyle(fontSize: 20)),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 24,
                        color: AppDesign.gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.publishedAt == null
                          ? '发布日期未提供'
                          : newsTime(item.publishedAt!),
                      style: const TextStyle(color: AppDesign.muted),
                    ),
                    const SizedBox(height: 16),
                    if (item.image != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Image.network(
                          item.image.toString(),
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _open(item.url),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('打开官方原文'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _remind(item),
                          icon: const Icon(Icons.notification_add_outlined),
                          label: const Text('设置提醒'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SelectableText(
                      item.text.isEmpty ? '此公告的正文暂不可用，请查看官方原文。' : item.text,
                      style: const TextStyle(height: 1.7),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '时间、奖励与卡池安排以官方原文及游戏内公告为准。',
                      style: TextStyle(color: AppDesign.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OFFICIAL INTELLIGENCE',
            style: TextStyle(fontSize: 10, letterSpacing: 2),
          ),
          Text('冒险情报 · ${_labels[_tab]}', style: const TextStyle(fontSize: 19)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '刷新官方公告',
          onPressed: _news.loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      backgroundColor: AppDesign.panel,
      indicatorColor: AppDesign.gold,
      selectedIndex: _tab,
      onDestinationSelected: (value) {
        setState(() => _tab = value);
        if (value == 3) unawaited(_loadStatus());
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.celebration_outlined),
          label: '活动',
        ),
        NavigationDestination(icon: Icon(Icons.campaign_outlined), label: '更新'),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          label: '召唤卡池',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_outlined),
          label: '通知',
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: _tab == 3
              ? _notificationPage()
              : _tab == 2
              ? SummonBannerPage(
                  banners: _banners,
                  loading: _news.loading || _youtube.loading,
                  error: _news.error ?? _youtube.error,
                  lastUpdated: _news.lastUpdated,
                  usingEnglish: _news.usingEnglish,
                  onOfficialIndex: () =>
                      _open(NewsRepository.officialChineseIndex),
                  onYoutubeChannel: () => _open(officialYoutubeChannel),
                  onRefresh: _refresh,
                  onSource: (banner) => _open(banner.source.url),
                  onRemind: (banner) => _remind(
                    banner.source,
                    reminderId: banner.id,
                    title: banner.name,
                  ),
                )
              : _feedPage(),
        ),
      ),
    ),
  );

  Widget _feedPage() {
    final category = NewsCategory.values[_tab];
    final items = recentNews(
      _news.items,
      category: category,
      now: widget.now(),
    );
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            ['EVENT ARCHIVE', 'UPDATE BULLETIN', 'SUMMON INTELLIGENCE'][_tab],
            style: const TextStyle(
              color: AppDesign.gold,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '仅显示最近两个月的官方公告。下拉可刷新。',
            style: const TextStyle(color: AppDesign.muted),
          ),
          if (_news.lastUpdated != null)
            Text(
              '上次同步：${newsTime(_news.lastUpdated!)}',
              style: const TextStyle(color: AppDesign.muted, fontSize: 12),
            ),
          if (_news.usingEnglish)
            const Text(
              '中文公告暂不可用，当前显示官方英文公告。',
              style: TextStyle(color: AppDesign.gold),
            ),
          if (_news.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LinearProgressIndicator(),
            ),
          if (_news.error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_news.error!),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('重试'),
                        ),
                        TextButton(
                          onPressed: () =>
                              _open(NewsRepository.officialChineseIndex),
                          child: const Text('打开官方网站'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (!_news.loading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 48,
                    color: AppDesign.gold,
                  ),
                  SizedBox(height: 16),
                  Text('暂无可显示的官方公告'),
                  SizedBox(height: 8),
                  Text(
                    '成功同步后将在这里显示，不使用示例或过期活动填充。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppDesign.muted),
                  ),
                ],
              ),
            ),
          for (final item in items)
            Card(
              child: InkWell(
                onTap: () => _detail(item),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.tag.isEmpty
                            ? 'OFFICIAL NEWS'
                            : item.tag.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppDesign.gold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.publishedAt == null
                            ? '发布日期未提供'
                            : newsTime(item.publishedAt!),
                        style: const TextStyle(
                          color: AppDesign.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Row(
                        children: [
                          Expanded(
                            child: Text(
                              '阅读公告与设置提醒',
                              style: TextStyle(color: AppDesign.crystal),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: AppDesign.gold),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _notificationPage() {
    final supported = _status['supported'] == true;
    final allowed = _status['permission'] == true;
    final enabled = _status['enabled'] == true;
    final reminders = (_status['reminders'] as List? ?? []).cast<Map>();
    final alerts = (_status['alerts'] as List? ?? []).cast<Map>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'YOUR WATCHLIST',
          style: TextStyle(
            color: AppDesign.gold,
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Android 系统通知',
                  style: TextStyle(fontSize: 20, color: AppDesign.gold),
                ),
                const SizedBox(height: 8),
                Text(
                  supported
                      ? '开启后约每小时检查一次官方公告，关闭应用后也可检查。首次同步建立基准，不推送历史公告。'
                      : '请在 Android 安装版中使用手机系统通知。当前平台仍可浏览官方公告。',
                ),
                const SizedBox(height: 8),
                const Text(
                  '系统省电、断网或强制停止可能推迟检查。此功能是定期检查，不是即时推送。',
                  style: TextStyle(fontSize: 12, color: AppDesign.muted),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动公告通知'),
                  subtitle: Text(
                    allowed ? (enabled ? '已开启' : '已关闭') : '需要系统通知权限',
                  ),
                  value: enabled && allowed,
                  onChanged: !supported || _busy
                      ? null
                      : (value) => _action(() async {
                          if (value &&
                              !await _notifications.requestPermission()) {
                            _message('通知权限未开启。可前往系统设置允许通知。');
                            return;
                          }
                          await _notifications.setEnabled(value);
                          if (value && _news.error == null) {
                            await _notifications.observe(_news.items);
                          }
                        }),
                ),
                for (final category in NewsCategory.values)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(['活动公告', '更新与维护', '召唤卡池'][category.index]),
                    value: _status[category.name] != false,
                    onChanged: !supported || _busy
                        ? null
                        : (value) => _action(
                            () => _notifications.setCategory(
                              category.name,
                              value,
                            ),
                          ),
                  ),
                if (supported)
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _action(() async {
                                if (!await _notifications.requestPermission()) {
                                  _message('需要系统通知权限。');
                                  return;
                                }
                                await _notifications.test();
                              }),
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('发送测试通知'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _action(_notifications.settings),
                        child: const Text('系统通知设置'),
                      ),
                    ],
                  ),
                if (_status['lastCheck'] is num &&
                    (_status['lastCheck'] as num) > 0)
                  Text(
                    '后台最近同步：${newsTime(DateTime.fromMillisecondsSinceEpoch((_status['lastCheck'] as num).toInt(), isUtc: true))}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppDesign.muted,
                    ),
                  ),
                if (_status['error'] is String &&
                    (_status['error'] as String).isNotEmpty)
                  Text(
                    _status['error'] as String,
                    style: const TextStyle(color: AppDesign.gold),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '已设置的提醒',
          style: TextStyle(fontSize: 18, color: AppDesign.gold),
        ),
        const Text(
          '从公告详情中选择「设置提醒」，按马来西亚时间设置。',
          style: TextStyle(color: AppDesign.muted),
        ),
        if (reminders.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('暂无提醒。')),
        for (final reminder in reminders)
          Card(
            child: ListTile(
              title: Text(reminder['title'] as String? ?? ''),
              subtitle: Text(
                newsTime(
                  DateTime.fromMillisecondsSinceEpoch(
                    (reminder['at'] as num).toInt(),
                    isUtc: true,
                  ),
                ),
              ),
              trailing: IconButton(
                tooltip: '取消提醒',
                onPressed: _busy
                    ? null
                    : () => _action(
                        () => _notifications.cancel(reminder['id'].toString()),
                      ),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        const SizedBox(height: 18),
        const Text(
          '最近通知',
          style: TextStyle(fontSize: 18, color: AppDesign.gold),
        ),
        if (alerts.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('暂无通知记录。')),
        for (final alert in alerts)
          Card(
            child: ListTile(
              title: Text(alert['title'] as String? ?? ''),
              subtitle: Text(
                newsTime(
                  DateTime.fromMillisecondsSinceEpoch(
                    (alert['at'] as num).toInt(),
                    isUtc: true,
                  ),
                ),
              ),
              onTap: () {
                final url = Uri.tryParse(alert['url'] as String? ?? '');
                if (url?.host == 'www.browndust2.com' &&
                    url?.scheme == 'https') {
                  _open(url!);
                }
              },
            ),
          ),
      ],
    );
  }
}
