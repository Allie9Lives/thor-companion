package com.alan.thor_companion

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private fun saveRecording(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("paths")
        val screen = call.argument<String>("screen")
        val root = java.io.File(cacheDir,"thor-transfers").canonicalPath + java.io.File.separator
        if (Build.VERSION.SDK_INT < 29 || screen !in listOf("top","bottom","both") || paths == null || paths.size != (if (screen == "both") 2 else 1)) {
            result.error("recording", "Invalid recording files.", null); return
        }
        val clips = paths.map { java.io.File(it) }
        if (clips.any { !it.canonicalPath.startsWith(root) || !it.isFile || it.extension != "mp4" || it.length() !in 128..(512L*1024*1024) }) {
            result.error("recording", "Recording cache is unavailable. Download again.", null); return
        }
        Thread {
            val inserted = mutableListOf<android.net.Uri>()
            try {
                clips.forEachIndexed { index, file ->
                    val label = if (screen == "both") if (index == 0) "top" else "bottom" else screen
                    val values = ContentValues().apply {
                        put(MediaStore.Video.Media.DISPLAY_NAME,"Thor-$label-${System.currentTimeMillis()}.mp4")
                        put(MediaStore.Video.Media.MIME_TYPE,"video/mp4")
                        put(MediaStore.Video.Media.RELATIVE_PATH,"${Environment.DIRECTORY_MOVIES}/Thor Companion")
                        put(MediaStore.Video.Media.IS_PENDING,1)
                    }
                    val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI,values) ?: error("Could not create video")
                    inserted.add(uri)
                    contentResolver.openOutputStream(uri)?.use { output -> file.inputStream().use { it.copyTo(output,65536) } } ?: error("Could not save video")
                }
                for (uri in inserted) contentResolver.update(uri,ContentValues().apply {put(MediaStore.Video.Media.IS_PENDING,0)},null,null)
                runOnUiThread {result.success(null)}
            } catch (e: Exception) {
                for (uri in inserted) contentResolver.delete(uri,null,null)
                runOnUiThread {result.error("recording_save","Could not save recording to Photos. Check available storage.",null)}
            }
        }.start()
    }
    private val files by lazy { ThorFileBridge(this) }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (!files.activityResult(requestCode, resultCode, data)) super.onActivityResult(requestCode, resultCode, data)
    }
    private var alertPermission: MethodChannel.Result? = null
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 8221) {
            alertPermission?.success(grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED)
            alertPermission = null
        }
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger,"com.alan.thorCompanion/diagnostics").setMethodCallHandler { call,result -> ThorDiagnostics.call(this,call,result) }
        MethodChannel(engine.dartExecutor.binaryMessenger,"com.alan.thorCompanion/wifi").setMethodCallHandler { call,result ->
            if(call.method!="current") result.notImplemented()
            else try {
                val wifi=applicationContext.getSystemService(android.content.Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                val name=wifi.connectionInfo.ssid?.removeSurrounding("\"")
                result.success(if(name.isNullOrEmpty() || name=="<unknown ssid>") null else mapOf("name" to name,"event" to name))
            } catch(e:Exception){result.success(null)}
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.alan.thorCompanion/about").setMethodCallHandler { call, result ->
            when (call.method) {
                "version" -> {val info=packageManager.getPackageInfo(packageName,0);result.success(mapOf("version" to info.versionName,"build" to info.longVersionCode.toString()))}
                "appearanceIcon" -> try {
                    val mode=call.arguments as? String
                    val target=mapOf("dark" to "Dark", "light" to "Light", "clearPurple" to "Purple", "rainbow" to "Rainbow")[mode] ?: error("Unknown theme")
                    val names=listOf(target)+listOf("Dark","Light","Purple","Rainbow").filter{it!=target}
                    if(Build.VERSION.SDK_INT>=33) { val updates=names.map {name -> android.content.pm.PackageManager.ComponentEnabledSetting(android.content.ComponentName(this,"$packageName.Launcher$name"),if(name==target)android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED else android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,android.content.pm.PackageManager.DONT_KILL_APP)}
                    packageManager.setComponentEnabledSettings(updates) }
                    else names.forEach { name -> packageManager.setComponentEnabledSetting(android.content.ComponentName(this,"$packageName.Launcher$name"),if(name==target)android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED else android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,android.content.pm.PackageManager.DONT_KILL_APP) }
                    result.success(null)
                } catch(e:Exception){result.error("icon","Could not update the app icon.",null)}
                "webOps" -> try {
                    val url=android.net.Uri.parse(call.arguments as? String ?: "")
                    require(url.scheme=="https"&&url.port==47184&&url.host!=null&&url.userInfo==null)
                    startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW,url));result.success(null)
                } catch(e:Exception){result.error("open_link","Could not open Web Ops.",null)}
                "github" -> try {startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW,android.net.Uri.parse("https://github.com/Allie9Lives")));result.success(null)} catch (e: Exception) {result.error("open_link","Couldn’t open GitHub.",null)}
                else -> result.notImplemented()
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.alan.thorCompanion/files").setMethodCallHandler { call, result -> files.call(call, result) }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.alan.thorCompanion/batteryAlerts").setMethodCallHandler { call, result ->
            val manager = getSystemService(android.app.NotificationManager::class.java)
            if (call.method == "requestPermission") {
                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    if (alertPermission != null) result.error("battery_alert_permission", "A permission request is already open.", null)
                    else { alertPermission = result; requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 8221) }
                } else result.success(manager.areNotificationsEnabled())
            } else if (call.method == "show") {
                val id = call.argument<String>("id")
                val title = call.argument<String>("title")
                val body = call.argument<String>("body")
                if (id !in listOf("low10", "low20", "charged80", "plugged", "unplugged", "closedLid", "wifiChanged", "wifiLost", "wifiSignIn", "bluetoothLost", "bluetoothBack", "test") || title == null || body == null || title.length >= 160 || body.length >= 500) {
                    result.error("battery_alert", "Invalid battery notification.", null)
                } else if (!manager.areNotificationsEnabled()) {
                    result.error("battery_alert_permission", "Allow notifications in system settings.", null)
                } else {
                    val positive = id in listOf("plugged", "charged80", "wifiChanged", "bluetoothBack", "test")
                    val channelId = if (positive) "thor_battery_positive_v2" else "thor_battery_warning_v2"
                    val channel = android.app.NotificationChannel(channelId, if (positive) "Battery status" else "Battery warnings", android.app.NotificationManager.IMPORTANCE_DEFAULT)
                    val sound = android.net.Uri.parse("android.resource://$packageName/raw/" + if (positive) "thor_positive" else "thor_warning")
                    channel.setSound(sound, android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION).build())
                    manager.createNotificationChannel(channel)
                    val intent = android.content.Intent(this, MainActivity::class.java)
                    val pending = android.app.PendingIntent.getActivity(this, 31, intent, android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT)
                    val notification = android.app.Notification.Builder(this, channelId).setSmallIcon(android.R.drawable.ic_lock_idle_low_battery)
                        .setContentTitle(title).setContentText(body).setStyle(android.app.Notification.BigTextStyle().bigText(body)).setAutoCancel(true).setContentIntent(pending).build()
                    try { manager.notify(id.hashCode(), notification); result.success(null) }
                    catch (e: SecurityException) { result.error("battery_alert_permission", "Allow notifications in system settings.", null) }
                }
            } else result.notImplemented()
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.alan.thorCompanion/screenshots").setMethodCallHandler { call, result ->
            if (call.method == "saveVideo") {saveRecording(call,result);return@setMethodCallHandler}
            if (call.method == "keepAwake") {
                if (call.arguments == true) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                result.success(null)
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("png")
            val screen = call.argument<String>("screen")
            if (call.method != "save" || bytes == null || bytes.size < 24 || bytes.size > 24 * 1024 * 1024 || screen !in listOf("top", "bottom", "both")) {
                result.error("screenshot", "Invalid screenshot image.", null)
            } else if (Build.VERSION.SDK_INT < 29) {
                result.error("screenshot", "Saving screenshots needs Android 10 or later.", null)
            } else {
                Thread {
                    var uri: android.net.Uri? = null
                    try {
                        val values = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, "Thor-$screen-${System.currentTimeMillis()}.png")
                            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Thor Companion")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                        uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("Could not create photo")
                        contentResolver.openOutputStream(uri!!)?.use { it.write(bytes) } ?: error("Could not write photo")
                        contentResolver.update(uri!!, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
                        runOnUiThread { result.success(null) }
                    } catch (e: Exception) {
                        uri?.let { contentResolver.delete(it, null, null) }
                        runOnUiThread { result.error("screenshot_save", "Could not save screenshot to Photos.", null) }
                    }
                }.start()
            }
        }
    }
}
