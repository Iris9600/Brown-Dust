import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'resource_history.dart';
import 'app_design.dart';
import 'mission_schedule.dart';
import 'announcements/news_hub.dart';
import 'amount_dialog.dart';
import 'mission_data.dart';
import 'mission_widgets.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '棕色尘埃 2 · 任务清单',
    debugShowCheckedModeBanner: false,
    theme: AppDesign.theme,
    home: const MissionPage(),
  );
}

class MissionPage extends StatefulWidget {
  const MissionPage({super.key, this.now = DateTime.now});
  final DateTime Function() now;
  @override
  State<MissionPage> createState() => _MissionPageState();
}

class _MissionPageState extends State<MissionPage> with WidgetsBindingObserver {
  final Map<String, int> _amounts = {};
  final Set<String> _done = {};
  final Map<String, Map<String, int>> _resources = {};
  final ResourceHistory _history = ResourceHistory();
  final Map<String, String> _completedDates = {};
  Timer? _retentionTimer;
  Timer? _midnightTimer;
  String? _dailyDate;
  String? _weeklyDate;
  SharedPreferences? _prefs;
  bool _loading = true;
  bool _failed = false;
  int _tab = 0;
  Future<void> _pending = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _retentionTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshRetention(),
    );
    _load();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    if (!mounted || _failed) return;
    _midnightTimer = Timer(ResourceHistory.untilMidnight(widget.now()), () {
      _refreshRetention();
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    _retentionTimer?.cancel();
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRetention();
      _scheduleMidnight();
    }
  }

  void _clearChecklist(int tab) {
    final prefix = '$tab:';
    _done.removeWhere((id) => id.startsWith(prefix));
    _amounts.removeWhere((id, _) => id.startsWith(prefix));
    _resources.removeWhere((id, _) => id.startsWith(prefix));
    _completedDates.removeWhere((id, _) => id.startsWith(prefix));
  }

  void _prune() {
    final now = widget.now();
    final today = ResourceHistory.dateKey(now);
    if (_dailyDate != today) {
      _clearChecklist(0);
      _dailyDate = today;
    }
    final week = MissionSchedule.weekKey(now);
    if (_weeklyDate != week) {
      _clearChecklist(1);
      _weeklyDate = week;
    }
    _history.prune(now);
    final retained = ResourceHistory.retainedDates(now).toSet();
    final expired = _completedDates.keys
        .where((id) => !retained.contains(_completedDates[id]))
        .toList();
    for (final id in expired) {
      _done.remove(id);
      _amounts.remove(id);
      _resources.remove(id);
      _completedDates.remove(id);
    }
  }

  void _refreshRetention() {
    if (_loading || _failed || !mounted) return;
    setState(_prune);
    _save();
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString('checklist_v1');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _dailyDate = data['dailyDate'] as String?;
        _weeklyDate = data['weeklyDate'] as String?;
        final amounts = Map<String, int>.from(data['amounts'] as Map);
        final done = List<String>.from(data['done'] as List);
        if (amounts.values.any((v) => v < 0)) throw const FormatException();
        _amounts.addAll(amounts);
        _done.addAll(done);
        final resources = data['resources'] as Map? ?? {};
        for (final entry in resources.entries) {
          _resources[entry.key as String] = Map<String, int>.from(
            entry.value as Map,
          );
        }
        if (_resources.values.any((r) => r.values.any((v) => v < 0))) {
          throw const FormatException();
        }
        if (data['history'] != null) {
          for (final entry in (data['history'] as Map).entries) {
            final rewards = Map<String, int>.from(entry.value as Map);
            if (rewards.values.any((v) => v < 0)) throw const FormatException();
            _history.days[entry.key as String] = rewards;
          }
          _completedDates.addAll(
            Map<String, String>.from(data['completedDates'] as Map),
          );
          if (_done.any((id) => !_completedDates.containsKey(id))) {
            throw const FormatException();
          }
        } else {
          // Legacy completed tasks have no date; import them as today's records.
          final today = ResourceHistory.dateKey(widget.now());
          for (var tab = 0; tab < 2; tab++) {
            for (var index = 0; index < _items(tab).length; index++) {
              final id = _id(tab, index);
              if (_done.contains(id)) {
                _completedDates[id] = today;
                _history.adjust(today, _reward(tab, index), 1);
              }
            }
          }
        }
      }
      // Upgrade old saves: retain today's checks, reset older daily progress.
      _dailyDate ??=
          _completedDates.entries
              .where((entry) => entry.key.startsWith('0:'))
              .map((entry) => entry.value)
              .firstOrNull ??
          ResourceHistory.dateKey(widget.now());
      // Infer a legacy save's weekly period before applying catch-up resets.
      final weeklyDates =
          _completedDates.entries
              .where((entry) => entry.key.startsWith('1:'))
              .map((entry) => entry.value)
              .toList()
            ..sort();
      final previousDate = weeklyDates.firstOrNull ?? _dailyDate;
      _weeklyDate ??= MissionSchedule.weekKey(
        DateTime.tryParse('${previousDate}T00:00:00+08:00') ?? widget.now(),
      );
      _prune();
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
    if (!_failed) {
      _save();
      _scheduleMidnight();
    }
  }

  String _id(int tab, int index) => '$tab:$index';
  List<List<Object>> _items(int tab) => tab == 0 ? daily : weekly;
  int _amount(int tab, int index) =>
      _amounts[_id(tab, index)] ?? _items(tab)[index][2] as int;
  int _earned(int tab) {
    var total = 0;
    for (var i = 0; i < _items(tab).length; i++) {
      if (_done.contains(_id(tab, i))) total += _amount(tab, i);
    }
    return total;
  }

  Map<String, int> _reward(int tab, int index) => {
    ...?_resources[_id(tab, index)],
    '钻石': _amount(tab, index),
  };

  void _save() {
    _prune();
    final snapshot = jsonEncode({
      'done': _done.toList(),
      'amounts': _amounts,
      'resources': _resources,
      'history': _history.days,
      'completedDates': _completedDates,
      'dailyDate': _dailyDate,
      'weeklyDate': _weeklyDate,
    });
    _pending = _pending.then((_) async {
      try {
        if (await _prefs?.setString('checklist_v1', snapshot) != true) {
          throw StateError('save');
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('保存失败，请勿关闭应用。')));
        }
      }
    });
  }

  Future<void> _editAmount(int index) async {
    final tab = _tab;
    final openedDate = ResourceHistory.dateKey(widget.now());
    final openedWeek = MissionSchedule.weekKey(widget.now());
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => AmountDialog(initial: _reward(tab, index)),
    );
    if (result != null && mounted) {
      if ((tab == 0 && openedDate != ResourceHistory.dateKey(widget.now())) ||
          (tab == 1 && openedWeek != MissionSchedule.weekKey(widget.now()))) {
        _refreshRetention();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tab == 0 ? '已到马来西亚新一天，请重新填写今日奖励。' : '已到马来西亚新一周，请重新填写本周奖励。',
            ),
          ),
        );
        return;
      }
      setState(() {
        _prune();
        final id = _id(tab, index);
        final date = _completedDates[id];
        if (_done.contains(id) && date != null) {
          _history.adjust(date, _reward(tab, index), -1);
          _history.adjust(date, result, 1);
        }
        _amounts[_id(tab, index)] = result['钻石']!;
        _resources[_id(tab, index)] = result;
      });
      _save();
    }
  }

  Future<void> _reset() async {
    final tab = _tab;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('重置${tab == 0 ? '每日' : '每周'}清单？'),
        content: const Text('保留最近 7 天的已获得资源记录，清除本页勾选与实际奖励。固定奖励保留，另一页不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _clearChecklist(tab);
      });
      _save();
    }
  }

  void _toggle(int index, bool checked) {
    final id = _id(_tab, index);
    setState(() {
      _prune();
      if (checked) {
        if (_done.add(id)) {
          final date = ResourceHistory.dateKey(widget.now());
          _completedDates[id] = date;
          _history.adjust(date, _reward(_tab, index), 1);
        }
      } else if (_done.remove(id)) {
        final date = _completedDates.remove(id);
        if (date != null) _history.adjust(date, _reward(_tab, index), -1);
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(_tab);
    final completed = List.generate(
      items.length,
      (i) => i,
    ).where((i) => _done.contains(_id(_tab, i))).length;
    return Scaffold(
      // The reward dialog handles keyboard insets independently.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leadingWidth: 76,
        leading: const JournalEmblem(),
        actions: [
          IconButton(
            tooltip: '活动、更新与召唤情报',
            icon: const Icon(Icons.campaign_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const NewsHub())),
          ),
        ],
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BROWN DUST II',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 3,
                color: AppDesign.gold,
              ),
            ),
            SizedBox(height: 3),
            Text(
              '棕色尘埃 2 · 任务清单',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF2EDE2),
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppDesign.border),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF25302F),
              AppDesign.background,
              Color(0xFF18232E),
            ],
          ),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    children: [
                      if (_failed)
                        const MaterialBanner(
                          content: Text('读取失败，请重新打开应用后再修改。'),
                          actions: [SizedBox.shrink()],
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SummaryCard(
                          history: _history,
                          retainedDates: ResourceHistory.retainedDates(
                            widget.now(),
                          ),
                          dailyEarned: _earned(0),
                          weeklyEarned: _earned(1),
                        ),
                      ),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                            value: 0,
                            label: Text('每日任务'),
                            icon: Icon(Icons.wb_sunny_outlined),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text('每周任务'),
                            icon: Icon(Icons.date_range),
                          ),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (s) =>
                            setState(() => _tab = s.first),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('$completed/${items.length} 完成'),
                                ),
                                Text('${_earned(_tab)} 钻石'),
                                TextButton(
                                  onPressed: _failed ? null : _reset,
                                  child: const Text('重置清单'),
                                ),
                              ],
                            ),
                            LinearProgressIndicator(
                              value: completed / items.length,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          cacheExtent: 600,
                          key: ValueKey(_tab),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: items.length + 1,
                          itemBuilder: (context, index) {
                            if (index == items.length) {
                              return const ChecklistTips();
                            }
                            final item = items[index];
                            final id = _id(_tab, index);
                            return TaskCard(
                              id: id,
                              title: item[0] as String,
                              subtitle: item[1] as String,
                              done: _done.contains(id),
                              amount: _amount(_tab, index),
                              onChanged: _failed
                                  ? null
                                  : (checked) => _toggle(index, checked),
                              onEditAmount: _failed
                                  ? null
                                  : () => _editAmount(index),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
