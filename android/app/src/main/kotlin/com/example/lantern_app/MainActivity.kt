package com.example.lantern_app // <-- Keep your existing package name here!

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "lantern.audio/mute"
    private var savedVolume: Int? = null

    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vm?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    private fun vibrateEffect(effect: VibrationEffect) {
        val vibrator = getVibrator() ?: return
        if (!vibrator.hasVibrator()) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val attrs = VibrationAttributes.Builder()
                    .setUsage(VibrationAttributes.USAGE_HARDWARE_FEEDBACK)
                    .build()
                vibrator.vibrate(effect, attrs)
            } else {
                vibrator.vibrate(effect)
            }
        } catch (_: Exception) {}
    }

    private fun triggerIosHaptic(type: String, amplitude: Int) {
        val vibrator = getVibrator() ?: return
        if (!vibrator.hasVibrator()) return

        try {
            // Android 11+ (API 30+): Use hardware LRA Taptic Primitives if supported
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                when (type) {
                    "tick" -> {
                        if (vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_TICK)) {
                            val scale = (amplitude.coerceIn(40, 255) / 255f).coerceIn(0.25f, 1.0f)
                            vibrateEffect(
                                VibrationEffect.startComposition()
                                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, scale)
                                    .compose()
                            )
                            return
                        }
                    }
                    "lowTick" -> {
                        if (vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_LOW_TICK)) {
                            val scale = (amplitude.coerceIn(30, 255) / 255f).coerceIn(0.2f, 0.85f)
                            vibrateEffect(
                                VibrationEffect.startComposition()
                                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_LOW_TICK, scale)
                                    .compose()
                            )
                            return
                        }
                    }
                    "click" -> {
                        if (vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK)) {
                            vibrateEffect(
                                VibrationEffect.startComposition()
                                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.85f)
                                    .compose()
                            )
                            return
                        }
                    }
                    "heavy" -> {
                        if (vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK)) {
                            vibrateEffect(
                                VibrationEffect.startComposition()
                                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1.0f)
                                    .compose()
                            )
                            return
                        }
                    }
                }
            }

            // Android 10+ (API 29+) Predefined & Custom OneShot LRA micro-pulses
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = when (type) {
                    "tick" -> VibrationEffect.createOneShot(7, amplitude.coerceIn(60, 180))
                    "lowTick" -> VibrationEffect.createOneShot(5, amplitude.coerceIn(40, 120))
                    "click" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                    } else {
                        VibrationEffect.createOneShot(10, 160)
                    }
                    "heavy" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK)
                    } else {
                        VibrationEffect.createOneShot(18, 255)
                    }
                    "pulse" -> VibrationEffect.createOneShot(12, amplitude.coerceIn(45, 240))
                    else -> VibrationEffect.createOneShot(8, 120)
                }
                vibrateEffect(effect)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(10)
            }
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "muteMedia" -> {
                        if (savedVolume == null) {
                            savedVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                        }
                        result.success(null)
                    }
                    "unmuteMedia" -> {
                        savedVolume = null
                        result.success(null)
                    }
                    "haptic" -> {
                        val type = call.argument<String>("type") ?: "tick"
                        val amp = call.argument<Int>("amp") ?: 120
                        triggerIosHaptic(type, amp)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}