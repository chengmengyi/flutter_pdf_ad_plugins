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
    private var nativeFactoryRegistered = false

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
        if (nativeFactoryRegistered) {
            return
        }
        val factory = GuideCompactNativeAdFactory(binding.applicationContext)
        factory.layoutName = smallNativeAdLayoutName
        val registered = GoogleMobileAdsPlugin.registerNativeAdFactory(
            binding.flutterEngine,
            GUIDE_COMPACT_NATIVE_FACTORY_ID,
            factory
        )
        if (registered) {
            guideCompactNativeFactory = factory
            nativeFactoryRegistered = true
        }
    }

    private fun unregisterNativeAdFactories(binding: FlutterPluginBinding) {
        if (nativeFactoryRegistered) {
            GoogleMobileAdsPlugin.unregisterNativeAdFactory(
                binding.flutterEngine,
                GUIDE_COMPACT_NATIVE_FACTORY_ID
            )
        }
        guideCompactNativeFactory = null
        nativeFactoryRegistered = false
    }

    private fun ensureNativeAdFactoryRegistered() {
        val binding = flutterPluginBinding ?: return
        if (nativeFactoryRegistered) {
            return
        }
        try {
            registerNativeAdFactories(binding)
        } catch (_: Throwable) {
        }
    }

    companion object {
        const val GUIDE_COMPACT_NATIVE_FACTORY_ID = "guide_compact_native"
    }
}
