package com.alan.thor_companion

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.time.Instant
import java.util.concurrent.Executors

/** Small app-private connection log. No telemetry or command payloads. */
object ThorDiagnostics {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private fun sanitize(message: String) = message
        .replace(Regex("(?i)\\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\\b"), "[Bluetooth address]")
        .replace(Regex("(?i)Bearer\\s+\\S+"), "Bearer [redacted]")
        .replace(Regex("(?i)\\b[a-f0-9]{64}\\b"), "[credential redacted]")
        .replace('\n', ' ').take(2048)

    fun call(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val app = context.applicationContext
        when (call.method) {
            "info" -> {
                val info = app.packageManager.getPackageInfo(app.packageName, 0)
                val connectAllowed=app.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT)==android.content.pm.PackageManager.PERMISSION_GRANTED
                val scanAllowed=app.checkSelfPermission(android.Manifest.permission.BLUETOOTH_SCAN)==android.content.pm.PackageManager.PERMISSION_GRANTED
                val id=call.argument<String>("deviceId")
                val bond=try {
                    if(!connectAllowed) "Permission needed"
                    else if(id==null||!android.bluetooth.BluetoothAdapter.checkBluetoothAddress(id)) "No Bluetooth device selected"
                    else when(app.getSystemService(android.bluetooth.BluetoothManager::class.java)?.adapter?.getRemoteDevice(id)?.bondState){
                        android.bluetooth.BluetoothDevice.BOND_BONDED -> "Paired"
                        android.bluetooth.BluetoothDevice.BOND_BONDING -> "Pairing in progress"
                        null -> "Unavailable"
                        else -> "Not paired"
                    }
                }catch(_:Exception){"Unavailable"}
                result.success(mapOf("bond" to bond,"scanPermission" to if(scanAllowed) "Allowed" else "Denied", "connectPermission" to if(connectAllowed) "Allowed" else "Denied", "phone" to "${Build.MANUFACTURER} ${Build.MODEL}",
                    "os" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                    "client" to "${info.versionName} (${info.longVersionCode})"))
            }
            "append" -> {
                val message = call.arguments as? String
                if (message == null || message.length > 8192) { result.error("diagnostic", "Invalid connection event.", null); return }
                val safe = sanitize(message)
                worker.execute {
                    try {
                        val file = File(app.filesDir, "ble-diagnostics.log")
                        if (file.length() >= 256 * 1024) {
                            val previous = File(app.filesDir, "ble-diagnostics.previous.log")
                            previous.delete()
                            if (!file.renameTo(previous)) file.writeText("")
                        }
                        file.appendText("${Instant.now()} $safe\n")
                    } catch (_: Exception) { /* Diagnostics must not interrupt Bluetooth. */ }
                }
                result.success(null)
            }
            "read" -> worker.execute {
                val text = try {
                    listOf("ble-diagnostics.previous.log", "ble-diagnostics.log").joinToString("") { name ->
                        val file = File(app.filesDir, name)
                        if (file.isFile) file.readText().takeLast(32768) else ""
                    }.takeLast(32768)
                } catch (_: Exception) { "" }
                main.post { result.success(text) }
            }
            else -> result.notImplemented()
        }
    }
}
