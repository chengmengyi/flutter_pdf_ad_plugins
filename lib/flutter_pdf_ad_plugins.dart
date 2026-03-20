import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'bean/ad_info_bean.dart';
import 'enum/ad_type.dart';
import 'load/flutter_pdf_ad_loader.dart';
import 'load/loaded_ad_cache_entry.dart';

export 'bean/ad_info_bean.dart';
export 'enum/ad_type.dart';
export 'load/flutter_pdf_ad_loader.dart';
export 'load/loaded_ad_cache_entry.dart';

class FlutterPdfAdPlugins {
  static final FlutterPdfAdPlugins _adPlugins = FlutterPdfAdPlugins();
  static FlutterPdfAdPlugins get instance => _adPlugins;

  int _productCooldownSeconds = 30;
  int _inventoryCooldownSeconds = 30;

  FlutterPdfAdLoader<Object>? _adLoader;
  final Set<Object> _interstitialLikeNativePlacements = <Object>{};
  _LastShownAdRecord? _lastShownAdRecord;

  Future<void> initAdmob() async {
    await MobileAds.instance.initialize();
  }

  void updateProductCooldownSeconds(int seconds) {
    _productCooldownSeconds = seconds < 0 ? 0 : seconds;
  }

  void updateInventoryCooldownSeconds(int seconds) {
    _inventoryCooldownSeconds = seconds < 0 ? 0 : seconds;
  }

  void updateInterstitialLikeNativePlacements<K>(Iterable<K> placements) {
    _interstitialLikeNativePlacements
      ..clear()
      ..addAll(placements.map((placement) => placement as Object));
  }

  void configureLoader<K>({
    AdRequest? defaultAdRequest,
    AdSize? bannerSize,
    NativeTemplateStyle? nativeTemplateStyle,
    String Function(K placement)? placementLabelBuilder,
  }) {
    _adLoader ??= FlutterPdfAdLoader<Object>(
      defaultAdRequest: defaultAdRequest,
      bannerSize: bannerSize,
      nativeTemplateStyle: nativeTemplateStyle,
      placementLabelBuilder: placementLabelBuilder == null
          ? null
          : (placement) => placementLabelBuilder(placement as K),
    );
  }

  void updateConfigs<K>(
    Map<K, List<AdInfoBean>> configs, {
    String Function(K placement)? placementLabelBuilder,
  }) {
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    loader.updateConfigs(_boxConfigs(configs));
  }

  void updatePlacementConfig<K>(
    K placement,
    List<AdInfoBean> configs, {
    String Function(K placement)? placementLabelBuilder,
  }) {
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    loader.updatePlacementConfig(placement as Object, configs);
  }

  Future<LoadedAdCacheEntry?> loadPlacement<K>(
    K placement, {
    List<AdInfoBean>? configs,
    bool force = false,
    String Function(K placement)? placementLabelBuilder,
  }) {
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    return loader.loadPlacement(
      placement as Object,
      configs: configs,
      force: force,
    );
  }

  Future<LoadedAdCacheEntry?> getCachedEntry<K>(K placement) {
    final loader = _ensureLoader<K>();
    return loader.getCachedEntry(placement as Object);
  }

  Future<Ad?> getCachedAd<K>(K placement) {
    final loader = _ensureLoader<K>();
    return loader.getCachedAd(placement as Object);
  }

  Future<bool> showCachedAd<K>(
    K placement, {
    BuildContext? context,
    bool enableNativeCooldown = false,
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) {
    final loader = _ensureLoader<K>();
    return _showPlacement(
      loader,
      placement as Object,
      context: context,
      enableNativeCooldown: enableNativeCooldown,
      onUserEarnedReward: onUserEarnedReward,
    );
  }

  Future<bool> loadAndShow<K>(
    K placement, {
    BuildContext? context,
    List<AdInfoBean>? configs,
    bool forceReload = false,
    bool enableNativeCooldown = false,
    OnUserEarnedRewardCallback? onUserEarnedReward,
    String Function(K placement)? placementLabelBuilder,
  }) {
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    return _loadAndShowPlacement(
      loader,
      placement as Object,
      context: context,
      configs: configs,
      forceReload: forceReload,
      enableNativeCooldown: enableNativeCooldown,
      onUserEarnedReward: onUserEarnedReward,
    );
  }

  Future<void> preloadAll<K>({
    Iterable<K>? placements,
    bool force = false,
    String Function(K placement)? placementLabelBuilder,
  }) {
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    return loader.preloadAll(
      placements: placements?.map((placement) => placement as Object),
      force: force,
    );
  }

  Future<void> clearPlacementCache<K>(K placement) {
    final loader = _ensureLoader<K>();
    return loader.clearPlacementCache(placement as Object);
  }

  Future<void> disposeLoader() async {
    final loader = _adLoader;
    _adLoader = null;
    _lastShownAdRecord = null;
    _interstitialLikeNativePlacements.clear();
    if (loader != null) {
      await loader.dispose();
    }
  }

  FlutterPdfAdLoader<Object> _ensureLoader<K>({
    String Function(K placement)? placementLabelBuilder,
  }) {
    configureLoader<K>(placementLabelBuilder: placementLabelBuilder);
    return _adLoader!;
  }

  Map<Object, List<AdInfoBean>> _boxConfigs<K>(
    Map<K, List<AdInfoBean>> configs,
  ) {
    return configs.map(
      (placement, items) => MapEntry(placement as Object, items),
    );
  }

  Future<bool> _loadAndShowPlacement(
    FlutterPdfAdLoader<Object> loader,
    Object placement, {
    required BuildContext? context,
    required List<AdInfoBean>? configs,
    required bool forceReload,
    required bool enableNativeCooldown,
    required OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    if (!forceReload) {
      final shown = await _showPlacement(
        loader,
        placement,
        context: context,
        enableNativeCooldown: enableNativeCooldown,
        onUserEarnedReward: onUserEarnedReward,
      );
      if (shown) {
        return true;
      }
    }

    final entry = await loader.loadPlacement(
      placement,
      configs: configs,
      force: forceReload,
    );
    if (entry == null) {
      return false;
    }

    if (context != null && !context.mounted) {
      return false;
    }

    return _showPlacement(
      loader,
      placement,
      context: context,
      enableNativeCooldown: enableNativeCooldown,
      onUserEarnedReward: onUserEarnedReward,
    );
  }

  Future<bool> _showPlacement(
    FlutterPdfAdLoader<Object> loader,
    Object placement, {
    required BuildContext? context,
    required bool enableNativeCooldown,
    required OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    final cachedEntry = loader.cacheMap[placement];
    if (cachedEntry == null) {
      return false;
    }

    if (cachedEntry.isExpired) {
      await loader.clearPlacementCache(placement);
      unawaited(loader.loadPlacement(placement, force: true));
      _log('show-expired', placement, cachedEntry.info);
      return false;
    }

    final cooldownResult = _getCooldownBlockReason(
      cachedEntry.info,
      enableNativeCooldown: enableNativeCooldown,
    );
    if (cooldownResult != null) {
      _log(
        'show-cooldown-blocked',
        placement,
        cachedEntry.info,
        extra:
            'cooldownType=${cooldownResult.cooldownType} '
            'remainingSeconds=${cooldownResult.remainingSeconds}',
      );
      return false;
    }

    final adType = cachedEntry.info.parsedAdType;
    if (adType == AdType.native) {
      if (context == null) {
        _log('show-native-missing-context', placement, cachedEntry.info);
        return false;
      }

      final shown = await _showNativeAd(
        context,
        loader,
        placement,
        cachedEntry,
      );
      if (shown) {
        _recordShownAd(
          cachedEntry.info,
          enableNativeCooldown: enableNativeCooldown,
        );
      }
      return shown;
    }

    final shown = await loader.showCachedAd(
      placement,
      onUserEarnedReward: onUserEarnedReward,
    );
    if (shown) {
      _recordShownAd(cachedEntry.info, enableNativeCooldown: true);
    }
    return shown;
  }

  _CooldownBlockReason? _getCooldownBlockReason(
    AdInfoBean info, {
    required bool enableNativeCooldown,
  }) {
    final adType = info.parsedAdType;
    if (adType == null) {
      return null;
    }

    if (adType == AdType.native && !enableNativeCooldown) {
      return null;
    }

    final lastShown = _lastShownAdRecord;
    if (lastShown == null) {
      return null;
    }

    final now = DateTime.now();
    if (info.adId != null && info.adId == lastShown.adId) {
      final inventoryUntil = lastShown.shownAt.add(
        Duration(seconds: _inventoryCooldownSeconds),
      );
      if (now.isBefore(inventoryUntil)) {
        return _CooldownBlockReason(
          cooldownType: 'kc_cd',
          remainingSeconds: inventoryUntil.difference(now).inSeconds + 1,
        );
      }
    }

    if (lastShown.adType != adType) {
      final productUntil = lastShown.shownAt.add(
        Duration(seconds: _productCooldownSeconds),
      );
      if (now.isBefore(productUntil)) {
        return _CooldownBlockReason(
          cooldownType: 'pr_cd',
          remainingSeconds: productUntil.difference(now).inSeconds + 1,
        );
      }
    }

    return null;
  }

  void _recordShownAd(AdInfoBean info, {required bool enableNativeCooldown}) {
    final adType = info.parsedAdType;
    if (adType == null) {
      return;
    }

    if (adType == AdType.native && !enableNativeCooldown) {
      return;
    }

    _lastShownAdRecord = _LastShownAdRecord(
      adId: info.adId,
      adType: adType,
      shownAt: DateTime.now(),
    );
  }

  Future<bool> _showNativeAd(
    BuildContext context,
    FlutterPdfAdLoader<Object> loader,
    Object placement,
    LoadedAdCacheEntry entry,
  ) async {
    final ad = entry.ad;
    if (ad is! NativeAd) {
      return false;
    }

    final interstitialLike = _interstitialLikeNativePlacements.contains(
      placement,
    );
    if (interstitialLike) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _NativeInterstitialPage(ad: ad),
          fullscreenDialog: true,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (_) => _NativeDialog(ad: ad),
      );
    }

    await loader.clearPlacementCache(placement);
    _log('native-closed-reload', placement, entry.info);
    unawaited(loader.loadPlacement(placement, force: true));
    return true;
  }

  void _log(String stage, Object placement, AdInfoBean info, {String? extra}) {
    if (kReleaseMode) {
      return;
    }

    final buffer = StringBuffer()
      ..write('[FlutterPdfAdPlugins] $stage ')
      ..write('placement=$placement ')
      ..write('adInfo={${info.logSummary}} ')
      ..write('pr_cd=$_productCooldownSeconds ')
      ..write('kc_cd=$_inventoryCooldownSeconds');

    if (extra != null && extra.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(extra);
    }

    debugPrint(buffer.toString());
  }
}

class _LastShownAdRecord {
  const _LastShownAdRecord({
    required this.adId,
    required this.adType,
    required this.shownAt,
  });

  final String? adId;
  final AdType adType;
  final DateTime shownAt;
}

class _CooldownBlockReason {
  const _CooldownBlockReason({
    required this.cooldownType,
    required this.remainingSeconds,
  });

  final String cooldownType;
  final int remainingSeconds;
}

class _NativeInterstitialPage extends StatelessWidget {
  const _NativeInterstitialPage({required this.ad});

  final NativeAd ad;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 360,
                  maxHeight: 520,
                ),
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: AdWidget(ad: ad),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NativeDialog extends StatelessWidget {
  const _NativeDialog({required this.ad});

  final NativeAd ad;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 320, height: 360, child: AdWidget(ad: ad)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }
}
