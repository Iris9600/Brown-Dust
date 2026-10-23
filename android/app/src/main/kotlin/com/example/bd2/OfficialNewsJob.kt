package com.example.bd2

import android.Manifest
import android.app.*
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.app.job.JobService
import android.app.job.JobParameters
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.io.ByteArrayOutputStream

/** Native background polling works without an always-running Flutter isolate. */
object NewsNotifier {
    private const val JOB = 18401
    private const val NOW_JOB = 18402
    private const val NEWS_CHANNEL = "bd2_official_announcements"
    private const val REMINDER_CHANNEL = "bd2_announcement_reminders"
    private fun prefs(context: Context) = context.getSharedPreferences("bd2_official_news", Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    fun allowed(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        (Build.VERSION.SDK_INT < 24 || manager(context).areNotificationsEnabled())
    private fun channels(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            manager(context).createNotificationChannel(NotificationChannel(NEWS_CHANNEL, "官方公告", NotificationManager.IMPORTANCE_DEFAULT))
            manager(context).createNotificationChannel(NotificationChannel(REMINDER_CHANNEL, "活动与卡池提醒", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }
    fun officialUrl(value: String): Boolean = try {
        val uri = Uri.parse(value)
        uri.scheme == "https" && uri.host == "www.browndust2.com" && uri.path?.contains("/news") == true
    } catch (_: Exception) { false }
    private fun array(context: Context, key: String): JSONArray = JSONArray(prefs(context).getString(key, "[]"))
    @Synchronized
    fun status(context: Context): Map<String, Any> {
        val p = prefs(context)
        val reminders = array(context, "reminders")
        val future = (0 until reminders.length()).map { reminders.getJSONObject(it) }
            .filter { it.optLong("at") > System.currentTimeMillis() - 24 * 60 * 60 * 1000L }.sortedBy { it.optLong("at") }
        return mapOf("enabled" to p.getBoolean("enabled", false), "permission" to allowed(context),
            "events" to p.getBoolean("events", true), "updates" to p.getBoolean("updates", true),
            "banners" to p.getBoolean("banners", true), "lastCheck" to p.getLong("lastCheck", 0),
            "error" to (p.getString("error", "") ?: ""),
            "reminders" to future.map { jsonMap(it) },
            "alerts" to (0 until array(context, "alerts").length()).map { jsonMap(array(context, "alerts").getJSONObject(it)) })
    }
    private fun jsonMap(value: JSONObject): Map<String, Any> = value.keys().asSequence().associateWith { value.get(it) }
    @Synchronized
    fun setEnabled(context: Context, enabled: Boolean) {
        if (enabled && !allowed(context)) throw SecurityException("Notification permission required")
        if (enabled && !prefs(context).getBoolean("enabled", false)) {
            prefs(context).edit().putBoolean("baseline_cn", false).putBoolean("baseline_en", false).apply()
        }
        prefs(context).edit().putBoolean("enabled", enabled).apply()
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (enabled) {
            schedulePolling(context)
            val immediate = JobInfo.Builder(NOW_JOB, ComponentName(context, OfficialNewsJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setMinimumLatency(1000).build()
            if (scheduler.schedule(immediate) != JobScheduler.RESULT_SUCCESS) {
                prefs(context).edit().putString("error", "后台检查排队失败，请重新开启通知。").apply()
            }
        } else { scheduler.cancel(JOB); scheduler.cancel(NOW_JOB) }
    }
    fun schedulePolling(context: Context) {
        if (!prefs(context).getBoolean("enabled", false)) return
        val info = JobInfo.Builder(JOB, ComponentName(context, OfficialNewsJob::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPeriodic(60 * 60 * 1000L).setPersisted(true).build()
        if (context.getSystemService(JobScheduler::class.java).schedule(info) != JobScheduler.RESULT_SUCCESS) {
            throw IllegalStateException("Cannot schedule background checks")
        }
    }
    @Synchronized
    fun category(context: Context, name: String, enabled: Boolean) {
        require(name in listOf("events", "updates", "banners"))
        prefs(context).edit().putBoolean(name, enabled).apply()
    }
    private fun categories(title: String, tag: String, body: String): JSONArray {
        val heading = "$title $tag".lowercase()
        val all = "$heading $body".lowercase()
        val result = mutableListOf<String>()
        val officialEvent = tag == "event"
        val officialUpdate = tag in listOf("notice", "inspection", "maintenance", "update", "dev_note", "shop", "package_deal", "issue", "goods")
        if (officialEvent || (!officialUpdate && Regex("event|活动|活動").containsMatchIn(heading))) result.add("events")
        if (Regex("pick[ -]?up|summon|recruit|抽卡|卡池|招募|召唤|召喚").containsMatchIn(all)) result.add("banners")
        if (officialUpdate || (!officialEvent && (Regex("update|maintenance|patch|notice|dev.?note|更新|维护|維護|公告|开发|開發").containsMatchIn(heading) || result.isEmpty()))) result.add("updates")
        if (!officialEvent && !officialUpdate && Regex("event update|event period|活动时间|活動期間|活动更新|活動更新").containsMatchIn(all) && !result.contains("events")) result.add("events")
        return JSONArray(result)
    }
    /** No notifications on the first successful sync for each language. */
    @Synchronized
    fun observe(context: Context, records: JSONArray, language: String) {
        if (!prefs(context).getBoolean("enabled", false) || records.length() == 0) return
        val lang = if (language == "en" || language == "en-us") "en" else "cn"
        val p = prefs(context)
        val seen = JSONObject(p.getString("seen_$lang", "{}") ?: "{}")
        val baseline = p.getBoolean("baseline_$lang", false) && p.getBoolean("api_v2_$lang", false)
        val changed = mutableListOf<JSONObject>()
        for (i in 0 until records.length()) {
            val item = records.getJSONObject(i)
            val id = item.optString("id")
            if (id.isEmpty() || !officialUrl(item.optString("url"))) continue
            val revision = item.optString("revision", item.optString("title"))
            val categories = item.optJSONArray("categories") ?: JSONArray()
            val interested = (0 until categories.length()).any { p.getBoolean(categories.optString(it), true) }
            if (baseline && (!seen.has(id) || seen.optString(id) != revision) && interested) changed.add(item)
            seen.put(id, revision)
        }
        if (Thread.currentThread().isInterrupted || !p.getBoolean("enabled", false)) return
        if (allowed(context)) {
            if (changed.size > 5) {
                post(context, "digest", "有 ${changed.size} 条官方公告更新", "打开官网查看最新活动、更新与召唤信息。", "https://www.browndust2.com/en-us/news", false)
            } else changed.forEach { item -> post(context, item.optString("id"), item.optString("title"), "Brown Dust 2 官方公告已发布或更新。", item.optString("url"), false) }
        }
        // Bound storage while protecting every item in the current feed.
        val keys = seen.keys().asSequence().toList()
        if (keys.size > 2000) {
            val currentIds = (0 until records.length()).map { records.getJSONObject(it).optString("id") }.toSet()
            keys.filterNot { it in currentIds }.take(keys.size - 2000).forEach { seen.remove(it) }
        }
        p.edit().putString("seen_$lang", seen.toString()).putBoolean("baseline_$lang", true)
            .putBoolean("api_v2_$lang", true)
            .putLong("lastCheck", System.currentTimeMillis()).putString("error", "").apply()
    }
    fun fetchAndObserve(context: Context) {
        var failure: Exception? = null
        for ((code, locale) in listOf("cn" to "zh-cn", "en" to "en-us")) {
            try {
                val connection = URL("https://webapi.browndust2.com/api/notices?locale=$locale&page=0&limit=100").openConnection() as HttpURLConnection
                connection.connectTimeout = 20000
                connection.readTimeout = 20000
                connection.instanceFollowRedirects = false
                val body = try {
                    check(connection.responseCode == 200) { "Official feed HTTP ${connection.responseCode}" }
                    connection.inputStream.use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            if (Thread.currentThread().isInterrupted) throw InterruptedException()
                            val count = input.read(buffer)
                            if (count < 0) break
                            check(output.size() + count <= 12 * 1024 * 1024) { "Feed too large" }
                            output.write(buffer, 0, count)
                        }
                        val bytes = output.toByteArray()
                        check(bytes.size <= 12 * 1024 * 1024) { "Feed too large" }
                        String(bytes, Charsets.UTF_8)
                    }
                } finally { connection.disconnect() }
                val rows = JSONObject(body).getJSONArray("items")
                val sorted = (0 until rows.length()).mapNotNull { index ->
                    val row = rows.optJSONObject(index) ?: return@mapNotNull null
                    val fields = row.optJSONObject("attributes") ?: row
                    if (row.optString("id").isEmpty() || fields.optString("subject", fields.optString("title")).isEmpty()) null else row
                }.sortedByDescending { (it.optJSONObject("attributes") ?: it).optString("publishedAt") }.take(100)
                check(sorted.isNotEmpty()) { "Official feed format changed" }
                val records = JSONArray()
                for (row in sorted) {
                    val fields = row.optJSONObject("attributes") ?: row
                    val id = row.get("id").toString()
                    val title = fields.optString("subject", fields.optString("title"))
                    val content = fields.optString("contentPreview")
                    // Match Dart's timestamp revisions when provided; use title when dates are absent.
                    val revision = (if (fields.isNull("updatedAt")) "" else fields.optString("updatedAt")).ifEmpty { (if (fields.isNull("publishedAt")) "" else fields.optString("publishedAt")).ifEmpty { title } }
                    records.put(JSONObject().put("id", id).put("title", title)
                        .put("url", "https://www.browndust2.com/$locale/news/view?id=${Uri.encode(id)}")
                        .put("revision", normalizeRevision(revision))
                        .put("categories", categories(title, fields.optString("category"), content)))
                }
                if (Thread.currentThread().isInterrupted) return
                observe(context, records, code)
                return
            } catch (error: Exception) {
                failure = error
                android.util.Log.w("OfficialNewsJob", "Official feed $locale failed", error)
            }
        }
        if (!Thread.currentThread().isInterrupted) {
            prefs(context).edit().putString("error", "无法同步官方公告，将在有网络时重试。${failure?.javaClass?.simpleName ?: ""}").apply()
            throw IllegalStateException("Official feeds unavailable", failure)
        }
    }
    private fun normalizeRevision(value: String): String {
        val match = Regex("^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.(\\d+))?(Z|[+-]\\d{2}:?\\d{2})$").matchEntire(value) ?: return value
        val fraction = match.groupValues[2].padEnd(3, '0').take(3)
        val zone = match.groupValues[3].let { if (it == "Z") "+00:00" else if (it.length == 5) it.take(3) + ":" + it.takeLast(2) else it }
        return try {
            val format = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", java.util.Locale.US)
            format.isLenient = false
            format.parse("${match.groupValues[1]}.$fraction$zone")?.time?.toString() ?: value
        } catch (_: Exception) { value }
    }
    @Synchronized
    fun post(context: Context, id: String, title: String, body: String, url: String, reminder: Boolean) {
        require(officialUrl(url))
        if (!allowed(context)) return
        channels(context)
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, if (reminder) REMINDER_CHANNEL else NEWS_CHANNEL) else Notification.Builder(context)
        builder.setSmallIcon(R.drawable.ic_stat_quest).setContentTitle(title).setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(pending).setAutoCancel(true)
        manager(context).notify((if (reminder) "reminder:" else "news:") + id, 0, builder.build())
        val alerts = array(context, "alerts")
        val next = JSONArray().put(JSONObject().put("title", title).put("url", url).put("at", System.currentTimeMillis()))
        for (i in 0 until minOf(alerts.length(), 49)) next.put(alerts.getJSONObject(i))
        prefs(context).edit().putString("alerts", next.toString()).apply()
    }
    fun test(context: Context) = post(context, "test", "冒险情报通知已就绪", "官方公告与已设置的提醒将显示在这里。", "https://www.browndust2.com/en-us/news", true)
    private fun reminderIntent(context: Context, id: String): PendingIntent {
        val intent = Intent(context, NewsReminderReceiver::class.java).setAction("com.example.bd2.REMIND")
            .setData(Uri.parse("bd2://reminder/${Uri.encode(id)}")).putExtra("id", id)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    @Synchronized
    fun scheduleReminder(context: Context, item: JSONObject) {
        require(allowed(context)) { "Notification permission required" }
        val at = item.getLong("at")
        require(at > System.currentTimeMillis() && at <= System.currentTimeMillis() + 366L * 24 * 60 * 60 * 1000)
        require(item.getString("id").isNotBlank() && item.getString("title").length in 1..2000 && officialUrl(item.getString("url")))
        val previous = array(context, "reminders")
        val next = JSONArray()
        for (i in 0 until previous.length()) {
            val old = previous.getJSONObject(i)
            if (old.optString("id") != item.getString("id") && old.optLong("at") > System.currentTimeMillis() - 24 * 60 * 60 * 1000L) next.put(old)
        }
        require(next.length() < 100) { "Too many reminders" }
        next.put(item)
        check(prefs(context).edit().putString("reminders", next.toString()).commit()) { "Cannot save reminder" }
        try {
            val alarm = context.getSystemService(AlarmManager::class.java)
            val pending = reminderIntent(context, item.getString("id"))
            if (Build.VERSION.SDK_INT >= 23) alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            else alarm.set(AlarmManager.RTC_WAKEUP, at, pending)
        } catch (error: Exception) {
            prefs(context).edit().putString("reminders", previous.toString()).commit()
            throw error
        }
    }
    @Synchronized
    fun cancelReminder(context: Context, id: String) {
        context.getSystemService(AlarmManager::class.java).cancel(reminderIntent(context, id))
        val previous = array(context, "reminders")
        val next = JSONArray()
        for (i in 0 until previous.length()) if (previous.getJSONObject(i).optString("id") != id) next.put(previous.getJSONObject(i))
        check(prefs(context).edit().putString("reminders", next.toString()).commit())
    }
    @Synchronized
    fun deliver(context: Context, id: String) {
        val items = array(context, "reminders")
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            if (item.optString("id") == id) {
                if (System.currentTimeMillis() - item.optLong("at") < 24 * 60 * 60 * 1000L) {
                    post(context, "scheduled:$id", item.optString("title"), "你设置的活动或卡池提醒时间已到。请查看官方公告。", item.optString("url"), true)
                }
                cancelReminder(context, id)
                return
            }
        }
    }
    @Synchronized
    fun restore(context: Context) {
        schedulePolling(context)
        val items = array(context, "reminders")
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            if (allowed(context)) { if (item.optLong("at") > System.currentTimeMillis()) scheduleReminder(context, item) else deliver(context, item.optString("id")) }
        }
    }
}

class OfficialNewsJob : JobService() {
    private val workers = mutableMapOf<Int, Thread>()
    override fun onStartJob(params: JobParameters): Boolean {
        val worker = Thread({
            var retry = false
            try { NewsNotifier.fetchAndObserve(this) } catch (_: Exception) { retry = true }
            val finishedWorker = Thread.currentThread()
            Handler(Looper.getMainLooper()).post {
                if (workers[params.jobId] === finishedWorker) {
                    workers.remove(params.jobId)
                    jobFinished(params, retry)
                }
            }
        }, "bd2-official-news")
        workers[params.jobId] = worker
        worker.start()
        return true
    }
    override fun onDestroy() {
        workers.values.forEach { it.interrupt() }
        workers.clear()
        super.onDestroy()
    }
    override fun onStopJob(params: JobParameters): Boolean {
        workers.remove(params.jobId)?.interrupt()
        return true
    }
}
class NewsReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) NewsNotifier.restore(context)
            else if (intent.action == "com.example.bd2.REMIND") NewsNotifier.deliver(context, intent.getStringExtra("id") ?: return)
        } catch (error: Exception) {
            context.getSharedPreferences("bd2_official_news", Context.MODE_PRIVATE).edit()
                .putString("error", "提醒恢复失败，请重新打开应用。${error.javaClass.simpleName}").apply()
        }
    }
}
