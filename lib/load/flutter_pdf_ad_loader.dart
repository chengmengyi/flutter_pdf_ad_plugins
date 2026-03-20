import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../bean/ad_info_bean.dart';
import '../enum/ad_type.dart';
import 'loaded_ad_cache_entry.dart';

const Duration _requestFallbackDelay = Duration(seconds: 3);

class FlutterPdfAdLoader<K> {
  FlutterPdfAdLoader({
    Map<K, List<AdInfoBean>> initialConfigs = const {},
    AdRequest? defaultAdRequest,
    AdSize? bannerSize,
    NativeTemplateStyle? nativeTemplateStyle,
    String Function(K placement)? placementLabelBuilder,
  }) : _defaultAdRequest = defaultAdRequest ?? const AdRequest(),
       _bannerSize = bannerSize ?? AdSize.banner,
       _nativeTemplateStyle =
           nativeTemplateStyle ??
           NativeTemplateStyle(templateType: TemplateType.medium),
       _placementLabelBuilder = placementLabelBuilder {
    updateConfigs(initialConfigs);
  }

  final AdRequest _defaultAdRequest;
  final AdSize _bannerSize;
  final NativeTemplateStyle _nativeTemplateStyle;
  final String Function(K placement)? _placementLabelBuilder;

  final Map<K, List<AdInfoBean>> _configs = {};
  final Map<K, LoadedAdCacheEntry> _cacheMap = {};
  final Map<K, Future<LoadedAdCacheEntry?>> _loadingTasks = {};

  Map<K, List<AdInfoBean>> get configs => Map.unmodifiable(_configs);

  Map<K, LoadedAdCacheEntry> get cacheMap => Map.unmodifiable(_cacheMap);

  void updateConfigs(Map<K, List<AdInfoBean>> configs) {
    _configs
      ..clear()
      ..addAll(
        configs.map(
          (key, value) => MapEntry(key, List<AdInfoBean>.unmodifiable(value)),
        ),
      );
  }

  void updatePlacementConfig(K placement, List<AdInfoBean> configs) {
    _configs[placement] = List<AdInfoBean>.unmodifiable(configs);
  }

  Future<LoadedAdCacheEntry?> loadPlacement(
    K placement, {
    List<AdInfoBean>? configs,
    bool force = false,
  }) async {
    final inFlight = _loadingTasks[placement];
    if (inFlight != null) {
      return inFlight;
    }

    if (!force) {
      final cacheExpired = await _evictExpiredCacheIfNeeded(
        placement,
        reloadOnExpire: false,
      );
      if (cacheExpired) {
        _logCacheExpired(placement, trigger: 'load');
      }

      final cachedEntry = _cacheMap[placement];
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

  Future<void> preloadAll({Iterable<K>? placements, bool force = false}) async {
    final targets = placements ?? _configs.keys;
    await Future.wait(
      targets.map((placement) => loadPlacement(placement, force: force)),
    );
  }

  Future<LoadedAdCacheEntry?> getCachedEntry(K placement) async {
    final cacheExpired = await _evictExpiredCacheIfNeeded(
      placement,
      reloadOnExpire: false,
    );
    if (cacheExpired) {
      _logCacheExpired(placement, trigger: 'read');
      return null;
    }
    return _cacheMap[placement];
  }

  Future<Ad?> getCachedAd(K placement) async {
    return (await getCachedEntry(placement))?.ad;
  }

  Future<Widget?> buildCachedAdWidget(K placement) async {
    final ad = await getCachedAd(placement);
    if (ad is AdWithView) {
      return AdWidget(ad: ad);
    }
    return null;
  }

  Future<bool> showCachedAd(
    K placement, {
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    final cacheExpired = await _evictExpiredCacheIfNeeded(
      placement,
      reloadOnExpire: true,
    );
    if (cacheExpired) {
      _logCacheExpired(placement, trigger: 'show');
      return false;
    }

    final entry = _cacheMap[placement];
    if (entry == null) {
      return false;
    }

    final ad = entry.ad;
    if (ad is AppOpenAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
        onAdDismissedFullScreenContent: (_) {
          unawaited(_reloadPlacementAfterShow(placement));
        },
        onAdFailedToShowFullScreenContent: (_, __) {
          unawaited(_reloadPlacementAfterShow(placement));
        },
      );
      await ad.show();
      return true;
    }

    if (ad is InterstitialAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
        onAdDismissedFullScreenContent: (_) {
          unawaited(_reloadPlacementAfterShow(placement));
        },
        onAdFailedToShowFullScreenContent: (_, __) {
          unawaited(_reloadPlacementAfterShow(placement));
        },
      );
      await ad.show();
      return true;
    }

    if (ad is RewardedAd) {
      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdDismissedFullScreenContent: (_) {
          unawaited(_reloadPlacementAfterShow(placement));
        },
        onAdFailedToShowFullScreenContent: (_, __) {
          unawaited(_reloadPlacementAfterShow(placement));
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

  Future<bool> loadAndShow(
    K placement, {
    List<AdInfoBean>? configs,
    bool forceReload = false,
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    final cachedShown = await showCachedAd(
      placement,
      onUserEarnedReward: onUserEarnedReward,
    );
    if (cachedShown && !forceReload) {
      return true;
    }

    final entry = await loadPlacement(
      placement,
      configs: configs,
      force: forceReload,
    );
    if (entry == null) {
      return false;
    }

    return showCachedAd(placement, onUserEarnedReward: onUserEarnedReward);
  }

  Future<void> clearPlacementCache(K placement) async {
    final entry = _cacheMap.remove(placement);
    if (entry != null) {
      await entry.dispose();
    }
  }

  Future<void> _reloadPlacementAfterShow(K placement) async {
    await clearPlacementCache(placement);
    _logCacheReload(placement, trigger: 'close');
    await loadPlacement(placement, force: true);
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
    K placement,
    List<AdInfoBean> configs,
  ) async {
    final sortedConfigs =
        configs
            .where(
              (config) => config.adId != null && config.parsedAdType != null,
            )
            .toList(growable: false)
          ..sort((left, right) => (right.sort ?? 0).compareTo(left.sort ?? 0));

    if (sortedConfigs.isEmpty) {
      await clearPlacementCache(placement);
      return null;
    }

    final completer = Completer<LoadedAdCacheEntry?>();
    final startedIndexes = <int>{};
    final completedIndexes = <int>{};
    final timers = <Timer>[];
    var winnerChosen = false;
    var activeLoads = 0;

    Future<void> tryCompleteNoFill() async {
      if (winnerChosen || completer.isCompleted) {
        return;
      }

      final allStarted = startedIndexes.length == sortedConfigs.length;
      if (!allStarted || activeLoads > 0) {
        return;
      }

      await clearPlacementCache(placement);
      completer.complete(null);
    }

    Future<void> startLoadAt(int index) async {
      if (winnerChosen || index >= sortedConfigs.length) {
        return;
      }
      if (!startedIndexes.add(index)) {
        return;
      }

      final config = sortedConfigs[index];
      _logLoadStart(placement, config);
      activeLoads++;

      if (index + 1 < sortedConfigs.length) {
        final timer = Timer(_requestFallbackDelay, () {
          if (winnerChosen || completedIndexes.contains(index)) {
            return;
          }
          unawaited(startLoadAt(index + 1));
        });
        timers.add(timer);
      }

      final ad = await _loadAd(config);
      completedIndexes.add(index);
      activeLoads--;

      if (winnerChosen) {
        if (ad != null) {
          await ad.dispose();
        }
        await tryCompleteNoFill();
        return;
      }

      if (ad == null) {
        _logLoadFailure(placement, config);
        if (index + 1 < sortedConfigs.length) {
          await startLoadAt(index + 1);
        }
        await tryCompleteNoFill();
        return;
      }

      winnerChosen = true;
      for (final timer in timers) {
        timer.cancel();
      }

      final entry = LoadedAdCacheEntry(
        info: config,
        ad: ad,
        cachedAt: DateTime.now(),
      );
      await _replaceCache(placement, entry);
      _logLoadSuccess(placement, entry);
      completer.complete(entry);
    }

    unawaited(startLoadAt(0));
    return completer.future;
  }

  Future<void> _replaceCache(K placement, LoadedAdCacheEntry nextEntry) async {
    final previousEntry = _cacheMap[placement];
    if (previousEntry != null) {
      await previousEntry.dispose();
    }
    _cacheMap[placement] = nextEntry;
  }

  Future<bool> _evictExpiredCacheIfNeeded(
    K placement, {
    required bool reloadOnExpire,
  }) async {
    final entry = _cacheMap[placement];
    if (entry == null || !entry.isExpired) {
      return false;
    }

    await clearPlacementCache(placement);
    if (reloadOnExpire) {
      unawaited(loadPlacement(placement, force: true));
    }
    return true;
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

  void _logLoadStart(K placement, AdInfoBean info) {
    _log('load-start', placement, info: info);
  }

  void _logLoadFailure(K placement, AdInfoBean info) {
    _log('load-failed', placement, info: info);
  }

  void _logLoadSuccess(K placement, LoadedAdCacheEntry entry) {
    _log(
      'load-success',
      placement,
      info: entry.info,
      extra:
          'loadedAt=${entry.cachedAt.toIso8601String()} '
          'expireAt=${entry.expireAt?.toIso8601String() ?? 'never'} '
          'adClass=${entry.ad.runtimeType}',
    );
  }

  void _logCacheExpired(K placement, {required String trigger}) {
    if (kReleaseMode) {
      return;
    }

    debugPrint(
      '[FlutterPdfAdLoader] cache-expired placement=${_placementLabel(placement)} '
      'trigger=$trigger',
    );
  }

  void _logCacheReload(K placement, {required String trigger}) {
    if (kReleaseMode) {
      return;
    }

    debugPrint(
      '[FlutterPdfAdLoader] reload-after-show placement=${_placementLabel(placement)} '
      'trigger=$trigger',
    );
  }

  void _log(
    String stage,
    K placement, {
    required AdInfoBean info,
    String? extra,
  }) {
    if (kReleaseMode) {
      return;
    }

    final buffer = StringBuffer()
      ..write('[FlutterPdfAdLoader] ')
      ..write(stage)
      ..write(' placement=')
      ..write(_placementLabel(placement))
      ..write(' adInfo={')
      ..write(info.logSummary)
      ..write('}');

    if (extra != null && extra.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(extra);
    }

    debugPrint(buffer.toString());
  }

  String _placementLabel(K placement) {
    return _placementLabelBuilder?.call(placement) ?? placement.toString();
  }
}
