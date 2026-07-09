package com.pdf.ad.flutter_pdf_ad_plugins

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.Collections
import java.util.WeakHashMap

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
    private var application: Application? = null
    private val activeActivities = Collections.newSetFromMap(WeakHashMap<Activity, Boolean>())
    private val adActivities = Collections.newSetFromMap(WeakHashMap<Activity, Boolean>())
    private val closeableFullScreenAdActivityNames = linkedSetOf(
        "com.google.android.gms.ads.AdActivity",
        "com.facebook.ads.AudienceNetworkActivity",
        "com.facebook.ads.InterstitialAdActivity",
        "com.applovin.adview.AppLovinFullscreenActivity",
        "com.bytedance.sdk.openadsdk.activity.TTFullScreenVideoActivity",
        "com.bytedance.sdk.openadsdk.activity.TTFullScreenExpressVideoActivity",
        "com.bytedance.sdk.openadsdk.activity.TTInterstitialActivity",
        "com.bytedance.sdk.openadsdk.activity.TTInterstitialExpressActivity",
        "com.bytedance.sdk.openadsdk.activity.TTRewardVideoActivity",
        "com.bytedance.sdk.openadsdk.activity.TTRewardExpressVideoActivity",
        "com.vungle.warren.ui.VungleActivity",
        "com.vungle.warren.ui.VungleFlexViewActivity",
        "com.vungle.ads.internal.ui.VungleActivity",
        "com.unity3d.services.ads.adunit.AdUnitActivity",
        "com.unity3d.services.ads.adunit.AdUnitTransparentActivity",
        "com.unity3d.services.ads.adunit.AdUnitSoftwareActivity",
        "com.unity3d.services.ads.adunit.AdUnitTransparentSoftwareActivity",
        "com.ironsource.sdk.controller.ControllerActivity",
        "com.ironsource.sdk.controller.InterstitialActivity",
        "com.ironsource.sdk.controller.OpenUrlActivity",
        "com.mbridge.msdk.reward.player.MBRewardVideoActivity",
        "com.mbridge.msdk.newreward.player.MBRewardVideoActivity",
        "com.mbridge.msdk.interstitial.view.MBInterstitialActivity",
        "com.mbridge.msdk.newinterstitial.view.MBNewInterstitialActivity",
        "com.mbridge.msdk.activity.MBCommonActivity",
        "com.mbridge.msdk.out.LoadingActivity",
        "com.mbridge.msdk.interactiveads.activity.InteractiveShowActivity",
        "com.mbridge.msdk.mbsignalcommon.mraid.MraidActivity",
        "com.mbridge.msdk.mbsignalcommon.webEnvCheck.WebGLCheckActivity"
    )
    private val activityLifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
            trackAdActivity(activity)
        }

        override fun onActivityStarted(activity: Activity) {
            trackAdActivity(activity)
        }

        override fun onActivityResumed(activity: Activity) {
            trackAdActivity(activity)
        }

        override fun onActivityPaused(activity: Activity) = Unit

        override fun onActivityStopped(activity: Activity) = Unit

        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

        override fun onActivityDestroyed(activity: Activity) {
            activeActivities.remove(activity)
            adActivities.remove(activity)
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        applicationContext = flutterPluginBinding.applicationContext
        application = flutterPluginBinding.applicationContext as? Application
        application?.registerActivityLifecycleCallbacks(activityLifecycleCallbacks)
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
            "closeFullScreenAd" -> {
                result.success(closeFullScreenAd())
            }
            "updateCloseableFullScreenAdActivityNames" -> {
                val activityNames =
                    call.argument<List<String>>("activityNames") ?: emptyList()
                updateCloseableFullScreenAdActivityNames(activityNames)
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        unregisterNativeAdFactories(binding)
        application?.unregisterActivityLifecycleCallbacks(activityLifecycleCallbacks)
        application = null
        activeActivities.clear()
        adActivities.clear()
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

    private fun trackAdActivity(activity: Activity) {
        activeActivities.add(activity)
        if (isCloseableFullScreenAdActivity(activity)) {
            adActivities.add(activity)
        }
    }

    private fun closeFullScreenAd(): Boolean {
        var closed = false
        val closeTargets = (adActivities.toList() + activeActivities.toList())
            .distinct()
            .filter(::isCloseableFullScreenAdActivity)
        closeTargets.forEach { activity ->
            if (!activity.isFinishing && !activity.isDestroyed) {
                activity.finish()
                closed = true
            }
        }
        return closed
    }

    private fun updateCloseableFullScreenAdActivityNames(activityNames: List<String>) {
        activityNames
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .forEach { closeableFullScreenAdActivityNames.add(it) }
        activeActivities
            .filter(::isCloseableFullScreenAdActivity)
            .forEach { adActivities.add(it) }
    }

    private fun isCloseableFullScreenAdActivity(activity: Activity): Boolean {
        val activityClass = activity.javaClass
        val className = activityClass.name
        if (closeableFullScreenAdActivityNames.contains(className)) {
            return true
        }
        return closeableFullScreenAdActivityNames.any { closeableName ->
            runCatching {
                Class.forName(closeableName).isAssignableFrom(activityClass)
            }.getOrDefault(false)
        }
    }

    companion object {
        const val GUIDE_COMPACT_NATIVE_FACTORY_ID = "guide_compact_native"
        const val FULL_SCREEN_NATIVE_FACTORY_ID = "full_screen_native"
    }
}
