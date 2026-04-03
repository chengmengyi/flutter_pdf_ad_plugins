package com.pdf.ad.flutter_pdf_ad_plugins

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class GuideCompactNativeAdFactory(
    private val context: Context
) : GoogleMobileAdsPlugin.NativeAdFactory {

    var layoutName: String? = null

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val inflater = LayoutInflater.from(context)
        val resolvedLayoutName = layoutName?.trim().orEmpty()
        require(resolvedLayoutName.isNotEmpty()) {
            "Missing configured layout name for compact native ad"
        }
        val layoutId = context.resources.getIdentifier(
            resolvedLayoutName,
            "layout",
            context.packageName
        )
        require(layoutId != 0) {
            "Missing layout resource: $resolvedLayoutName"
        }
        val adView = inflater.inflate(layoutId, null) as NativeAdView

        val iconView = adView.findViewById<ImageView?>(id("ad_app_icon"))
        val headlineView = adView.findViewById<TextView?>(id("ad_headline"))
        val bodyView = adView.findViewById<TextView?>(id("ad_body"))
        val ctaView = adView.findViewById<TextView?>(id("ad_call_to_action"))

        if (iconView != null) {
            adView.iconView = iconView
            if (nativeAd.icon?.drawable != null) {
                iconView.setImageDrawable(nativeAd.icon?.drawable)
                iconView.visibility = View.VISIBLE
            } else {
                iconView.visibility = View.INVISIBLE
            }
        }

        if (headlineView != null) {
            adView.headlineView = headlineView
            headlineView.text = nativeAd.headline ?: ""
        }

        if (bodyView != null) {
            adView.bodyView = bodyView
            val secondaryText = nativeAd.body
                ?: nativeAd.advertiser
                ?: nativeAd.store
                ?: ""
            if (secondaryText.isBlank()) {
                bodyView.visibility = View.INVISIBLE
            } else {
                bodyView.text = secondaryText
                bodyView.visibility = View.VISIBLE
            }
        }

        if (ctaView != null) {
            adView.callToActionView = ctaView
            val ctaText = nativeAd.callToAction ?: "Install"
            ctaView.text = ctaText
            ctaView.visibility = View.VISIBLE
        }

        adView.setNativeAd(nativeAd)
        return adView
    }

    private fun id(name: String): Int {
        return context.resources.getIdentifier(name, "id", context.packageName)
    }
}
