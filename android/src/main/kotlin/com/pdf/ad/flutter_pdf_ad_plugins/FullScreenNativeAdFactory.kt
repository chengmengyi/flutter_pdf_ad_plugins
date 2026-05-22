package com.pdf.ad.flutter_pdf_ad_plugins

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class FullScreenNativeAdFactory(
    private val context: Context
) : GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.fpad_full_screen_native_ad, null) as NativeAdView

        val mediaView = adView.findViewById<MediaView>(R.id.fpad_ad_media)
        val headlineView = adView.findViewById<TextView>(R.id.fpad_ad_headline)
        val bodyView = adView.findViewById<TextView>(R.id.fpad_ad_body)
        val ctaView = adView.findViewById<Button>(R.id.fpad_ad_call_to_action)

        adView.mediaView = mediaView
        adView.headlineView = headlineView
        adView.bodyView = bodyView
        adView.callToActionView = ctaView

        bindAssets(adView, nativeAd, headlineView, bodyView, ctaView)
        adView.setNativeAd(nativeAd)
        return adView
    }

    private fun bindAssets(
        adView: NativeAdView,
        nativeAd: NativeAd,
        headlineView: TextView,
        bodyView: TextView,
        ctaView: Button
    ) {
        headlineView.text = nativeAd.headline.orEmpty()

        val secondaryText = nativeAd.body
            ?: nativeAd.advertiser
            ?: nativeAd.store
            ?: ""
        if (secondaryText.isBlank()) {
            bodyView.visibility = View.GONE
        } else {
            bodyView.text = secondaryText
            bodyView.visibility = View.VISIBLE
        }

        ctaView.text = nativeAd.callToAction ?: "Open"
        ctaView.visibility = View.VISIBLE
        adView.callToActionView = ctaView
    }
}
