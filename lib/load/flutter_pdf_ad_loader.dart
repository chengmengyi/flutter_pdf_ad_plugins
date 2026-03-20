import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../bean/ad_info_bean.dart';
import '../enum/ad_placement.dart';
import '../enum/ad_type.dart';
import 'loaded_ad_cache_entry.dart';

class FlutterPdfAdLoader {
  FlutterPdfAdLoader({
    Map<AdPlacement, List<AdInfoBean>> initialConfigs = const {},
    AdRequest? defaultAdRequest,
    AdSize? bannerSize,
    NativeTemplateStyle? nativeTemplateStyle,
  }) : _defaultAdRequest = defaultAdRequest ?? const AdRequest(),
       _bannerSize = bannerSize ?? AdSize.banner,
       _nativeTemplateStyle =
           nativeTemplateStyle ??
           NativeTemplateStyle(templateType: TemplateType.medium) {
    updateConfigs(initialConfigs);
  }

  final AdRequest _defaultAdRequest;
  final AdSize _bannerSize;
  final NativeTemplateStyle _nativeTemplateStyle;

  final Map<AdPlacement, List<AdInfoBean>> _configs = {};
  final Map<AdPlacement, LoadedAdCacheEntry> _cacheMap = {};
  final Map<AdPlacement, Future<LoadedAdCacheEntry?>> _loadingTasks = {};

  Map<AdPlacement, List<AdInfoBean>> get configs => Map.unmodifiable(_configs);

  Map<AdPlacement, LoadedAdCacheEntry> get cacheMap =>
      Map.unmodifiable(_cacheMap);

  void updateConfigs(Map<AdPlacement, List<AdInfoBean>> configs) {
    _configs
      ..clear()
      ..addAll(
        configs.map(
          (key, value) => MapEntry(key, List<AdInfoBean>.unmodifiable(value)),
        ),
      );
  }

  void updatePlacementConfig(AdPlacement placement, List<AdInfoBean> configs) {
    _configs[placement] = List<AdInfoBean>.unmodifiable(configs);
  }

  Future<LoadedAdCacheEntry?> loadPlacement(
    AdPlacement placement, {
    List<AdInfoBean>? configs,
    bool force = false,
  }) async {
    final inFlight = _loadingTasks[placement];
    if (inFlight != null) {
      return inFlight;
    }

    if (!force) {
      final cachedEntry = await getCachedEntry(placement);
      if (cachedEntry != null) {
        return cachedEntry;
      }
    }

    final placementConfigs =
        configs ?? _configs[placement] ?? const <AdInfoBean>[];
    final future = _loadPlacementInternal(placement, placementConfigs);
    _loadingTasks[placement] = future;

    try {
      return await future;
    } finally {
      _loadingTasks.remove(placement);
    }
  }

  Future<void> preloadAll({
    Iterable<AdPlacement>? placements,
    bool force = false,
  }) async {
    final targets = placements ?? _configs.keys;
    await Future.wait(
      targets.map((placement) => loadPlacement(placement, force: force)),
    );
  }

  Future<LoadedAdCacheEntry?> getCachedEntry(AdPlacement placement) async {
    final entry = _cacheMap[placement];
    if (entry == null) {
      return null;
    }
    if (!entry.isExpired) {
      return entry;
    }
    await clearPlacementCache(placement);
    return null;
  }

  Future<Ad?> getCachedAd(AdPlacement placement) async {
    return (await getCachedEntry(placement))?.ad;
  }

  Future<Widget?> buildCachedAdWidget(AdPlacement placement) async {
    final ad = await getCachedAd(placement);
    if (ad is AdWithView) {
      return AdWidget(ad: ad);
    }
    return null;
  }

  Future<bool> showCachedAd(
    AdPlacement placement, {
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    final entry = await getCachedEntry(placement);
    if (entry == null) {
      return false;
    }

    final ad = entry.ad;
    if (ad is AppOpenAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
        onAdDismissedFullScreenContent: (_) {
          unawaited(clearPlacementCache(placement));
        },
        onAdFailedToShowFullScreenContent: (_, __) {
          unawaited(clearPlacementCache(placement));
        },
      );
      await ad.show();
      return true;
    }

    if (ad is InterstitialAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
        onAdDismissedFullScreenContent: (_) {
          unawaited(clearPlacementCache(placement));
        },
        onAdFailedToShowFullScreenContent: (_, __) {
          unawaited(clearPlacementCache(placement));
        },
      );
      await ad.show();
      return true;
    }

    if (ad is RewardedAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdDismissedFullScreenContent: (_) {
          unawaited(clearPlacementCache(placement));
        },
        onAdFailedToShowFullScreenContent: (_, __) {
          unawaited(clearPlacementCache(placement));
        },
      );
      await ad.show(
        onUserEarnedReward:
            onUserEarnedReward ??
            (_, __) {
              // No-op when caller does not need reward callbacks.
            },
      );
      return true;
    }

    return false;
  }

  Future<void> clearPlacementCache(AdPlacement placement) async {
    final entry = _cacheMap.remove(placement);
    if (entry != null) {
      await entry.dispose();
    }
  }

  Future<void> dispose() async {
    final placements = _cacheMap.keys.toList(growable: false);
    for (final placement in placements) {
      await clearPlacementCache(placement);
    }
    _configs.clear();
    _loadingTasks.clear();
  }

  Future<LoadedAdCacheEntry?> _loadPlacementInternal(
    AdPlacement placement,
    List<AdInfoBean> configs,
  ) async {
    final sortedConfigs =
        configs
            .where(
              (config) => config.adId != null && config.parsedAdType != null,
            )
            .toList(growable: false)
          ..sort((left, right) => (right.sort ?? 0).compareTo(left.sort ?? 0));

    for (final config in sortedConfigs) {
      final ad = await _loadAd(config);
      if (ad == null) {
        continue;
      }

      final entry = LoadedAdCacheEntry(
        info: config,
        ad: ad,
        cachedAt: DateTime.now(),
      );
      await _replaceCache(placement, entry);
      return entry;
    }

    await clearPlacementCache(placement);
    return null;
  }

  Future<void> _replaceCache(
    AdPlacement placement,
    LoadedAdCacheEntry nextEntry,
  ) async {
    final previousEntry = _cacheMap[placement];
    if (previousEntry != null) {
      await previousEntry.dispose();
    }
    _cacheMap[placement] = nextEntry;
  }

  Future<Ad?> _loadAd(AdInfoBean info) async {
    final adType = info.parsedAdType;
    final adId = info.adId;
    if (adType == null || adId == null || adId.isEmpty) {
      return null;
    }

    switch (adType) {
      case AdType.appOpen:
        return _loadAppOpenAd(adId);
      case AdType.interstitial:
        return _loadInterstitialAd(adId);
      case AdType.native:
        return _loadNativeAd(adId);
      case AdType.rewarded:
        return _loadRewardedAd(adId);
      case AdType.banner:
        return _loadBannerAd(adId);
    }
  }

  Future<Ad?> _loadAppOpenAd(String adId) async {
    final completer = Completer<Ad?>();
    try {
      await AppOpenAd.load(
        adUnitId: adId,
        request: _defaultAdRequest,
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            if (!completer.isCompleted) {
              completer.complete(ad);
            }
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          },
        ),
      );
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    return completer.future;
  }

  Future<Ad?> _loadInterstitialAd(String adId) async {
    final completer = Completer<Ad?>();
    try {
      await InterstitialAd.load(
        adUnitId: adId,
        request: _defaultAdRequest,
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (!completer.isCompleted) {
              completer.complete(ad);
            }
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          },
        ),
      );
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    return completer.future;
  }

  Future<Ad?> _loadRewardedAd(String adId) async {
    final completer = Completer<Ad?>();
    try {
      await RewardedAd.load(
        adUnitId: adId,
        request: _defaultAdRequest,
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (!completer.isCompleted) {
              completer.complete(ad);
            }
          },
          onAdFailedToLoad: (_) {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          },
        ),
      );
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    return completer.future;
  }

  Future<Ad?> _loadBannerAd(String adId) async {
    final completer = Completer<Ad?>();
    final ad = BannerAd(
      size: _bannerSize,
      adUnitId: adId,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!completer.isCompleted) {
            completer.complete(ad);
          }
        },
        onAdFailedToLoad: (ad, _) async {
          await ad.dispose();
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      ),
      request: _defaultAdRequest,
    );

    try {
      await ad.load();
    } catch (_) {
      await ad.dispose();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }

    return completer.future;
  }

  Future<Ad?> _loadNativeAd(String adId) async {
    final completer = Completer<Ad?>();
    final ad = NativeAd(
      adUnitId: adId,
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!completer.isCompleted) {
            completer.complete(ad);
          }
        },
        onAdFailedToLoad: (ad, _) async {
          await ad.dispose();
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      ),
      request: _defaultAdRequest,
      nativeTemplateStyle: _nativeTemplateStyle,
    );

    try {
      await ad.load();
    } catch (_) {
      await ad.dispose();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }

    return completer.future;
  }
}
