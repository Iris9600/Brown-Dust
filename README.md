# 棕色尘埃 2 任务清单 (Brown Dust 2 Mission Checklist)

A Flutter app for Brown Dust 2 players. It tracks daily and weekly routines and the rewards you earn, and it collects official news, summon banners and reminders. The UI is in Simplified Chinese.

## Quick start

```sh
flutter run        # launch on a device or emulator
flutter analyze    # static analysis
flutter test       # unit and widget tests
```

## Project layout

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | App entry, `MissionPage` state, persistence and MYT resets |
| `lib/mission_data.dart` | Daily/weekly checklist definitions and resource names |
| `lib/mission_widgets.dart` | Summary card, task card and tips footer |
| `lib/amount_dialog.dart` | "Actual rewards" entry dialog |
| `lib/resource_history.dart` | Seven-day MYT earnings history |
| `lib/mission_schedule.dart` | Weekly (Monday MYT) period keys |
| `lib/app_design.dart` | Shared colors, theme and component styles |
| `lib/announcements/` | News hub, official API client, summon banners, YouTube uploads, notifications |
| `android/app/src/main/kotlin/` | Background news job and reminder receiver |
| `tool/` | Icon generation and web build scripts |

## Checklists and rewards

- **16 daily** and **12 weekly** items, based on the supplied list and an online review on 2026-10-16. Weekly entries include seasonal progress checks; they do not imply weekly reward resets.
- Checking an item adds its gem reward; unchecking subtracts it. Fixed defaults are **60** (daily missions) and **200** (weekly missions). Variable rewards start at 0: use each item's reward button to enter the actual amounts.
- Tracked resources: gems, draw tickets, gold, ancient crystals, attribute stones, devil coins, decoration coins and Oren coins. They are counted separately; tickets and resources are never converted into gems.
- Earnings are not an in-game inventory balance and do not subtract spending. Event reward guidance is kept separate so per-event rewards are not counted as weekly income.
- This is a recurring-activity checklist, not a full catalog of one-time clears, achievements or temporary events.
- Item positions are stable, so saved checks and amounts stay attached to their original tasks across updates.

## Time zone, resets and retention

All dates use **Malaysia time (MYT, UTC+8)**, regardless of the device's time zone.

- **Daily reset:** at 00:00 MYT, clears daily checks and entered amounts and restores the fixed defaults.
- **Weekly reset:** on Monday at 00:00 MYT, done the same way for the weekly list. Daily resets never touch weekly progress.
- **Catch-up:** a timer handles the reset while the app is open. Opening or resuming the app catches up on any missed resets.
- **Retention:** only today and the previous six calendar days of earnings are kept. Older and future-dated records are removed on open, resume, save and every minute while running.
- **Manual reset** affects only the selected list. All resets leave dated earnings in place. Editing or unchecking an item adjusts its original completion date.
- **Stale dialogs:** a reward dialog opened before a reset must be reopened before it can save.
- **Legacy saves:** undated checked tasks are imported once as today's records. Undated lifetime totals are removed because their age can't be verified.

Data is stored locally with `shared_preferences` under the `checklist_v1` key.

## News, updates and summon banners

The megaphone button opens **Events**, **Updates**, **Summon Banners** and **Notifications**.

- **Source:** the official API `https://webapi.browndust2.com/api/notices` (`locale=zh-cn`, falling back to `en-us`), with full article HTML from `/api/notices/{id}`. The old `newsData_cn.json` export stopped in May 2026 and is no longer used.
- **Categories:** `event` → Events, while `notice` and `inspection` (maintenance) → Updates. Pickup notices are also parsed for summon banners.
- **Retention:** posts older than two calendar months are deleted from memory and from the cache before refresh, on open, and every minute while active.
- **Summon banner cards:** each card shows one unit or costume, with its official picture, name and labelled summon period.
  - Only explicit pickup sections or standalone pickup posts are used. Patch and event articles never become cards.
  - Dates are never borrowed from another unit or guessed from images. A poster with no text schedule shows an "unverified schedule" badge.
  - Times with an explicit timezone are converted to MYT. Date-only and maintenance boundaries are shown verbatim.
  - Banners with a verified end time are hidden once they end. Duplicates keep the newest official source.
  - Tap a poster to zoom it full-screen.
- **YouTube uploads:** costume, skin and PV videos come from [@browndust2_en](https://www.youtube.com/@browndust2_en/videos), use the same two-month window, and show their verified upload date. Upload dates are never treated as summon dates.
- Detail pages link to the [official news site](https://www.browndust2.com/en-us/news). The Summon page links to the [Chinese news index](https://www.browndust2.com/zh-cn/news?page=1&type=all).

## Android notifications

Implemented natively (Kotlin) using `JobScheduler`, `NotificationManager` and inexact `AlarmManager` alarms over the `bd2/announcements` method channel. No Firebase or server is needed.

- Turn alerts on in the Notifications page and grant notification permission. You can choose event, update and banner alerts.
- **While the hub is open:** it refreshes on open, on resume and every 15 minutes.
- **In the background:** a persisted job checks roughly every hour.
- **First sync:** the first sync for each language only sets a baseline; old posts don't trigger alerts.
- **Grouping:** new or revised posts are deduplicated. More than five changes are combined into one summary alert.
- **Reminders:** use **Set Reminder** on any post or banner to pick a future MYT time.
  - Each post or banner keeps one reminder; setting a new one replaces it.
  - Reminders survive reboot and app updates, and recently missed ones are delivered when restored.
  - Turning automatic alerts off does not cancel reminders.
- The page lists upcoming reminders and the 50 most recent alerts. Tapping a notification opens the official post.
- These are periodic local alerts, not instant push. Android may delay them in battery-saver or offline states, and a force-stopped app can't run until it is reopened.
- The small notification icon is `android/app/src/main/res/drawable/ic_stat_quest.xml`.

See [JobInfo.Builder#setPeriodic](https://developer.android.com/reference/android/app/job/JobInfo.Builder#setPeriodic(long)) and [alarm delivery](https://developer.android.com/develop/background-work/services/alarms).

### Manual device check

Reboot behaviour and scheduled delivery still need checking on a physical device:

1. Build and install the Android app.
2. Open the megaphone, refresh while online and turn on notifications.
3. Send a test notification and schedule a reminder.
4. Close the app and confirm the reminder arrives, including after a reboot.

A web build does not include Android background notifications.

## Design and icons

- The theme is inspired by Brown Dust 2's fantasy journal look: charcoal panels, beveled gold borders, crystal-blue reward icons and sage-green completed states. It uses native Flutter widgets only, with no external artwork or font downloads.
- The launcher icon source is `assets/branding/app-icon.png`. To regenerate the Android, iOS and web sizes, run:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool/update_app_icons.ps1
  ```

  Then rebuild and reinstall the app.

## Testing

The tests cover MYT resets and retention, legacy migration, reward validation, feed parsing and classification, language fallback, offline caching, summon extraction, YouTube parsing, small-phone layouts, permission rejection and the Android method-channel contract. Live feeds use isolated fixtures, so no historical banners ship as current data.

## Sources

- [Daily routine guide (Feb 2026)](https://volx.jp/browndust2-daily-mission/): Fantasia Square, equipment and routine details
- [Daily routines](https://dotgg.gg/brown-dust-2/beginners-guide-daily-routines-guide/): tower collection and routine context
- [Guild update](https://dotgg.gg/brown-dust-2/july-3rd-utc-routine-maintenance-and-update/): daily guild attendance rewards
- [Fiend Hunter calculator and version notes](https://botan14xd.github.io/BD2-Overview/misc/fh-calc/): current weekly versus archived daily formats
- [Tower of Salvation guide](https://dotgg.gg/brown-dust-2/tower-of-salvation-quick-start-guide/): seasonal progression and rewards

Always check current in-game announcements for availability and rewards.
