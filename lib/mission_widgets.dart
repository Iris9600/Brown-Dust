import 'package:flutter/material.dart';
import 'app_design.dart';
import 'mission_data.dart';
import 'resource_history.dart';

/// Seven-day resource totals, current checklist gems and the daily breakdown.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.history,
    required this.retainedDates,
    required this.dailyEarned,
    required this.weeklyEarned,
  });
  final ResourceHistory history;
  final List<String> retainedDates;
  final int dailyEarned;
  final int weeklyEarned;

  int _total(String resource) => history.total(resource);

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    final headline = Theme.of(context).textTheme.headlineMedium;
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ADVENTURER’S JOURNAL',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: AppDesign.gold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text('资源总览 · 最近 7 天', style: bold),
                Text(
                  '${_total('钻石')} 钻石',
                  key: const Key('sevenDayGems'),
                  style: headline,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final resource in resourceNames.skip(1))
                      Chip(
                        label: Text('$resource ${_total(resource)}'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('当前清单 · 已获得钻石'),
                Text(
                  '${dailyEarned + weeklyEarned} 钻石',
                  key: const Key('totalGems'),
                  style: headline,
                ),
                Text('每日 $dailyEarned  ·  每周 $weeklyEarned'),
                const SizedBox(height: 8),
                const Text(
                  '按马来西亚时间（MYT / UTC+8）保存，只保留今天与前 6 天。每日清单于 00:00 自动重置；收益按原日期保留。每周清单于周一 00:00 自动重置；每日重置不影响每周进度。',
                ),
                const SizedBox(height: 12),
                const Text('每日收益明细', style: bold),
                for (final date in retainedDates)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '$date  ·  ${resourceNames.map((name) => "$name ${history.days[date]?[name] ?? 0}").join(" / ")}',
                    ),
                  ),
                const Text(
                  '旧版已勾选任务按升级当天导入；无日期的历史累计无法归入最近 7 天，已移除。',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One checklist entry with its checkbox and reward button.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.amount,
    required this.onChanged,
    required this.onEditAmount,
  });
  final String id;
  final String title;
  final String subtitle;
  final bool done;
  final int amount;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onEditAmount;

  @override
  Widget build(BuildContext context) => Card(
    color: done ? const Color(0xFF202F2B) : AppDesign.panel,
    shape: BeveledRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: done ? const Color(0xFF557964) : AppDesign.border,
      ),
    ),
    child: Column(
      children: [
        CheckboxListTile(
          key: ValueKey(id),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: done ? AppDesign.mint : const Color(0xFFF2EDE2),
            ),
          ),
          subtitle: Text(subtitle),
          value: done,
          onChanged: onChanged == null
              ? null
              : (checked) => onChanged!(checked!),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onEditAmount,
            icon: const Icon(
              Icons.diamond_outlined,
              size: 18,
              color: AppDesign.crystal,
            ),
            label: Text('$amount 钻石 · 填写实际奖励'),
          ),
        ),
      ],
    ),
  );
}

/// Reward and collection reminders shown below each checklist.
class ChecklistTips extends StatelessWidget {
  const ChecklistTips({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '收益与领取提醒',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          '• 在线核对：2026-10-16。清单包含日常、每周检查及开放期间可选事项；具体开放条件与周期以游戏公告为准。\n'
          '• 同一笔奖励只填写在一个条目；特别是活动战斗、魔兽追踪者、通行证与活动结算。新增事项默认 0 钻，非钻石资源不计入总额。\n'
          '• 每日任务 7 天共 420 钻 + 每周任务 200 钻 + PvP 400–2000 钻：一周 1020–2620 钻，需满足对应条件。此估算不计入已获得。\n'
          '• 赛季活动任务、商店与魔兽追踪者奖励可能随版本调整；以当期奖励页为准，按各自周期领取，勿当作固定每周收入。\n'
          '• 派遣与餐厅钻石不固定；派遣约 25 钻的估计不可当作固定收入。\n'
          '• 末日之书与傲慢之塔达到纪录后记得领取每日奖励，无需每天重复挑战。\n'
          '• 部分事项只推进每日/每周任务，完成后记得进入任务页领奖。\n'
          '• 数据保存在当前设备，仅保留 MYT 今天与前 6 天的收益。每日 00:00 自动重置并保存；关闭时下次打开补做。每周清单于周一 00:00 自动重置；每日重置不影响每周进度。',
        ),
      ],
    ),
  );
}
