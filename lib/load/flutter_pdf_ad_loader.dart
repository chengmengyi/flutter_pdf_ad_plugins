// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart'
    show instanceManager;

import '../bean/ad_info_bean.dart';
import '../enum/ad_type.dart';
import 'loaded_ad_cache_entry.dart';

const Duration _requestFallbackDelay = Duration(seconds: 3);
const String _fallbackAdNetwork = 'Admob';

class FlutterPdfAdLoader<K> {
  FlutterPdfAdLoader({
    Map<K, List<AdInfoBean>> initialConfigs = const {},
    AdRequest? defaultAdRequest,
    AdSize? bannerSize,
    AdSize? Function(K placement)? bannerSizeBuilder,
    AdRequest? Function(K placement, AdRequest defaultRequest)?
    adRequestBuilder,
    String? Function(K placement)? nativeAdFactoryIdBuilder,
    NativeAdOptions? Function(K placement)? nativeAdOptionsBuilder,
    NativeTemplateStyle? nativeTemplateStyle,
    NativeTemplateStyle? Function(K placement)? nativeTemplateStyleBuilder,
    void Function(K placement, LoadedAdCacheEntry entry)? onPlacementLoaded,
    void Function(K placement, AdInfoBean info)? onAdRequestStart,
    void Function(
      K placement,
      AdInfoBean info,
      String adNetwork,
      String adSourceName,
    )?
    onAdRequestSuccess,
    void Function(
      K placement,
      AdInfoBean info,
      String failReason,
      String adNetwork,
      String adSourceName,
    )?
    onAdRequestFailure,
    void Function(
      K placement,
      AdInfoBean info,
      String adNetwork,
      String adSourceName,
    )?
    onAdShowStart,
    void Function(
      K placement,
      AdInfoBean info,
      String adNetwork,
      String adSourceName,
    )?
    onAdShowed,
    void Function(
      K placement,
      AdInfoBean info,
      String adNetwork,
      String adSourceName,
    )?
    onAdClicked,
    void Function(
      K placement,
      AdInfoBean info,
      String adNetwork,
      String adSourceName,
    )?
    onAdClosed,
    String Function(K placement)? placementLabelBuilder,
    void Function(
      K placement,
      AdInfoBean info,
      Ad ad,
      double valueMicros,
      PrecisionType precision,
      String currencyCode,
    )?
    onPaidEvent,
  }) : _defaultAdRequest = defaultAdRequest ?? const AdRequest(),
       _bannerSize = bannerSize ?? AdSize.banner,
       _bannerSizeBuilder = bannerSizeBuilder,
       _adRequestBuilder = adRequestBuilder,
       _nativeAdFactoryIdBuilder = nativeAdFactoryIdBuilder,
       _nativeAdOptionsBuilder = nativeAdOptionsBuilder,
       _nativeTemplateStyle =
           nativeTemplateStyle ??
           NativeTemplateStyle(templateType: TemplateType.medium),
       _nativeTemplateStyleBuilder = nativeTemplateStyleBuilder,
       _onPlacementLoaded = onPlacementLoaded,
       _onAdRequestStart = onAdRequestStart,
       _onAdRequestSuccess = onAdRequestSuccess,
       _onAdRequestFailure = onAdRequestFailure,
       _onAdShowStart = onAdShowStart,
       _onAdShowed = onAdShowed,
       _onAdClicked = onAdClicked,
       _onAdClosed = onAdClosed,
       _placementLabelBuilder = placementLabelBuilder,
       _onPaidEvent = onPaidEvent {
    updateConfigs(initialConfigs);
  }

  final AdRequest _defaultAdRequest;
  final AdSize _bannerSize;
  final AdSize? Function(K placement)? _bannerSizeBuilder;
  final AdRequest? Function(K placement, AdRequest defaultRequest)?
  _adRequestBuilder;
  final String? Function(K placement)? _nativeAdFactoryIdBuilder;
  final NativeAdOptions? Function(K placement)? _nativeAdOptionsBuilder;
  final NativeTemplateStyle _nativeTemplateStyle;
  final NativeTemplateStyle? Function(K placement)? _nativeTemplateStyleBuilder;
  final void Function(K placement, LoadedAdCacheEntry entry)?
  _onPlacementLoaded;
  final void Function(K placement, AdInfoBean info)? _onAdRequestStart;
  final void Function(
    K placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  )?
  _onAdRequestSuccess;
  final void Function(
    K placement,
    AdInfoBean info,
    String failReason,
    String adNetwork,
    String adSourceName,
  )?
  _onAdRequestFailure;
  final void Function(
    K placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  )?
  _onAdShowStart;
  final void Function(
    K placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  )?
  _onAdShowed;
  final void Function(
    K placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  )?
  _onAdClicked;
  final void Function(
    K placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  )?
  _onAdClosed;
  final String Function(K placement)? _placementLabelBuilder;
  final void Function(
    K placement,
    AdInfoBean info,
    Ad ad,
    double valueMicros,
    PrecisionType precision,
    String currencyCode,
  )?
  _onPaidEvent;

  final Map<K, List<AdInfoBean>> _configs = {};
  final Map<K, List<LoadedAdCacheEntry>> _cacheMap = {};
  final Map<K, Future<LoadedAdCacheEntry?>> _loadingTasks = {};
  final Map<K, int> _activeRequestCounts = {};
  final Set<K> _skipReloadAfterClosePlacements = <K>{};
  final Set<K> _singleFillPlacements = <K>{};

  Map<K, List<AdInfoBean>> get configs => Map.unmodifiable(_configs);

  Map<K, LoadedAdCacheEntry> get cacheMap {
    return Map<K, LoadedAdCacheEntry>.unmodifiable(
      _cacheMap.map((key, value) => MapEntry(key, value.first)),
    );
  }

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

  void updateSkipReloadAfterClosePlacements(Iterable<K> placements) {
    _skipReloadAfterClosePlacements
      ..clear()
      ..addAll(placements);
  }

  void updateSingleFillPlacements(Iterable<K> placements) {
    _singleFillPlacements
      ..clear()
      ..addAll(placements);
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

    final cacheExpired = await _evictExpiredCacheIfNeeded(
      placement,
      reloadOnExpire: false,
    );
    if (cacheExpired) {
      _logCacheExpired(placement, trigger: 'load');
    }

    final cachedEntry = _cacheMap[placement];
    if (cachedEntry != null && cachedEntry.isNotEmpty) {
      return cachedEntry.first;
    }

    final latestInFlight = _loadingTasks[placement];
    if (latestInFlight != null) {
      return latestInFlight;
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
    await _evictExpiredCacheIfNeeded(placement, reloadOnExpire: false);
    final entries = _cacheMap[placement];
    if (entries == null || entries.isEmpty) {
      return null;
    }
    return entries.first;
  }

  Future<Ad?> getCachedAd(K placement) async {
    return (await getCachedEntry(placement))?.ad;
  }

  Future<LoadedAdCacheEntry?> takeCachedEntry(
    K placement, {
    bool reloadAfterTake = false,
  }) async {
    await _evictExpiredCacheIfNeeded(placement, reloadOnExpire: false);
    final entries = _cacheMap[placement];
    if (entries == null || entries.isEmpty) {
      return null;
    }
    final entry = entries.removeAt(0);
    if (entries.isEmpty) {
      _cacheMap.remove(placement);
    }
    if (reloadAfterTake) {
      unawaited(loadPlacement(placement, force: true));
    }
    return entry;
  }

  Future<Widget?> buildCachedAdWidget(K placement) async {
    final ad = await getCachedAd(placement);
    if (ad is AdWithView && instanceManager.adIdFor(ad) != null) {
      return AdWidget(ad: ad);
    }
    return null;
  }

  Future<bool> showCachedAd(
    K placement, {
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    final result = await showCachedAdWithResult(
      placement,
      onUserEarnedReward: onUserEarnedReward,
    );
    return result.shown;
  }

  Future<ShowAdResult> showCachedAdWithResult(
    K placement, {
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    await _evictExpiredCacheIfNeeded(placement, reloadOnExpire: true);

    final entries = _cacheMap[placement];
    final entry = entries == null || entries.isEmpty ? null : entries.first;
    if (entry == null) {
      return const ShowAdResult.failure('no-cached-ad');
    }

    final ad = entry.ad;
    if (ad is AppOpenAd) {
      final completer = Completer<ShowAdResult>();
      ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
        onAdShowedFullScreenContent: (_) {
          _dispatchAdShowed(placement, entry.info, entry.ad);
        },
        onAdDismissedFullScreenContent: (_) async {
          _dispatchAdClosed(placement, entry.info, entry.ad);
          await _consumeShownEntryAfterShow(placement, entry, trigger: 'close');
          if (!completer.isCompleted) {
            completer.complete(const ShowAdResult.success());
          }
        },
        onAdFailedToShowFullScreenContent: (_, error) {
          if (!completer.isCompleted) {
            completer.complete(
              ShowAdResult.failure(
                'code=${error.code} message=${error.message} domain=${error.domain}',
              ),
            );
          }
          unawaited(
            _consumeShownEntryAfterShow(
              placement,
              entry,
              trigger: 'failed-show',
            ),
          );
        },
        onAdClicked: (_) {
          _dispatchAdClicked(placement, entry.info, entry.ad);
        },
      );
      try {
        _dispatchAdShowStart(placement, entry.info, entry.ad);
        await ad.show();
      } catch (error) {
        return ShowAdResult.failure('exception=$error');
      }
      return completer.future;
    }

    if (ad is InterstitialAd) {
      final completer = Completer<ShowAdResult>();
      ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
        onAdShowedFullScreenContent: (_) {
          _dispatchAdShowed(placement, entry.info, entry.ad);
        },
        onAdDismissedFullScreenContent: (_) async {
          _dispatchAdClosed(placement, entry.info, entry.ad);
          await _consumeShownEntryAfterShow(placement, entry, trigger: 'close');
          if (!completer.isCompleted) {
            completer.complete(const ShowAdResult.success());
          }
        },
        onAdFailedToShowFullScreenContent: (_, error) {
          if (!completer.isCompleted) {
            completer.complete(
              ShowAdResult.failure(
                'code=${error.code} message=${error.message} domain=${error.domain}',
              ),
            );
          }
          unawaited(
            _consumeShownEntryAfterShow(
              placement,
              entry,
              trigger: 'failed-show',
            ),
          );
        },
        onAdClicked: (_) {
          _dispatchAdClicked(placement, entry.info, entry.ad);
        },
      );
      try {
        _dispatchAdShowStart(placement, entry.info, entry.ad);
        await ad.show();
      } catch (error) {
        return ShowAdResult.failure('exception=$error');
      }
      return completer.future;
    }

    if (ad is RewardedAd) {
      final completer = Completer<ShowAdResult>();
      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdShowedFullScreenContent: (_) {
          _dispatchAdShowed(placement, entry.info, entry.ad);
        },
        onAdDismissedFullScreenContent: (_) async {
          _dispatchAdClosed(placement, entry.info, entry.ad);
          await _consumeShownEntryAfterShow(placement, entry, trigger: 'close');
          if (!completer.isCompleted) {
            completer.complete(const ShowAdResult.success());
          }
        },
        onAdFailedToShowFullScreenContent: (_, error) {
          if (!completer.isCompleted) {
            completer.complete(
              ShowAdResult.failure(
                'code=${error.code} message=${error.message} domain=${error.domain}',
              ),
            );
          }
          unawaited(
            _consumeShownEntryAfterShow(
              placement,
              entry,
              trigger: 'failed-show',
            ),
          );
        },
        onAdClicked: (_) {
          _dispatchAdClicked(placement, entry.info, entry.ad);
        },
      );
      try {
        _dispatchAdShowStart(placement, entry.info, entry.ad);
        await ad.show(
          onUserEarnedReward:
              onUserEarnedReward ??
              (_, __) {
                // No-op when caller does not need reward callbacks.
              },
        );
      } catch (error) {
        return ShowAdResult.failure('exception=$error');
      }
      return completer.future;
    }

    return ShowAdResult.failure('unsupported-ad-class=${ad.runtimeType}');
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
    final entries = _cacheMap.remove(placement);
    if (entries != null) {
      for (final entry in entries) {
        await entry.dispose();
      }
    }
  }

  Future<void> consumeShownEntryAfterClose(
    K placement,
    LoadedAdCacheEntry entry,
  ) {
    return _consumeShownEntryAfterShow(placement, entry, trigger: 'close');
  }

  Future<void> dispose() async {
    final placements = _cacheMap.keys.toList(growable: false);
    for (final placement in placements) {
      await clearPlacementCache(placement);
    }
    _configs.clear();
    _loadingTasks.clear();
    _activeRequestCounts.clear();
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
    var hasSuccessfulFill = false;

    bool allDone() =>
        completedIndexes.length == sortedConfigs.length &&
        startedIndexes.length == sortedConfigs.length;

    Future<void> tryCompleteNoFill() async {
      if (completer.isCompleted) {
        return;
      }
      if (!allDone()) {
        return;
      }
      if ((_cacheMap[placement]?.isNotEmpty ?? false)) {
        return;
      }
      await clearPlacementCache(placement);
      completer.complete(null);
    }

    Future<void> startLoadAt(int index) async {
      if (index >= sortedConfigs.length) {
        return;
      }
      if (!startedIndexes.add(index)) {
        return;
      }

      final config = sortedConfigs[index];
      _logLoadStart(placement, config);
      _activeRequestCounts[placement] =
          (_activeRequestCounts[placement] ?? 0) + 1;

      if (!_singleFillPlacements.contains(placement) &&
          index + 1 < sortedConfigs.length) {
        final timer = Timer(_requestFallbackDelay, () {
          if (completedIndexes.contains(index)) {
            return;
          }
          unawaited(startLoadAt(index + 1));
        });
        timers.add(timer);
      }

      final result = await _loadAd(placement, config);
      completedIndexes.add(index);
      final nextActiveCount = (_activeRequestCounts[placement] ?? 1) - 1;
      if (nextActiveCount <= 0) {
        _activeRequestCounts.remove(placement);
      } else {
        _activeRequestCounts[placement] = nextActiveCount;
      }

      final ad = result.ad;
      if (ad == null) {
        _logLoadFailure(
          placement,
          config,
          reason: result.failureReason,
          adNetwork: result.adNetwork,
        );
        if (index + 1 < sortedConfigs.length) {
          unawaited(startLoadAt(index + 1));
        }
        await tryCompleteNoFill();
        return;
      }

      final entry = LoadedAdCacheEntry(
        info: config,
        ad: ad,
        cachedAt: DateTime.now(),
        requestOrder: index,
      );
      if (_singleFillPlacements.contains(placement) && hasSuccessfulFill) {
        _log(
          'drop-extra-success',
          placement,
          info: config,
          extra: 'reason=single-fill',
        );
        await entry.dispose();
        await tryCompleteNoFill();
        return;
      }
      hasSuccessfulFill = true;
      await _insertCacheEntry(placement, entry);
      _logLoadSuccess(
        placement,
        entry,
        cacheCount: _cacheMap[placement]?.length ?? 0,
      );
      _onPlacementLoaded?.call(placement, entry);
      if (!completer.isCompleted) {
        completer.complete(entry);
      }
      await tryCompleteNoFill();
    }

    unawaited(startLoadAt(0));
    final firstResult = await completer.future;
    for (final timer in timers) {
      timer.cancel();
    }
    return firstResult;
  }

  Future<void> _insertCacheEntry(
    K placement,
    LoadedAdCacheEntry nextEntry,
  ) async {
    final entries = _cacheMap.putIfAbsent(
      placement,
      () => <LoadedAdCacheEntry>[],
    );
    var insertAt = entries.length;
    for (var index = 0; index < entries.length; index++) {
      if (nextEntry.requestOrder <= entries[index].requestOrder) {
        insertAt = index;
        break;
      }
    }
    entries.insert(insertAt, nextEntry);
  }

  Future<bool> _evictExpiredCacheIfNeeded(
    K placement, {
    required bool reloadOnExpire,
  }) async {
    final entries = _cacheMap[placement];
    if (entries == null || entries.isEmpty) {
      return false;
    }

    final expiredEntries = entries
        .where((entry) => entry.isExpired)
        .toList(growable: false);
    if (expiredEntries.isEmpty) {
      return false;
    }

    for (final expiredEntry in expiredEntries) {
      entries.remove(expiredEntry);
      await expiredEntry.dispose();
    }

    if (entries.isEmpty) {
      _cacheMap.remove(placement);
      if (reloadOnExpire) {
        unawaited(loadPlacement(placement, force: true));
      }
    }
    return true;
  }

  Future<_AdLoadResult> _loadAd(K placement, AdInfoBean info) async {
    final adType = info.parsedAdType;
    final adId = info.adId;
    if (adType == null || adId == null || adId.isEmpty) {
      return const _AdLoadResult.failure('invalid-ad-config');
    }

    switch (adType) {
      case AdType.appOpen:
        return _loadAppOpenAd(placement, info, adId);
      case AdType.interstitial:
        return _loadInterstitialAd(placement, info, adId);
      case AdType.native:
        return _loadNativeAd(placement, info, adId);
      case AdType.rewarded:
        return _loadRewardedAd(placement, info, adId);
      case AdType.banner:
        return _loadBannerAd(placement, info, adId);
    }
  }

  Future<_AdLoadResult> _loadAppOpenAd(
    K placement,
    AdInfoBean info,
    String adId,
  ) async {
    final completer = Completer<_AdLoadResult>();

    void completeFailure(String reason, {String? adNetwork}) {
      if (!completer.isCompleted) {
        completer.complete(_AdLoadResult.failure(reason, adNetwork: adNetwork));
      }
    }

    try {
      await AppOpenAd.load(
        adUnitId: adId,
        request: _defaultAdRequest,
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            if (completer.isCompleted) {
              ad.dispose();
              return;
            }
            ad.onPaidEvent = _buildOnPaidEvent(placement, info);
            completer.complete(_AdLoadResult.success(ad));
          },
          onAdFailedToLoad: (error) {
            completeFailure(
              'code=${error.code} message=${error.message} domain=${error.domain}',
              adNetwork: _resolveResponseInfoAdNetwork(error.responseInfo),
            );
          },
        ),
      );
    } catch (error) {
      completeFailure('exception=$error');
    }
    return completer.future;
  }

  Future<_AdLoadResult> _loadInterstitialAd(
    K placement,
    AdInfoBean info,
    String adId,
  ) async {
    final completer = Completer<_AdLoadResult>();

    void completeFailure(String reason, {String? adNetwork}) {
      if (!completer.isCompleted) {
        completer.complete(_AdLoadResult.failure(reason, adNetwork: adNetwork));
      }
    }

    try {
      await InterstitialAd.load(
        adUnitId: adId,
        request: _defaultAdRequest,
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (completer.isCompleted) {
              ad.dispose();
              return;
            }
            ad.onPaidEvent = _buildOnPaidEvent(placement, info);
            completer.complete(_AdLoadResult.success(ad));
          },
          onAdFailedToLoad: (error) {
            completeFailure(
              'code=${error.code} message=${error.message} domain=${error.domain}',
              adNetwork: _resolveResponseInfoAdNetwork(error.responseInfo),
            );
          },
        ),
      );
    } catch (error) {
      completeFailure('exception=$error');
    }
    return completer.future;
  }

  Future<_AdLoadResult> _loadRewardedAd(
    K placement,
    AdInfoBean info,
    String adId,
  ) async {
    final completer = Completer<_AdLoadResult>();

    void completeFailure(String reason, {String? adNetwork}) {
      if (!completer.isCompleted) {
        completer.complete(_AdLoadResult.failure(reason, adNetwork: adNetwork));
      }
    }

    try {
      await RewardedAd.load(
        adUnitId: adId,
        request: _defaultAdRequest,
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (completer.isCompleted) {
              ad.dispose();
              return;
            }
            ad.onPaidEvent = _buildOnPaidEvent(placement, info);
            completer.complete(_AdLoadResult.success(ad));
          },
          onAdFailedToLoad: (error) {
            completeFailure(
              'code=${error.code} message=${error.message} domain=${error.domain}',
              adNetwork: _resolveResponseInfoAdNetwork(error.responseInfo),
            );
          },
        ),
      );
    } catch (error) {
      completeFailure('exception=$error');
    }
    return completer.future;
  }

  Future<_AdLoadResult> _loadBannerAd(
    K placement,
    AdInfoBean info,
    String adId,
  ) async {
    final completer = Completer<_AdLoadResult>();

    void completeFailure(String reason, {String? adNetwork}) {
      if (!completer.isCompleted) {
        completer.complete(_AdLoadResult.failure(reason, adNetwork: adNetwork));
      }
    }

    final ad = BannerAd(
      size: _bannerSizeBuilder?.call(placement) ?? _bannerSize,
      adUnitId: adId,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (completer.isCompleted) {
            ad.dispose();
            return;
          }
          completer.complete(_AdLoadResult.success(ad));
        },
        onAdFailedToLoad: (ad, error) async {
          final adNetwork = _resolveAdNetwork(ad);
          await ad.dispose();
          completeFailure(
            'code=${error.code} message=${error.message} domain=${error.domain}',
            adNetwork: adNetwork,
          );
        },
        onAdClicked: (ad) {
          _dispatchAdClicked(placement, info, ad);
        },
        onPaidEvent: _buildOnPaidEvent(placement, info),
      ),
      request:
          _adRequestBuilder?.call(placement, _defaultAdRequest) ??
          _defaultAdRequest,
    );

    try {
      await ad.load();
    } catch (error) {
      await ad.dispose();
      completeFailure('exception=$error');
    }

    return completer.future;
  }

  Future<_AdLoadResult> _loadNativeAd(
    K placement,
    AdInfoBean info,
    String adId,
  ) async {
    final completer = Completer<_AdLoadResult>();

    void completeFailure(String reason, {String? adNetwork}) {
      if (!completer.isCompleted) {
        completer.complete(_AdLoadResult.failure(reason, adNetwork: adNetwork));
      }
    }

    final ad = NativeAd(
      adUnitId: adId,
      factoryId: _nativeAdFactoryIdBuilder?.call(placement),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (completer.isCompleted) {
            ad.dispose();
            return;
          }
          completer.complete(_AdLoadResult.success(ad));
        },
        onAdFailedToLoad: (ad, error) async {
          final adNetwork = _resolveAdNetwork(ad);
          await ad.dispose();
          completeFailure(
            'code=${error.code} message=${error.message} domain=${error.domain}',
            adNetwork: adNetwork,
          );
        },
        onAdClicked: (ad) {
          _dispatchAdClicked(placement, info, ad);
        },
        onPaidEvent: _buildOnPaidEvent(placement, info),
      ),
      request: _defaultAdRequest,
      nativeAdOptions: _nativeAdOptionsBuilder?.call(placement),
      nativeTemplateStyle: _nativeAdFactoryIdBuilder?.call(placement) == null
          ? (_nativeTemplateStyleBuilder?.call(placement) ??
                _nativeTemplateStyle)
          : null,
    );

    try {
      await ad.load();
    } catch (error) {
      await ad.dispose();
      completeFailure('exception=$error');
    }

    return completer.future;
  }

  OnPaidEventCallback? _buildOnPaidEvent(K placement, AdInfoBean info) {
    final onPaidEvent = _onPaidEvent;
    if (onPaidEvent == null) {
      return null;
    }
    return (ad, valueMicros, precision, currencyCode) {
      onPaidEvent(placement, info, ad, valueMicros, precision, currencyCode);
    };
  }

  void _logLoadStart(K placement, AdInfoBean info) {
    _onAdRequestStart?.call(placement, info);
    _log('load-start', placement, info: info);
  }

  void _logLoadFailure(
    K placement,
    AdInfoBean info, {
    String? reason,
    String? adNetwork,
  }) {
    _onAdRequestFailure?.call(
      placement,
      info,
      reason ?? 'unknown',
      adNetwork ?? _fallbackAdNetwork,
      adNetwork ?? _fallbackAdNetwork,
    );
    _log('load-failed', placement, info: info, extra: reason);
  }

  void _logLoadSuccess(
    K placement,
    LoadedAdCacheEntry entry, {
    required int cacheCount,
  }) {
    final adSourceName = _resolveAdNetwork(entry.ad);
    _onAdRequestSuccess?.call(
      placement,
      entry.info,
      adSourceName,
      adSourceName,
    );
    _log(
      'load-success',
      placement,
      info: entry.info,
      extra:
          'requestOrder=${entry.requestOrder} '
          'cacheCount=$cacheCount '
          'loadedAt=${entry.cachedAt.toIso8601String()} '
          'expireAt=${entry.expireAt?.toIso8601String() ?? 'never'} '
          'adClass=${entry.ad.runtimeType}',
    );
  }

  String _resolveAdNetwork(Ad? ad) {
    return _normalizeAdNetwork(
      ad?.responseInfo?.loadedAdapterResponseInfo?.adSourceName,
    );
  }

  String _resolveResponseInfoAdNetwork(ResponseInfo? responseInfo) {
    return _normalizeAdNetwork(
      responseInfo?.loadedAdapterResponseInfo?.adSourceName,
    );
  }

  String _normalizeAdNetwork(String? adNetwork) {
    final normalized = adNetwork?.trim();
    if (normalized == null || normalized.isEmpty) {
      return _fallbackAdNetwork;
    }
    return normalized;
  }

  void _dispatchAdShowStart(K placement, AdInfoBean info, Ad ad) {
    final adSourceName = _resolveAdNetwork(ad);
    _onAdShowStart?.call(placement, info, adSourceName, adSourceName);
  }

  void _dispatchAdShowed(K placement, AdInfoBean info, Ad ad) {
    final adSourceName = _resolveAdNetwork(ad);
    _onAdShowed?.call(placement, info, adSourceName, adSourceName);
  }

  void _dispatchAdClicked(K placement, AdInfoBean info, Ad ad) {
    final adSourceName = _resolveAdNetwork(ad);
    _onAdClicked?.call(placement, info, adSourceName, adSourceName);
  }

  void _dispatchAdClosed(K placement, AdInfoBean info, Ad ad) {
    final adSourceName = _resolveAdNetwork(ad);
    _onAdClosed?.call(placement, info, adSourceName, adSourceName);
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

  Future<void> _consumeShownEntryAfterShow(
    K placement,
    LoadedAdCacheEntry shownEntry, {
    required String trigger,
  }) async {
    final entries = _cacheMap[placement];
    if (entries == null || entries.isEmpty) {
      return;
    }

    final removed = entries.remove(shownEntry);
    if (!removed) {
      return;
    }

    await shownEntry.dispose();

    if (entries.isEmpty) {
      _cacheMap.remove(placement);
      final activeRequestCount = _activeRequestCounts[placement] ?? 0;
      if (activeRequestCount > 0) {
        _log(
          'cache-empty-await-pending',
          placement,
          info: shownEntry.info,
          extra: 'activeRequestCount=$activeRequestCount',
        );
        return;
      }
      if (trigger == 'close' &&
          _skipReloadAfterClosePlacements.contains(placement)) {
        _log('skip-reload-after-close', placement, info: shownEntry.info);
        return;
      }
      _logCacheReload(placement, trigger: 'close-empty-reload');
      unawaited(loadPlacement(placement, force: true));
      return;
    }

    _log(
      'cache-advance-after-show',
      placement,
      info: entries.first.info,
      extra:
          'remainingCount=${entries.length} '
          'nextRequestOrder=${entries.first.requestOrder}',
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

class _AdLoadResult {
  const _AdLoadResult._({this.ad, this.failureReason, this.adNetwork});

  const _AdLoadResult.success(Ad ad) : this._(ad: ad);

  const _AdLoadResult.failure(String reason, {String? adNetwork})
    : this._(failureReason: reason, adNetwork: adNetwork);

  final Ad? ad;
  final String? failureReason;
  final String? adNetwork;
}

class ShowAdResult {
  const ShowAdResult._({required this.shown, this.failureReason});

  const ShowAdResult.success() : this._(shown: true);

  const ShowAdResult.failure(String reason)
    : this._(shown: false, failureReason: reason);

  final bool shown;
  final String? failureReason;
}
