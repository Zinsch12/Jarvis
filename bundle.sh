#!/bin/bash
# JARVIS Android v0.1 - membuat seluruh proyek (tanpa unduhan, tanpa model).
set -e
P=app/src/main/java/com/zinsch/jarvis
mkdir -p $P

cat > settings.gradle.kts <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "JARVIS"
include(":app")
EOF
cat > build.gradle.kts <<'EOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
EOF
cat > gradle.properties <<'EOF'
android.useAndroidX=true
org.gradle.jvmargs=-Xmx3g
kotlin.code.style=official
EOF
mkdir -p app
cat > app/build.gradle.kts <<'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.zinsch.jarvis"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.zinsch.jarvis"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}
EOF
mkdir -p app/src/main
cat > app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.SET_ALARM" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <queries>
        <intent><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /></intent>
        <intent><action android:name="android.speech.RecognitionService" /></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>
    </queries>
    <application android:label="JARVIS" android:allowBackup="false"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > $P/Prefs.kt <<'EOF'
package com.zinsch.jarvis

import android.content.Context

/** Pengaturan pengguna (disimpan lokal). */
class Prefs(ctx: Context) {
    private val p = ctx.getSharedPreferences("jarvis", Context.MODE_PRIVATE)
    private fun b(k: String, d: Boolean) = p.getBoolean(k, d)
    private fun setB(k: String, v: Boolean) { p.edit().putBoolean(k, v).apply() }

    var name: String
        get() = p.getString("name", "Bos") ?: "Bos"
        set(v) { p.edit().putString("name", v).apply() }
    var formal: Boolean
        get() = b("formal", false)
        set(v) { setB("formal", v) }
    var speak: Boolean
        get() = b("speak", true)
        set(v) { setB("speak", v) }
    var privateMode: Boolean
        get() = b("private", false)
        set(v) { setB("private", v) }
    var english: Boolean
        get() = b("english", false)
        set(v) { setB("english", v) }
    var offline: Boolean
        get() = b("offline", false)
        set(v) { setB("offline", v) }
    var rate: Float
        get() = p.getFloat("rate", 1f)
        set(v) { p.edit().putFloat("rate", v).apply() }
    var pitch: Float
        get() = p.getFloat("pitch", 1f)
        set(v) { p.edit().putFloat("pitch", v).apply() }
}
EOF

cat > $P/MemoryDb.kt <<'EOF'
package com.zinsch.jarvis

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** Riwayat percakapan dan memori jangka panjang (SQLite lokal). */
class MemoryDb(ctx: Context) : SQLiteOpenHelper(ctx, "jarvis.db", null, 1) {
    class Mem(val id: Long, val cat: String, val text: String)

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE messages(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, role TEXT, text TEXT)")
        db.execSQL("CREATE TABLE memories(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, cat TEXT, text TEXT)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    fun addMessage(role: String, text: String) {
        val v = ContentValues()
        v.put("ts", System.currentTimeMillis()); v.put("role", role); v.put("text", text)
        writableDatabase.insert("messages", null, v)
    }
    fun recent(limit: Int): List<Pair<String, String>> {
        val out = ArrayList<Pair<String, String>>()
        readableDatabase.rawQuery("SELECT role,text FROM messages ORDER BY id DESC LIMIT ?", arrayOf(limit.toString())).use { c ->
            while (c.moveToNext()) out.add(Pair(c.getString(0), c.getString(1)))
        }
        out.reverse()
        return out
    }
    fun clearMessages() { writableDatabase.delete("messages", null, null) }

    fun addMemory(cat: String, text: String) {
        val v = ContentValues()
        v.put("ts", System.currentTimeMillis()); v.put("cat", cat); v.put("text", text)
        writableDatabase.insert("memories", null, v)
    }
    fun memories(): List<Mem> {
        val out = ArrayList<Mem>()
        readableDatabase.rawQuery("SELECT id,cat,text FROM memories ORDER BY id DESC", null).use { c ->
            while (c.moveToNext()) out.add(Mem(c.getLong(0), c.getString(1), c.getString(2)))
        }
        return out
    }
    fun search(q: String): List<Mem> {
        val out = ArrayList<Mem>()
        readableDatabase.rawQuery("SELECT id,cat,text FROM memories WHERE text LIKE ? OR cat LIKE ? ORDER BY id DESC",
            arrayOf("%$q%", "%$q%")).use { c ->
            while (c.moveToNext()) out.add(Mem(c.getLong(0), c.getString(1), c.getString(2)))
        }
        return out
    }
    fun deleteMemory(id: Long) { writableDatabase.delete("memories", "id=?", arrayOf(id.toString())) }
    fun deleteMatching(q: String): Int = writableDatabase.delete("memories", "text LIKE ?", arrayOf("%$q%"))
    fun clearMemories() { writableDatabase.delete("memories", null, null) }
}
EOF

cat > $P/Calc.kt <<'EOF'
package com.zinsch.jarvis

/** Kalkulator kecil dan aman: + - * / dan tanda kurung. */
object Calc {
    fun eval(s: String): Double? = try {
        Parser(s.replace(" ", "").replace(",", ".").replace("×", "*")).run()
    } catch (e: Exception) { null }

    fun fmt(d: Double): String =
        if (d == Math.floor(d) && Math.abs(d) < 1e15) d.toLong().toString()
        else "%.6f".format(d).trimEnd('0').trimEnd('.')

    private class Parser(val s: String) {
        var i = 0
        fun run(): Double {
            val v = expr()
            if (i != s.length) throw IllegalArgumentException("sisa")
            return v
        }
        fun expr(): Double {
            var v = term()
            while (i < s.length && (s[i] == '+' || s[i] == '-')) {
                val op = s[i++]; val t = term()
                v = if (op == '+') v + t else v - t
            }
            return v
        }
        fun term(): Double {
            var v = factor()
            while (i < s.length && (s[i] == '*' || s[i] == '/' || s[i] == 'x')) {
                val op = s[i++]; val f = factor()
                v = if (op == '/') v / f else v * f
            }
            return v
        }
        fun factor(): Double {
            if (i < s.length && s[i] == '-') { i++; return -factor() }
            if (i < s.length && s[i] == '(') {
                i++
                val v = expr()
                if (i >= s.length || s[i] != ')') throw IllegalArgumentException("kurung")
                i++
                return v
            }
            val st = i
            while (i < s.length && (s[i].isDigit() || s[i] == '.')) i++
            if (st == i) throw IllegalArgumentException("angka")
            return s.substring(st, i).toDouble()
        }
    }
}
EOF

cat > $P/Brain.kt <<'EOF'
package com.zinsch.jarvis

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.Settings
import android.view.KeyEvent
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Otak JARVIS v0.1: pemahaman perintah berbasis aturan (offline, tanpa model AI).
 * Antarmuka respond() sengaja sederhana supaya nanti bisa diganti/ditambah model bahasa lokal.
 */
class Brain(private val ctx: Activity, private val db: MemoryDb, private val prefs: Prefs) {
    private var pending: (() -> String)? = null
    private val idLoc = Locale("id", "ID")
    private fun t(formal: String, casual: String): String = if (prefs.formal) formal else casual
    private val who: String get() = prefs.name

    private val settingsMap: List<Pair<List<String>, String>> = listOf(
        listOf("wifi", "wi-fi") to Settings.ACTION_WIFI_SETTINGS,
        listOf("bluetooth") to Settings.ACTION_BLUETOOTH_SETTINGS,
        listOf("layar", "tampilan", "display") to Settings.ACTION_DISPLAY_SETTINGS,
        listOf("suara", "sound") to Settings.ACTION_SOUND_SETTINGS,
        listOf("baterai", "battery") to Settings.ACTION_BATTERY_SAVER_SETTINGS,
        listOf("lokasi", "location") to Settings.ACTION_LOCATION_SOURCE_SETTINGS,
        listOf("aplikasi", "apps") to Settings.ACTION_APPLICATION_SETTINGS,
        listOf("aksesibilitas", "accessibility") to Settings.ACTION_ACCESSIBILITY_SETTINGS,
        listOf("bahasa", "language") to Settings.ACTION_LOCALE_SETTINGS,
        listOf("penyimpanan", "storage") to Settings.ACTION_INTERNAL_STORAGE_SETTINGS,
        listOf("jaringan", "network", "data") to Settings.ACTION_WIRELESS_SETTINGS,
        listOf("tanggal", "waktu", "date") to Settings.ACTION_DATE_SETTINGS
    )

    fun greeting(): String {
        val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        val part = when { h < 11 -> "pagi"; h < 15 -> "siang"; h < 18 -> "sore"; else -> "malam" }
        return t("Selamat $part, $who. Ada yang bisa saya bantu?", "Halo $who, selamat $part! Mau ngapain?")
    }

    fun respond(raw: String): String {
        val text = raw.trim()
        val q = text.lowercase(idLoc).replace(Regex("[?!.,]+$"), "").trim()
        if (q.isEmpty()) return t("Silakan sampaikan perintah Anda.", "Ngomong dulu dong.")
        val p = pending
        if (p != null) {
            pending = null
            return if (q in setOf("ya", "iya", "yes", "y", "oke", "ok", "lanjut", "boleh")) p()
            else t("Baik, dibatalkan.", "Oke, batal.")
        }
        return try { route(text, q) } catch (e: Exception) {
            t("Maaf, terjadi kesalahan: ${e.message}", "Waduh, error: ${e.message}")
        }
    }

    private fun after(q: String, vararg p: String): String? {
        for (x in p) if (q.startsWith(x)) return q.substring(x.length).trim()
        return null
    }

    private fun go(i: Intent): Boolean = try { ctx.startActivity(i); true } catch (e: Exception) { false }

    private fun route(text: String, q: String): String {
        fun has(vararg k: String): Boolean = k.any { q.contains(it) }

        // ---- bantuan, sapaan, identitas
        if (q == "bantuan" || q == "help" || q == "menu" || has("kamu bisa apa", "bisa apa saja", "what can you do")) return helpText()
        if (Regex("^(halo|hai|hi|hello|hey|selamat (pagi|siang|sore|malam))\\b").containsMatchIn(q)) return greeting()
        if (has("terima kasih", "makasih", "thanks", "thank you")) return t("Sama-sama, $who.", "Sip, sama-sama!")
        if (has("siapa kamu", "who are you", "siapa namamu"))
            return t("Saya JARVIS, asisten pribadi di ponsel Anda. Saat ini saya bekerja offline dengan perintah berbasis aturan, belum memakai model AI.",
                "Aku JARVIS, asistenmu. Sekarang masih mode aturan (offline), belum pakai model AI.")

        // ---- gaya dan preferensi
        if (has("gaya formal", "bicara formal", "be formal")) { prefs.formal = true; return "Baik. Saya akan berbicara secara formal." }
        if (has("gaya santai", "bicara santai", "be casual")) { prefs.formal = false; return "Oke, santai aja ya." }
        Regex("^(panggil aku|panggil saya|call me) (.+)$").find(q)?.let { m ->
            prefs.name = m.groupValues[2].trim().replaceFirstChar { c -> c.uppercase() }
            return t("Baik, saya akan memanggil Anda ${prefs.name}.", "Oke, kupanggil ${prefs.name}.")
        }
        if (has("aktifkan mode privat", "mode privat nyala", "private mode on")) {
            prefs.privateMode = true
            return t("Mode privat aktif. Percakapan dan memori tidak disimpan.", "Mode privat nyala, nggak ada yang disimpan.")
        }
        if (has("matikan mode privat", "mode privat mati", "private mode off")) {
            prefs.privateMode = false
            return t("Mode privat dimatikan.", "Mode privat mati.")
        }
        if (has("matikan suara jarvis", "jangan bicara", "voice off")) { prefs.speak = false; return "Suara dimatikan." }
        if (has("nyalakan suara jarvis", "voice on")) { prefs.speak = true; return "Suara dinyalakan." }

        // ---- memori
        after(q, "apa yang kamu ingat tentang ", "cari memori ")?.let { k ->
            val ms = db.search(k)
            return if (ms.isEmpty()) t("Tidak ada memori tentang \"$k\".", "Nggak ada soal \"$k\".")
            else ms.take(10).joinToString("\n") { "• [${it.cat}] ${it.text}" }
        }
        if (has("hapus semua memori", "lupakan semuanya", "clear memory")) {
            pending = { db.clearMemories(); t("Seluruh memori telah dihapus.", "Semua memori udah dihapus.") }
            return t("Anda yakin ingin menghapus seluruh memori? Katakan \"ya\" untuk melanjutkan.", "Yakin hapus semua memori? Bilang \"ya\" kalau iya.")
        }
        if (has("apa yang kamu ingat", "daftar memori", "lihat memori", "what do you remember")) {
            val ms = db.memories()
            if (ms.isEmpty()) return t("Belum ada memori tersimpan.", "Belum ada yang kuingat.")
            return t("Yang saya ingat:\n", "Yang kuingat:\n") + ms.take(15).joinToString("\n") { "• [${it.cat}] ${it.text}" }
        }
        after(q, "lupakan ", "hapus memori ", "forget ")?.let { k ->
            if (k.isNotEmpty()) {
                val n = db.deleteMatching(k)
                return if (n > 0) t("$n memori dihapus.", "$n memori dilupakan.") else t("Tidak ada memori yang cocok.", "Nggak ada yang cocok.")
            }
        }
        val rem = Regex("^(ingat bahwa|ingatlah|ingat|catatan|catat|remember that|remember)\\s+(.+)$", RegexOption.IGNORE_CASE).find(text.trim())
        if (rem != null) {
            if (prefs.privateMode) return t("Mode privat aktif, jadi tidak saya simpan.", "Lagi mode privat, nggak kusimpan.")
            val body = rem.groupValues[2].trim().trimEnd('.', '!')
            val cat = when {
                rem.groupValues[1].lowercase().startsWith("catat") -> "catatan"
                Regex("suka|favorit|benci|prefer").containsMatchIn(body.lowercase()) -> "preferensi"
                else -> "umum"
            }
            db.addMemory(cat, body)
            return t("Tercatat: \"$body\".", "Oke, kuingat: \"$body\".")
        }

        // ---- pengaturan Android
        val setWord = after(q, "buka pengaturan ", "buka setelan ", "open settings ")
        if (setWord != null || q == "buka pengaturan" || q == "buka setelan" || q == "open settings") {
            val w = setWord ?: ""
            val action = settingsMap.firstOrNull { (keys, _) -> keys.any { w.contains(it) } }?.second ?: Settings.ACTION_SETTINGS
            return if (go(Intent(action))) t("Membuka pengaturan.", "Buka pengaturan.") else t("Gagal membuka pengaturan itu.", "Nggak bisa buka itu.")
        }

        // ---- timer, alarm, pengingat, agenda
        if (has("timer", "hitung mundur", "countdown")) {
            val s = durationSec(q) ?: return t("Berapa lama timernya?", "Timer berapa lama?")
            val i = Intent(AlarmClock.ACTION_SET_TIMER).putExtra(AlarmClock.EXTRA_LENGTH, s).putExtra(AlarmClock.EXTRA_MESSAGE, "JARVIS")
            return if (go(i)) "Timer ${s / 60} menit ${s % 60} detik disiapkan." else "Gagal membuka aplikasi jam."
        }
        if (has("alarm", "bangunkan")) {
            val c = clock(q) ?: return t("Pukul berapa alarmnya?", "Alarm jam berapa?")
            val i = Intent(AlarmClock.ACTION_SET_ALARM).putExtra(AlarmClock.EXTRA_HOUR, c.first)
                .putExtra(AlarmClock.EXTRA_MINUTES, c.second).putExtra(AlarmClock.EXTRA_MESSAGE, "JARVIS")
            return if (go(i)) "Alarm ${"%02d:%02d".format(c.first, c.second)} disiapkan." else "Gagal membuka aplikasi jam."
        }
        after(q, "ingatkan aku ", "ingatkan saya ", "remind me to ", "remind me ")?.let { body ->
            val s = durationSec(body)
            val c = clock(body)
            if (s != null) {
                val i = Intent(AlarmClock.ACTION_SET_TIMER).putExtra(AlarmClock.EXTRA_LENGTH, s).putExtra(AlarmClock.EXTRA_MESSAGE, body)
                return if (go(i)) "Pengingat disiapkan: \"$body\"." else "Gagal membuka aplikasi jam."
            }
            if (c != null) {
                val i = Intent(AlarmClock.ACTION_SET_ALARM).putExtra(AlarmClock.EXTRA_HOUR, c.first)
                    .putExtra(AlarmClock.EXTRA_MINUTES, c.second).putExtra(AlarmClock.EXTRA_MESSAGE, body)
                return if (go(i)) "Pengingat jam ${"%02d:%02d".format(c.first, c.second)} disiapkan." else "Gagal membuka aplikasi jam."
            }
            return t("Kapan harus saya ingatkan? Contoh: \"ingatkan aku minum obat 30 menit lagi\".", "Kapan? Contoh: \"ingatkan aku minum obat 30 menit lagi\".")
        }
        after(q, "buat acara ", "tambah acara ", "buat jadwal ", "tambah jadwal ", "add event ")?.let { title ->
            val i = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)
                .putExtra(CalendarContract.Events.TITLE, title.replaceFirstChar { c -> c.uppercase() })
            return if (go(i)) t("Membuka kalender untuk acara \"$title\".", "Buka kalender buat \"$title\".") else "Gagal membuka kalender."
        }

        // ---- info perangkat
        if (has("baterai", "battery")) return batteryText()
        if (has("info perangkat", "device info", "spesifikasi", "diagnostik", "diagnostic")) return diagnostics()
        if (has("cek jaringan", "status jaringan", "koneksi internet", "network status", "ada internet")) return networkText()
        if (has("jam berapa", "what time", "pukul berapa")) return "Pukul ${SimpleDateFormat("HH:mm", idLoc).format(Date())}."
        if (has("tanggal berapa", "hari apa", "what date", "hari ini tanggal"))
            return SimpleDateFormat("EEEE, d MMMM yyyy", idLoc).format(Date()) + "."

        // ---- media, volume, senter
        if (has("lagu berikutnya", "next song", "next track", "skip lagu")) { media(KeyEvent.KEYCODE_MEDIA_NEXT); return t("Lagu berikutnya.", "Next.") }
        if (has("lagu sebelumnya", "previous song", "previous track")) { media(KeyEvent.KEYCODE_MEDIA_PREVIOUS); return t("Lagu sebelumnya.", "Balik lagu.") }
        if (has("jeda musik", "pause musik", "pause music", "hentikan musik", "stop musik")) { media(KeyEvent.KEYCODE_MEDIA_PAUSE); return t("Musik dijeda.", "Dijeda.") }
        if (has("putar musik", "play music", "lanjutkan musik", "resume music")) { media(KeyEvent.KEYCODE_MEDIA_PLAY); return t("Memutar musik.", "Putar.") }
        if (has("volume")) {
            val dir = when {
                has("naik", "besar", "up", "tambah") -> AudioManager.ADJUST_RAISE
                has("turun", "kecil", "down", "kurang") -> AudioManager.ADJUST_LOWER
                has("mute", "bisu", "senyap") -> AudioManager.ADJUST_MUTE
                else -> 0
            }
            if (dir == 0) return t("Volume dinaikkan atau diturunkan?", "Naik apa turun?")
            val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, AudioManager.FLAG_SHOW_UI)
            return t("Volume disesuaikan.", "Sip.")
        }
        if (has("senter", "flashlight", "torch")) return setTorch(!has("mati", "off", "matikan"))

        // ---- telepon dan pesan (hanya membuka draf; pengguna yang menekan kirim/panggil)
        Regex("^(?:kirim )?(?:sms|pesan)(?: ke)? (\\+?\\d[\\d\\s-]{4,}\\d)\\s*(.*)$", RegexOption.IGNORE_CASE).find(text.trim())?.let { m ->
            val num = m.groupValues[1].replace(Regex("[\\s-]"), "")
            val i = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$num")).putExtra("sms_body", m.groupValues[2])
            return if (go(i)) t("Draf pesan dibuka. Silakan periksa lalu kirim.", "Draf kebuka, cek terus kirim ya.") else "Gagal membuka aplikasi pesan."
        }
        after(q, "telepon ", "telpon ", "call ", "hubungi ")?.let { r ->
            val num = r.replace(Regex("[^+\\d]"), "")
            val i = Intent(Intent.ACTION_DIAL)
            if (num.length >= 3) i.data = Uri.parse("tel:$num")
            return if (go(i)) t("Membuka dialer. Silakan tekan panggil.", "Dialer kebuka, tekan panggil ya.") else "Gagal membuka dialer."
        }

        // ---- buka aplikasi / tautan / cari web
        val target = after(q, "buka ", "open ", "jalankan ", "launch ")
        if (target != null && target.isNotEmpty()) {
            if (Regex("^(https?://\\S+|[\\w-]+(\\.[\\w-]+)+(/\\S*)?)$").matches(target)) {
                val url = if (target.startsWith("http")) target else "https://$target"
                return if (go(Intent(Intent.ACTION_VIEW, Uri.parse(url)))) "Membuka $target." else "Gagal membuka tautan."
            }
            return openApp(target)
        }
        after(q, "cari ", "search ", "google ")?.let { s ->
            if (s.isNotEmpty()) {
                go(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/search?q=" + Uri.encode(s))))
                return t("Mencari \"$s\".", "Nyari \"$s\".")
            }
        }

        // ---- kalkulator
        val ex = after(q, "hitung ", "berapa ", "calculate ", "calc ")
            ?: if (Regex("^[\\d\\s+\\-*/x().,]+$").matches(q) && q.any { it.isDigit() }) q else null
        if (ex != null) Calc.eval(ex)?.let { return "= ${Calc.fmt(it)}" }

        return t("Maaf, saya belum memahami perintah itu. Katakan \"bantuan\" untuk melihat daftar perintah. Percakapan bebas membutuhkan model AI lokal, yang belum terpasang.",
            "Aku belum ngerti yang itu. Ketik \"bantuan\" ya. Ngobrol bebas butuh model AI lokal, belum ada.")
    }

    private fun durationSec(q: String): Int? {
        if (q.contains("setengah jam")) return 1800
        val m = Regex("(\\d+)\\s*(detik|dtk|second|sec|menit|mnt|minute|min|jam|hour|hr)").find(q) ?: return null
        val n = m.groupValues[1].toInt()
        return when (m.groupValues[2]) {
            "detik", "dtk", "second", "sec" -> n
            "menit", "mnt", "minute", "min" -> n * 60
            else -> n * 3600
        }
    }

    private fun clock(q: String): Pair<Int, Int>? {
        val m = Regex("(?:jam|pukul|at)\\s*(\\d{1,2})(?:[:.](\\d{2}))?").find(q)
            ?: Regex("\\b(\\d{1,2})[:.](\\d{2})\\b").find(q) ?: return null
        var h = m.groupValues[1].toInt()
        val mi = m.groupValues[2].ifEmpty { "0" }.toInt()
        if ((q.contains("sore") || q.contains("malam") || q.contains(" pm")) && h < 12) h += 12
        return if (h in 0..23 && mi in 0..59) Pair(h, mi) else null
    }

    private fun openApp(name: String): String {
        val pm = ctx.packageManager
        val apps = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
        val n = name.lowercase()
        fun label(r: android.content.pm.ResolveInfo) = r.loadLabel(pm).toString().lowercase()
        val hit = apps.firstOrNull { label(it) == n } ?: apps.firstOrNull { label(it).startsWith(n) } ?: apps.firstOrNull { label(it).contains(n) }
            ?: return t("Saya tidak menemukan aplikasi \"$name\".", "Nggak nemu aplikasi \"$name\".")
        val i = pm.getLaunchIntentForPackage(hit.activityInfo.packageName) ?: return "Aplikasi itu tidak bisa dibuka."
        return if (go(i)) t("Membuka ${hit.loadLabel(pm)}.", "Buka ${hit.loadLabel(pm)}.") else "Gagal membuka aplikasi."
    }

    private fun media(code: Int) {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
    }

    private fun setTorch(on: Boolean): String {
        val cm = ctx.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id = cm.cameraIdList.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true }
            ?: return "Perangkat ini tidak punya senter."
        cm.setTorchMode(id, on)
        return if (on) t("Senter dinyalakan.", "Senter nyala.") else t("Senter dimatikan.", "Senter mati.")
    }

    private fun batteryText(): String {
        val i = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return "Tidak bisa membaca baterai."
        val lv = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val sc = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val st = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val tp = i.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) / 10f
        val ch = st == BatteryManager.BATTERY_STATUS_CHARGING || st == BatteryManager.BATTERY_STATUS_FULL
        return "Baterai ${lv * 100 / sc}%${if (ch) ", sedang mengisi" else ""}, suhu ${"%.1f".format(tp)}°C."
    }

    private fun networkText(): String {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val c = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "Tidak ada koneksi internet."
        val type = when {
            c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "data seluler"
            else -> "jaringan lain"
        }
        return "Terhubung lewat $type."
    }

    /** Ringkasan sistem: dipakai perintah "info perangkat" dan dialog Diagnostik. */
    fun diagnostics(): String {
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo(); am.getMemoryInfo(mi)
        val st = StatFs(Environment.getDataDirectory().path)
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        val thermal = if (Build.VERSION.SDK_INT >= 29) when (pm.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "normal"
            PowerManager.THERMAL_STATUS_LIGHT, PowerManager.THERMAL_STATUS_MODERATE -> "hangat"
            else -> "PANAS"
        } else "tidak diketahui"
        val gb = 1024.0 * 1024.0 * 1024.0
        return "Perangkat: ${Build.MANUFACTURER} ${Build.MODEL}\nAndroid ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})\n" +
            "RAM: ${"%.1f".format(mi.availMem / gb)} GB bebas dari ${"%.1f".format(mi.totalMem / gb)} GB\n" +
            "Penyimpanan bebas: ${"%.1f".format(st.availableBytes / gb)} GB\n" +
            batteryText() + "\nSuhu sistem: $thermal\n" + networkText() + "\n" +
            "Pengenalan suara: ${if (android.speech.SpeechRecognizer.isRecognitionAvailable(ctx)) "tersedia" else "TIDAK tersedia"}\n" +
            "Mesin AI: aturan offline (belum ada model bahasa)\nMemori tersimpan: ${db.memories().size} butir"
    }

    private fun helpText(): String =
        "Contoh perintah:\n" +
        "• buka <aplikasi> / buka youtube.com / cari <kata>\n" +
        "• timer 10 menit · alarm jam 6.30 · ingatkan aku ... 30 menit lagi\n" +
        "• buat acara <judul> · buka pengaturan wifi\n" +
        "• ingat bahwa ... · apa yang kamu ingat · lupakan ...\n" +
        "• baterai · info perangkat · cek jaringan · jam berapa\n" +
        "• putar/jeda musik · lagu berikutnya · volume naik · nyalakan senter\n" +
        "• telepon 0812... · sms 0812... isi pesan\n" +
        "• hitung 12 * (3 + 4) · gaya formal/santai · panggil aku <nama>"
}
EOF

cat > $P/Voice.kt <<'EOF'
package com.zinsch.jarvis

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/** Suara: pengenalan ucapan (push-to-talk) dan sintesis suara, memakai layanan bawaan Android. */
class Voice(private val act: Activity, private val prefs: Prefs) {
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var rec: SpeechRecognizer? = null
    var onState: (Int) -> Unit = {}      // 0 siap, 1 mendengarkan, 2 berbicara
    var onRms: (Float) -> Unit = {}

    init {
        tts = TextToSpeech(act) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) { act.runOnUiThread { onState(0) } }
                override fun onError(utteranceId: String?) { act.runOnUiThread { onState(0) } }
            })
            applyTts()
        }
    }

    fun applyTts() {
        val t = tts ?: return
        if (!ttsReady) return
        t.setLanguage(if (prefs.english) Locale.US else Locale("id", "ID"))
        t.setSpeechRate(prefs.rate)
        t.setPitch(prefs.pitch)
    }

    fun speak(text: String) {
        if (!prefs.speak || !ttsReady) return
        applyTts()
        onState(2)
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "jarvis")
    }

    fun stopSpeaking() { tts?.stop(); onState(0) }

    fun listen(onFinal: (String) -> Unit, onPartial: (String) -> Unit, onErr: (String) -> Unit) {
        if (!SpeechRecognizer.isRecognitionAvailable(act)) { onErr("Pengenalan suara tidak tersedia di perangkat ini."); return }
        stopSpeaking()
        rec?.destroy()
        val r = SpeechRecognizer.createSpeechRecognizer(act)
        rec = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { onState(1) }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) { onRms(rmsdB) }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onError(error: Int) { onState(0); onErr(errText(error)) }
            override fun onResults(results: Bundle?) {
                onState(0)
                val l = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (l != null && l.isNotEmpty()) onFinal(l[0]) else onErr("Tidak terdengar.")
            }
            override fun onPartialResults(partialResults: Bundle?) {
                val l = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (l != null && l.isNotEmpty()) onPartial(l[0])
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, if (prefs.english) "en-US" else "id-ID")
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, prefs.offline)
        r.startListening(i)
    }

    /** Lepas tombol: berhenti merekam, hasil tetap diproses. */
    fun finish() { try { rec?.stopListening() } catch (e: Exception) {} }

    fun release() {
        try { rec?.destroy() } catch (e: Exception) {}
        rec = null
        tts?.stop(); tts?.shutdown(); tts = null
    }

    private fun errText(e: Int): String = when (e) {
        SpeechRecognizer.ERROR_NO_MATCH -> "Tidak ada yang cocok."
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Tidak ada suara terdengar."
        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Jaringan bermasalah (pengenalan suara di perangkat ini butuh internet)."
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Izin mikrofon belum diberikan."
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Pengenal suara sedang sibuk."
        else -> "Kesalahan suara ($e)."
    }
}
EOF

cat > $P/MainActivity.kt <<'EOF'
package com.zinsch.jarvis

import android.Manifest
import android.animation.ValueAnimator
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast

/** Indikator status: berdenyut hanya saat aktif (ringan). */
class OrbView(c: Context) : View(c) {
    private var phase = 0f
    var level = 0f
    private val anim: ValueAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1600
        repeatCount = ValueAnimator.INFINITE
        addUpdateListener { phase = it.animatedValue as Float; invalidate() }
    }
    var mode = 0    // 0 siap, 1 mendengarkan, 2 berpikir, 3 berbicara
        set(v) {
            field = v
            if (v == 0) { anim.cancel(); phase = 0f } else if (!anim.isStarted) anim.start()
            invalidate()
        }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 4f }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    override fun onDraw(cv: Canvas) {
        val cx = width / 2f; val cy = height / 2f; val r = minOf(cx, cy) * .6f
        val col = Color.parseColor(when (mode) { 1 -> "#4FC3A1"; 2 -> "#FFB347"; 3 -> "#00E5FF"; else -> "#2A7F8C" })
        val k = 1f + (if (mode == 1) level * .3f else 0f)
        fill.color = col; fill.alpha = 40; cv.drawCircle(cx, cy, r * 1.25f * k, fill)
        fill.color = col; fill.alpha = 120; cv.drawCircle(cx, cy, r * .55f * k, fill)
        ring.color = col; ring.alpha = 255; cv.drawCircle(cx, cy, r * k, ring)
        if (mode != 0) {
            ring.color = col; ring.alpha = ((1f - phase) * 200).toInt().coerceIn(0, 255)
            cv.drawCircle(cx, cy, r * (1f + phase * .5f) * k, ring)
        }
    }
}

class MainActivity : Activity() {
    private lateinit var prefs: Prefs
    private lateinit var db: MemoryDb
    private lateinit var brain: Brain
    private lateinit var voice: Voice
    private lateinit var orb: OrbView
    private lateinit var status: TextView
    private lateinit var chat: LinearLayout
    private lateinit var scroll: ScrollView
    private lateinit var input: EditText

    private val cy = Color.parseColor("#00E5FF")
    private val ink = Color.parseColor("#D6F6FF")
    private val dim = Color.parseColor("#6E98A6")
    private val bg = Color.parseColor("#050A10")
    private val panel = Color.parseColor("#0B1822")

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = bg
        window.navigationBarColor = bg
        prefs = Prefs(this); db = MemoryDb(this); brain = Brain(this, db, prefs); voice = Voice(this, prefs)
        val mono = Typeface.MONOSPACE

        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(bg) }

        val head = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(36), dp(16), dp(4))
        }
        orb = OrbView(this)
        head.addView(orb, LinearLayout.LayoutParams(dp(64), dp(64)))
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(12), 0, 0, 0) }
        col.addView(TextView(this).apply { text = "J.A.R.V.I.S"; textSize = 20f; typeface = mono; setTextColor(cy) })
        status = TextView(this).apply { text = "Siap"; textSize = 12f; typeface = mono; setTextColor(dim) }
        col.addView(status)
        head.addView(col, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        root.addView(head)

        fun chip(label: String, f: () -> Unit) = TextView(this).apply {
            text = label; typeface = mono; textSize = 13f; setTextColor(cy); gravity = Gravity.CENTER
            setPadding(dp(8), dp(8), dp(8), dp(8))
            background = GradientDrawable().apply { setColor(panel); setStroke(dp(1), Color.parseColor("#17323F")); cornerRadius = dp(10).toFloat() }
            setOnClickListener { f() }
        }
        val chips = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(12), dp(4), dp(12), dp(4)) }
        for ((label, f) in listOf<Pair<String, () -> Unit>>(
            "Memori" to { memoryDialog() }, "Setelan" to { settingsDialog() },
            "Diagnostik" to { diagDialog() }, "■ Diam" to { voice.stopSpeaking() })) {
            val c = chip(label, f)
            chips.addView(c, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { setMargins(dp(3), 0, dp(3), 0) })
        }
        root.addView(chips)

        chat = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(0, dp(8), 0, dp(8)) }
        scroll = ScrollView(this).apply { addView(chat) }
        root.addView(scroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(8), dp(6), dp(8), dp(10)) }
        input = EditText(this).apply {
            hint = "Ketik perintah…"; setTextColor(ink); setHintTextColor(dim)
            inputType = InputType.TYPE_CLASS_TEXT; imeOptions = EditorInfo.IME_ACTION_SEND; setSingleLine(true)
            setOnEditorActionListener { _, _, _ -> submit(text.toString()); true }
        }
        bar.addView(input, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val mic = Button(this).apply {
            text = "🎤 Tahan"; isAllCaps = false
            setOnTouchListener { v, e ->
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> { startListen(); true }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { voice.finish(); v.performClick(); true }
                    else -> false
                }
            }
        }
        bar.addView(mic)
        bar.addView(Button(this).apply { text = "➤"; setOnClickListener { submit(input.text.toString()) } })
        root.addView(bar)
        setContentView(root)

        voice.onState = { s ->
            status.text = when (s) { 1 -> "Mendengarkan…"; 2 -> "Berbicara…"; else -> "Siap" }
            orb.mode = when (s) { 1 -> 1; 2 -> 3; else -> 0 }
        }
        voice.onRms = { v -> orb.level = ((v + 2f) / 12f).coerceIn(0f, 1f) }

        val past = db.recent(40)
        if (past.isEmpty()) bubble("assistant", brain.greeting() + "\nKatakan \"bantuan\" untuk daftar perintah.")
        else for ((role, msg) in past) bubble(role, msg)
    }

    override fun onDestroy() { voice.release(); db.close(); super.onDestroy() }

    private fun submit(raw: String) {
        val t = raw.trim()
        if (t.isEmpty()) return
        input.setText("")
        bubble("user", t)
        if (!prefs.privateMode) db.addMessage("user", t)
        val reply = brain.respond(t)
        bubble("assistant", reply)
        if (!prefs.privateMode) db.addMessage("assistant", reply)
        voice.speak(reply)
    }

    private fun startListen() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
            Toast.makeText(this, "Izinkan mikrofon, lalu tahan tombol lagi.", Toast.LENGTH_LONG).show()
            return
        }
        voice.listen(
            onFinal = { submit(it) },
            onPartial = { status.text = "“$it”" },
            onErr = { status.text = it })
    }

    private fun bubble(role: String, msg: String) {
        val mine = role == "user"
        val tv = TextView(this).apply {
            text = msg; textSize = 15f; setTextColor(if (mine) Color.parseColor("#04201A") else ink)
            setPadding(dp(14), dp(10), dp(14), dp(10)); maxWidth = (resources.displayMetrics.widthPixels * .82f).toInt()
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat(); setColor(if (mine) cy else panel)
                if (!mine) setStroke(dp(1), Color.parseColor("#17323F"))
            }
            setTextIsSelectable(true)
        }
        val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            gravity = if (mine) Gravity.END else Gravity.START
            setMargins(dp(12), dp(5), dp(12), dp(5))
        }
        chat.addView(tv, lp)
        scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
    }

    private fun memoryDialog() {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(8), dp(16), dp(8)) }
        fun refresh() {
            box.removeAllViews()
            val ms = db.memories()
            if (ms.isEmpty()) box.addView(TextView(this).apply { text = "Belum ada memori. Katakan: \"ingat bahwa ...\""; setTextColor(dim) })
            for (m in ms) {
                val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
                row.addView(TextView(this).apply { text = "[${m.cat}] ${m.text}"; setTextColor(ink) },
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                row.addView(Button(this).apply { text = "Hapus"; setOnClickListener { db.deleteMemory(m.id); refresh() } })
                box.addView(row)
            }
        }
        refresh()
        AlertDialog.Builder(this).setTitle("Memori").setView(ScrollView(this).apply { addView(box) })
            .setPositiveButton("Tutup", null)
            .setNeutralButton("Hapus semua") { _, _ -> db.clearMemories() }.show()
    }

    private fun settingsDialog() {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), dp(8)) }
        fun sw(label: String, on: Boolean, set: (Boolean) -> Unit) {
            box.addView(Switch(this).apply {
                text = label; isChecked = on; setTextColor(ink); setPadding(0, dp(6), 0, dp(6))
                setOnCheckedChangeListener { _, c -> set(c) }
            })
        }
        fun seek(label: String, value: Float, set: (Float) -> Unit) {
            box.addView(TextView(this).apply { text = label; setTextColor(dim) })
            box.addView(SeekBar(this).apply {
                max = 150; progress = ((value - .5f) * 100f).toInt().coerceIn(0, 150)
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) { set(.5f + p / 100f) }
                    override fun onStartTrackingTouch(s: SeekBar?) {}
                    override fun onStopTrackingTouch(s: SeekBar?) {}
                })
            })
        }
        sw("Suara JARVIS", prefs.speak) { prefs.speak = it }
        sw("Gaya bicara formal", prefs.formal) { prefs.formal = it }
        sw("Mode privat (tidak menyimpan apa pun)", prefs.privateMode) { prefs.privateMode = it }
        sw("Bahasa Inggris (suara)", prefs.english) { prefs.english = it }
        sw("Utamakan pengenalan suara offline", prefs.offline) { prefs.offline = it }
        seek("Kecepatan bicara", prefs.rate) { prefs.rate = it }
        seek("Nada suara", prefs.pitch) { prefs.pitch = it }
        val nameEdit = EditText(this).apply { setText(prefs.name); hint = "Panggilan"; setTextColor(ink) }
        box.addView(TextView(this).apply { text = "JARVIS memanggilmu:"; setTextColor(dim) })
        box.addView(nameEdit)
        box.addView(Button(this).apply {
            text = "Hapus riwayat percakapan"
            setOnClickListener { db.clearMessages(); chat.removeAllViews(); Toast.makeText(context, "Riwayat dihapus.", Toast.LENGTH_SHORT).show() }
        })
        AlertDialog.Builder(this).setTitle("Setelan").setView(ScrollView(this).apply { addView(box) })
            .setPositiveButton("Selesai", null)
            .setOnDismissListener {
                val n = nameEdit.text.toString().trim()
                if (n.isNotEmpty()) prefs.name = n
                voice.applyTts()
            }.show()
    }

    private fun diagDialog() {
        AlertDialog.Builder(this).setTitle("Diagnostik sistem").setMessage(brain.diagnostics())
            .setPositiveButton("Tutup", null).show()
    }
}
EOF
echo "Proyek JARVIS selesai dibuat."
