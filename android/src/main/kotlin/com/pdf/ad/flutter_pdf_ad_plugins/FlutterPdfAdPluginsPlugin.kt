package com.pdf.ad.flutter_pdf_ad_plugins

import android.content.Context
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** FlutterPdfAdPluginsPlugin */
class FlutterPdfAdPluginsPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null
    private var flutterPluginBinding: FlutterPluginBinding? = null
    private var guideCompactNativeFactory: GuideCompactNativeAdFactory? = null
    private var smallNativeAdLayoutName: String? = null
    private var guideCompactNativeFactoryRegistered = false
    private var fullScreenNativeFactoryRegistered = false

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_pdf_ad_plugins")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "getAndroidId" -> {
                val context = applicationContext
                if (context == null) {
                    result.success(null)
                    return
                }
                val androidId = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ANDROID_ID
                )
                result.success(androidId)
            }
            "configureSmallNativeAdLayout" -> {
                val layoutName = call.argument<String>("layoutName")?.trim()
                smallNativeAdLayoutName = layoutName?.takeIf { it.isNotEmpty() }
                ensureNativeAdFactoryRegistered()
                guideCompactNativeFactory?.layoutName = smallNativeAdLayoutName
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        unregisterNativeAdFactories(binding)
        channel.setMethodCallHandler(null)
        flutterPluginBinding = null
        applicationContext = null
    }

    private fun registerNativeAdFactories(binding: FlutterPluginBinding) {
        if (!guideCompactNativeFactoryRegistered) {
            val guideFactory = GuideCompactNativeAdFactory(binding.applicationContext)
            guideFactory.layoutName = smallNativeAdLayoutName
            val guideRegistered = GoogleMobileAdsPlugin.registerNativeAdFactory(
                binding.flutterEngine,
                GUIDE_COMPACT_NATIVE_FACTORY_ID,
                guideFactory
            )
            if (guideRegistered) {
                guideCompactNativeFactory = guideFactory
                guideCompactNativeFactoryRegistered = true
            }
        }
        if (!fullScreenNativeFactoryRegistered) {
            val fullScreenRegistered = GoogleMobileAdsPlugin.registerNativeAdFactory(
                binding.flutterEngine,
                FULL_SCREEN_NATIVE_FACTORY_ID,
                FullScreenNativeAdFactory(binding.applicationContext)
            )
            if (fullScreenRegistered) {
                fullScreenNativeFactoryRegistered = true
            }
        }
    }

    private fun unregisterNativeAdFactories(binding: FlutterPluginBinding) {
        if (guideCompactNativeFactoryRegistered) {
            GoogleMobileAdsPlugin.unregisterNativeAdFactory(
                binding.flutterEngine,
                GUIDE_COMPACT_NATIVE_FACTORY_ID
            )
        }
        if (fullScreenNativeFactoryRegistered) {
            GoogleMobileAdsPlugin.unregisterNativeAdFactory(
                binding.flutterEngine,
                FULL_SCREEN_NATIVE_FACTORY_ID
            )
        }
        guideCompactNativeFactory = null
        guideCompactNativeFactoryRegistered = false
        fullScreenNativeFactoryRegistered = false
    }

    private fun ensureNativeAdFactoryRegistered() {
        val binding = flutterPluginBinding ?: return
        if (guideCompactNativeFactoryRegistered && fullScreenNativeFactoryRegistered) {
            return
        }
        try {
            registerNativeAdFactories(binding)
        } catch (_: Throwable) {
        }
    }

    companion object {
        const val GUIDE_COMPACT_NATIVE_FACTORY_ID = "guide_compact_native"
        const val FULL_SCREEN_NATIVE_FACTORY_ID = "full_screen_native"
    }
}
