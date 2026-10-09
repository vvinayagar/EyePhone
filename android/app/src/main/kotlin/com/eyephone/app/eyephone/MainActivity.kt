package com.eyephone.app.eyephone

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.view.KeyEvent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val HEADPHONE_CHANNEL = "com.eyephone.app/headphone"
    private val GEMINI_NANO_CHANNEL = "com.eyephone.app/gemini_nano"

    private var headphoneChannel: MethodChannel? = null
    private var geminiNanoChannel: MethodChannel? = null

    private var headsetReceiver: BroadcastReceiver? = null
    private var audioManager: AudioManager? = null
    private var localLlmEngine: LocalLlmEngine? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Headphone channel
        headphoneChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HEADPHONE_CHANNEL)
        headphoneChannel?.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "getHeadphoneStatus" -> {
                    result.success(getCurrentHeadphoneStatus())
                }
                else -> result.notImplemented()
            }
        }

        // On-device AI channel (MediaPipe Gemma 3n, with AICore capability reporting)
        localLlmEngine = LocalLlmEngine(applicationContext)

        geminiNanoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GEMINI_NANO_CHANNEL)
        geminiNanoChannel?.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "isAICoreAvailable" -> {
                    val available = isAICoreInstalled()
                    result.success(available)
                }
                "getDeviceInfo" -> {
                    val info = mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "sdkInt" to Build.VERSION.SDK_INT,
                        "hasAICore" to isAICoreInstalled()
                    )
                    result.success(info)
                }
                "getLocalModelStatus" -> {
                    result.success(localLlmEngine?.status() ?: emptyMap<String, Any?>())
                }
                "initializeLocalModel" -> {
                    val engine = localLlmEngine
                    if (engine == null) {
                        result.error("NO_ENGINE", "Local engine unavailable", null)
                    } else {
                        engine.initialize { status -> result.success(status) }
                    }
                }
                "runLocalPrompt" -> {
                    val engine = localLlmEngine
                    val prompt = call.argument<String>("prompt") ?: ""
                    val image = call.argument<ByteArray>("image")
                    if (engine == null) {
                        result.error("NO_ENGINE", "Local engine unavailable", null)
                    } else {
                        engine.generate(prompt, image) { res -> result.success(res) }
                    }
                }
                else -> result.notImplemented()
            }
        }

        registerHeadsetReceivers()
    }

    private fun getCurrentHeadphoneStatus(): Map<String, Any> {
        val am = audioManager ?: return mapOf("connected" to false, "type" to "none", "name" to "")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (device in devices) {
                when (device.type) {
                    AudioDeviceInfo.TYPE_WIRED_HEADSET,
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_USB_HEADSET -> {
                        return mapOf(
                            "connected" to true,
                            "type" to "wired",
                            "name" to (device.productName?.toString() ?: "Wired Headset")
                        )
                    }
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_BLE_HEADSET -> {
                        return mapOf(
                            "connected" to true,
                            "type" to "bluetooth",
                            "name" to (device.productName?.toString() ?: "Bluetooth Headset")
                        )
                    }
                }
            }
        } else {
            @Suppress("DEPRECATION")
            if (am.isWiredHeadsetOn) {
                return mapOf("connected" to true, "type" to "wired", "name" to "Wired Headset")
            }
            @Suppress("DEPRECATION")
            if (am.isBluetoothA2dpOn || am.isBluetoothScoOn) {
                return mapOf("connected" to true, "type" to "bluetooth", "name" to "Bluetooth Headset")
            }
        }

        return mapOf("connected" to false, "type" to "none", "name" to "")
    }

    private fun registerHeadsetReceivers() {
        headsetReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                intent?.let {
                    val status = getCurrentHeadphoneStatus()
                    headphoneChannel?.invokeMethod("onHeadphoneStateChanged", status)
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_HEADSET_PLUG)
            addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
            addAction("android.bluetooth.a2dp.profile.action.CONNECTION_STATE_CHANGED")
        }

        registerReceiver(headsetReceiver, filter)
    }

    override fun onDestroy() {
        super.onDestroy()
        headsetReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        localLlmEngine?.dispose()
        localLlmEngine = null
    }

    // Intercept Headset Button and Media Keys so blind user can click earphone button to talk
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_HEADSETHOOK,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                KeyEvent.KEYCODE_MEDIA_PLAY,
                KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                    headphoneChannel?.invokeMethod("onHeadsetButtonPressed", mapOf("keyCode" to event.keyCode))
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    // Check if Google AICore (On-Device Gemini Nano) is installed
    private fun isAICoreInstalled(): Boolean {
        return try {
            val pm = packageManager
            pm.getPackageInfo("com.google.android.aicore", PackageManager.GET_ACTIVITIES)
            true
        } catch (_: Exception) {
            false
        }
    }

}
