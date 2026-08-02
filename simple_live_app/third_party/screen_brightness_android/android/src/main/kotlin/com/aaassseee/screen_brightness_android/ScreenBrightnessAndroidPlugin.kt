package com.aaassseee.screen_brightness_android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import com.aaassseee.screen_brightness_android.stream_handler.ScreenBrightnessChangedStreamHandler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import java.lang.reflect.Field
import kotlin.math.sign
import kotlin.properties.Delegates
import androidx.core.net.toUri

/**
 * ScreenBrightnessAndroidPlugin setting screen brightness
 */
class ScreenBrightnessAndroidPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    /**
     * The MethodChannel that will the communication between Flutter and native Android
     *
     * This local reference serves to register the plugin with the Flutter Engine and unregister it
     * when the Flutter Engine is detached from the Activity
     */
    private lateinit var methodChannel: MethodChannel

    private var context: Context? = null

    private var activity: Activity? = null

    private lateinit var systemScreenBrightnessChangedEventChannel: EventChannel

    private var systemScreenBrightnessChangedStreamHandler: ScreenBrightnessChangedStreamHandler? = null

    private lateinit var applicationScreenBrightnessChangedEventChannel: EventChannel

    private var applicationScreenBrightnessChangedStreamHandler: ScreenBrightnessChangedStreamHandler? = null

    private val contextObserver: ContentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            super.onChange(selfChange)
            context?.let {
                try {
                    systemScreenBrightness = getSystemScreenBrightness(it)
                    systemScreenBrightnessChangedStreamHandler?.eventSink?.success(systemScreenBrightness)
                    if (applicationScreenBrightness == null) {
                        applicationScreenBrightnessChangedStreamHandler?.eventSink?.success(systemScreenBrightness)
                    }
                } catch (e: Settings.SettingNotFoundException) {
                    e.printStackTrace()
                }
            }
        }
    }

    /**
     * The value which will be init when this plugin is attached to the Flutter engine
     *
     * This value refer to the maximum brightness value.
     *
     * By system default the value should be 255.0f, however it vary in some OS, e.g. Miui.
     * Should not be changed in the future
     */
    private var maximumScreenBrightness by Delegates.notNull<Float>()

    /**
     * The value which will be init when this plugin is attached to the Flutter engine
     *
     * This value refer to the brightness value between 0 and 1 when the application initialized.
     */
    private var systemScreenBrightness by Delegates.notNull<Float>()

    /**
     * The value which will be set when user called [handleSetApplicationScreenBrightnessMethodCall]
     * or [handleResetApplicationScreenBrightnessMethodCall]
     *
     * This value refer to the brightness value between 0 and 1 when user called [handleSetApplicationScreenBrightnessMethodCall].
     */
    private var applicationScreenBrightness: Float? = null

    private var isAutoReset: Boolean = true

    private var isAnimate: Boolean = true

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger, "github.com/aaassseee/screen_brightness"
        )
        methodChannel.setMethodCallHandler(this)

        systemScreenBrightnessChangedEventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger, "github.com/aaassseee/screen_brightness/system_brightness_changed"
        )

        applicationScreenBrightnessChangedEventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "github.com/aaassseee/screen_brightness/application_brightness_changed"
        )

        try {
            maximumScreenBrightness = getScreenMaximumBrightness(flutterPluginBinding.applicationContext)
            systemScreenBrightness = getSystemScreenBrightness(flutterPluginBinding.applicationContext)
        } catch (e: Settings.SettingNotFoundException) {
            e.printStackTrace()
        }

        context = flutterPluginBinding.applicationContext
        flutterPluginBinding.applicationContext.contentResolver.registerContentObserver(
            Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS),
            false,
            contextObserver,
        )
        systemScreenBrightnessChangedStreamHandler = ScreenBrightnessChangedStreamHandler(null)
        systemScreenBrightnessChangedEventChannel.setStreamHandler(systemScreenBrightnessChangedStreamHandler)

        applicationScreenBrightnessChangedStreamHandler = ScreenBrightnessChangedStreamHandler(null)
        applicationScreenBrightnessChangedEventChannel.setStreamHandler(applicationScreenBrightnessChangedStreamHandler)

    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSystemScreenBrightness" -> handleGetSystemScreenBrightnessMethodCall(result)
            "setSystemScreenBrightness" -> handleSetSystemScreenBrightnessMethodCall(call, result)
            "getApplicationScreenBrightness" -> handleGetApplicationScreenBrightnessMethodCall(result)
            "setApplicationScreenBrightness" -> handleSetApplicationScreenBrightnessMethodCall(call, result)
            "resetApplicationScreenBrightness" -> handleResetApplicationScreenBrightnessMethodCall(result)
            "hasApplicationScreenBrightnessChanged" -> handleHasApplicationScreenBrightnessChangedMethodCall(result)
            "isAutoReset" -> handleIsAutoResetMethodCall(result)
            "setAutoReset" -> handleSetAutoResetMethodCall(call, result)
            "isAnimate" -> handleIsAnimateMethodCall(result)
            "setAnimate" -> handleSetAnimateMethodCall(call, result)
            "canChangeSystemBrightness" -> handleCanChangeSystemBrightness(result)
            else -> result.notImplemented()
        }
    }

    private fun handleGetSystemScreenBrightnessMethodCall(result: MethodChannel.Result) {
        result.success(systemScreenBrightness)
    }

    private fun handleSetSystemScreenBrightnessMethodCall(
        call: MethodCall, result: MethodChannel.Result
    ) {
        val context = context
        if (context == null) {
            result.error("-10", "Unexpected error on activity binding", null)
            return
        }

        val brightness: Float? = (call.argument("brightness") as? Double)?.toFloat()
        if (brightness == null) {
            result.error("-2", "Unexpected error on null brightness", null)
            return
        }

        val isSet = setSystemScreenBrightness(context, brightness)
        if (!isSet) {
            result.error("-1", "Unable to change system screen brightness", null)
            return
        }

        systemScreenBrightness = brightness
        handleSystemScreenBrightnessChanged(brightness)
        result.success(null)
    }

    private fun handleSystemScreenBrightnessChanged(brightness: Float) {
        systemScreenBrightnessChangedStreamHandler?.addScreenBrightnessToEventSink(brightness.toDouble())
    }

    private fun handleGetApplicationScreenBrightnessMethodCall(result: MethodChannel.Result) {
        val activity = activity
        if (activity == null) {
            result.error("-10", "Unexpected error on activity binding", null)
            return
        }

        var brightness: Float?
        // get current window attribute brightness
        val layoutParams: WindowManager.LayoutParams = activity.window.attributes
        brightness = layoutParams.screenBrightness
        // check brightness changed
        if (brightness.sign != -1.0f) {
            // return changed brightness
            result.success(brightness)
            return
        }

        // get system setting brightness
        try {
            brightness = getSystemScreenBrightness(activity.applicationContext)
            result.success(brightness)
        } catch (e: Settings.SettingNotFoundException) {
            e.printStackTrace()
            result.error("-11", "Could not found application screen brightness", null)
            return
        }
    }

    private fun handleSetApplicationScreenBrightnessMethodCall(
        call: MethodCall, result: MethodChannel.Result
    ) {
        val context = context
        if (context == null) {
            result.error("-10", "Unexpected error on activity binding", null)
            return
        }

        val brightness: Float? = (call.argument("brightness") as? Double)?.toFloat()
        if (brightness == null) {
            result.error("-2", "Unexpected error on null brightness", null)
            return
        }

        val isSet = setWindowsAttributesBrightness(brightness)
        if (!isSet) {
            result.error("-1", "Unable to change application screen brightness", null)
            return
        }

        applicationScreenBrightness = brightness
        handleApplicationScreenBrightnessChanged(brightness)
        result.success(null)
    }

    private fun handleResetApplicationScreenBrightnessMethodCall(result: MethodChannel.Result) {
        val context = context
        if (context == null) {
            result.error("-10", "Unexpected error on activity binding", null)
            return
        }

        val isSet = setWindowsAttributesBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
        if (!isSet) {
            result.error("-1", "Unable to reset screen brightness", null)
            return
        }

        applicationScreenBrightness = null
        handleApplicationScreenBrightnessChanged(systemScreenBrightness)
        result.success(null)
    }

    private fun handleApplicationScreenBrightnessChanged(brightness: Float) {
        applicationScreenBrightnessChangedStreamHandler?.addScreenBrightnessToEventSink(brightness.toDouble())
    }

    private fun handleHasApplicationScreenBrightnessChangedMethodCall(result: MethodChannel.Result) {
        result.success(applicationScreenBrightness != null)
    }

    private fun handleIsAutoResetMethodCall(result: MethodChannel.Result) {
        result.success(isAutoReset)
    }

    private fun handleSetAutoResetMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val isAutoReset: Boolean? = call.argument("isAutoReset") as? Boolean
        if (isAutoReset == null) {
            result.error("-2", "Unexpected error on null isAutoReset", null)
            return
        }

        this.isAutoReset = isAutoReset
        result.success(null)
    }

    private fun handleIsAnimateMethodCall(result: MethodChannel.Result) {
        result.success(isAnimate)
    }

    private fun handleSetAnimateMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val isAnimate: Boolean? = call.argument("isAnimate") as? Boolean
        if (isAnimate == null) {
            result.error("-2", "Unexpected error on null isAnimate", null)
            return
        }

        this.isAnimate = isAnimate
        result.success(null)
    }

    private fun handleCanChangeSystemBrightness(result: MethodChannel.Result) {
        val context = context
        if (context == null) {
            result.error("-10", "Unexpected error on activity binding", null)
            return
        }

        result.success(canWriteSystemSetting(context))
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context?.contentResolver?.unregisterContentObserver(contextObserver)
        methodChannel.setMethodCallHandler(null)
        systemScreenBrightnessChangedEventChannel.setStreamHandler(null)
        systemScreenBrightnessChangedStreamHandler = null
        applicationScreenBrightnessChangedEventChannel.setStreamHandler(null)
        applicationScreenBrightnessChangedStreamHandler = null
    }

    private fun getSystemScreenBrightness(context: Context): Float {
        return Settings.System.getInt(
            context.contentResolver, Settings.System.SCREEN_BRIGHTNESS
        ) / maximumScreenBrightness
    }

    private fun setSystemScreenBrightness(context: Context, brightness: Float): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!canWriteSystemSetting(context)) {
                Intent(
                    Settings.ACTION_MANAGE_WRITE_SETTINGS, "package:${context.packageName}".toUri()
                ).let {
                    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(it)
                }
                return false
            }
        }

        return Settings.System.putInt(
            context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, (maximumScreenBrightness * brightness).toInt()
        )
    }

    private fun getScreenMaximumBrightness(context: Context): Float {
        try {
            val powerManager: PowerManager =
                context.getSystemService(Context.POWER_SERVICE) as PowerManager? ?: throw ClassNotFoundException()
            val fields: Array<Field> = powerManager.javaClass.declaredFields
            for (field in fields) {
                if (field.name.equals("BRIGHTNESS_ON")) {
                    field.isAccessible = true
                    return (field[powerManager] as Int).toFloat()
                }
            }

            return 255.0f
        } catch (_: Exception) {
            return 255.0f
        }
    }

    private fun setWindowsAttributesBrightness(brightness: Float): Boolean {
        return try {
            val layoutParams: WindowManager.LayoutParams = activity!!.window.attributes
            layoutParams.screenBrightness = brightness
            activity!!.window.attributes = layoutParams
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun canWriteSystemSetting(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.System.canWrite(context)
        } else {
            true
        }
    }
}
