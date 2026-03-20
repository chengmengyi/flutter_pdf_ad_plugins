import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'bean/ad_info_bean.dart';
import 'enum/ad_type.dart';
import 'load/flutter_pdf_ad_loader.dart';
import 'load/loaded_ad_cache_entry.dart';
import 'shield/ad_adjust_manager.dart';
import 'shield/ad_referrer_manager.dart';
import 'shield/referrer_block_config.dart';
import 'ump/ump_consent_result.dart';

export 'bean/ad_info_bean.dart';
export 'enum/ad_type.dart';
export 'load/flutter_pdf_ad_loader.dart';
export 'load/loaded_ad_cache_entry.dart';
export 'ump/ump_consent_result.dart';

class FlutterPdfAdPlugins {
  static final FlutterPdfAdPlugins _adPlugins = FlutterPdfAdPlugins();
  static FlutterPdfAdPlugins get instance => _adPlugins;
  static const Set<String> _defaultCmpCountryCodes = <String>{
    'AT',
    'BE',
    'BG',
    'HR',
    'CY',
    'CZ',
    'DK',
    'EE',
    'FI',
    'FR',
    'DE',
    'GR',
    'HU',
    'IE',
    'IT',
    'LV',
    'LT',
    'LU',
    'MT',
    'NL',
    'PL',
    'PT',
    'RO',
    'SK',
    'SI',
    'ES',
    'SE',
    'NO',
    'IS',
    'LI',
    'CH',
    'GB',
  };

  int _productCooldownSeconds = 30;
  int _inventoryCooldownSeconds = 30;

  FlutterPdfAdLoader<Object>? _adLoader;
  final Map<Object, List<AdInfoBean>> _defaultConfigs =
      <Object, List<AdInfoBean>>{};
  final Map<Object, List<AdInfoBean>> _facebookConfigs =
      <Object, List<AdInfoBean>>{};
  final Set<Object> _interstitialLikeNativePlacements = <Object>{};
  _LastShownAdRecord? _lastShownAdRecord;
  bool _isBlacklistUser = false;
  final Set<String> _cmpCountryCodes = <String>{..._defaultCmpCountryCodes};
  ReferrerBlockConfig _referrerBlockConfig = const ReferrerBlockConfig(
    door: 0,
    ilve: <String>[],
  );

  Future<void> initAdmob({String? adjustAppToken, String? distinctId}) async {
    await MobileAds.instance.initialize();
    unawaited(AdReferrerManager.instance.getReferrer());
    final normalizedAdjustAppToken = (adjustAppToken ?? '').trim();
    if (normalizedAdjustAppToken.isNotEmpty) {
      unawaited(
        AdAdjustManager.instance.initialize(
          appToken: normalizedAdjustAppToken,
          distinctId: distinctId,
        ),
      );
    } else {
      _logGeneral('init-admob-skip-adjust empty-app-token');
    }
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

  void updateReferrerBlockConfig(Map<String, dynamic> json) {
    _referrerBlockConfig = ReferrerBlockConfig.fromJson(json);
    if (kReleaseMode) {
      return;
    }
    debugPrint(
      '[FlutterPdfAdPlugins] update-referrer-block-config '
      '${_referrerBlockConfig.logSummary}',
    );
  }

  void updateBlacklistStatus(bool isBlacklistUser) {
    _isBlacklistUser = isBlacklistUser;
    if (kReleaseMode) {
      return;
    }
    debugPrint(
      '[FlutterPdfAdPlugins] update-blacklist-status isBlacklistUser=$_isBlacklistUser',
    );
  }

  void updateCmpCountryCodes(Iterable<String> countryCodes) {
    _cmpCountryCodes
      ..clear()
      ..addAll(
        countryCodes
            .map((code) => code.trim().toUpperCase())
            .where((code) => code.isNotEmpty),
      );
    if (kReleaseMode) {
      return;
    }
    debugPrint(
      '[FlutterPdfAdPlugins] update-cmp-country-codes $_cmpCountryCodes',
    );
  }

  void resetCmpCountryCodes() {
    _cmpCountryCodes
      ..clear()
      ..addAll(_defaultCmpCountryCodes);
  }

  String getCurrentCountryCode() {
    final locale = ui.PlatformDispatcher.instance.locale;
    return (locale.countryCode ?? '').toUpperCase();
  }

  bool shouldUseCmpForCurrentLocale() {
    final countryCode = getCurrentCountryCode();
    return _cmpCountryCodes.contains(countryCode);
  }

  Future<UmpConsentResult> handleUmpConsent({
    ConsentRequestParameters? params,
    bool loadAndShowFormIfRequired = true,
  }) async {
    final countryCode = getCurrentCountryCode();
    final requiresCmpByLocale = _cmpCountryCodes.contains(countryCode);

    if (!requiresCmpByLocale) {
      final consentStatus = await ConsentInformation.instance
          .getConsentStatus();
      final canRequestAds = await ConsentInformation.instance.canRequestAds();
      final privacyStatus = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      _logUmp(
        'skip-by-locale',
        extra:
            'countryCode=$countryCode canRequestAds=$canRequestAds '
            'consentStatus=$consentStatus privacyStatus=$privacyStatus',
      );
      return UmpConsentResult(
        countryCode: countryCode,
        requiresCmpByLocale: false,
        canRequestAds: canRequestAds,
        consentStatus: consentStatus,
        privacyOptionsRequirementStatus: privacyStatus,
      );
    }

    final requestParameters = params ?? ConsentRequestParameters();
    final requestError = await _requestConsentInfoUpdate(requestParameters);
    FormError? formError = requestError;

    if (requestError == null && loadAndShowFormIfRequired) {
      formError = await _loadAndShowConsentFormIfRequired();
    }

    final consentStatus = await ConsentInformation.instance.getConsentStatus();
    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    final privacyStatus = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();

    _logUmp(
      'handled',
      extra:
          'countryCode=$countryCode canRequestAds=$canRequestAds '
          'consentStatus=$consentStatus privacyStatus=$privacyStatus '
          'formError=${formError?.message ?? 'null'}',
    );

    return UmpConsentResult(
      countryCode: countryCode,
      requiresCmpByLocale: true,
      canRequestAds: canRequestAds,
      consentStatus: consentStatus,
      privacyOptionsRequirementStatus: privacyStatus,
      formError: formError,
    );
  }

  Future<bool> canRequestAds() {
    return ConsentInformation.instance.canRequestAds();
  }

  Future<PrivacyOptionsRequirementStatus> getPrivacyOptionsRequirementStatus() {
    return ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
  }

  Future<FormError?> showPrivacyOptionsForm() {
    return _showPrivacyOptionsForm();
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
    _defaultConfigs
      ..clear()
      ..addAll(_boxConfigs(configs));
    _ensureLoader<K>(placementLabelBuilder: placementLabelBuilder);
  }

  void updatePlacementConfig<K>(
    K placement,
    List<AdInfoBean> configs, {
    String Function(K placement)? placementLabelBuilder,
  }) {
    _defaultConfigs[placement as Object] = List<AdInfoBean>.unmodifiable(
      configs,
    );
    _ensureLoader<K>(placementLabelBuilder: placementLabelBuilder);
  }

  void updateFacebookConfigs<K>(
    Map<K, List<AdInfoBean>> configs, {
    String Function(K placement)? placementLabelBuilder,
  }) {
    _facebookConfigs
      ..clear()
      ..addAll(_boxConfigs(configs));
    _ensureLoader<K>(placementLabelBuilder: placementLabelBuilder);
  }

  void updateFacebookPlacementConfig<K>(
    K placement,
    List<AdInfoBean> configs, {
    String Function(K placement)? placementLabelBuilder,
  }) {
    _facebookConfigs[placement as Object] = List<AdInfoBean>.unmodifiable(
      configs,
    );
    _ensureLoader<K>(placementLabelBuilder: placementLabelBuilder);
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
    return _loadPlacementWithAudience(
      loader,
      placement as Object,
      configs: configs,
      force: force,
    );
  }

  Future<LoadedAdCacheEntry?> getCachedEntry<K>(K placement) async {
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    return loader.getCachedEntry(placement as Object);
  }

  Future<Ad?> getCachedAd<K>(K placement) async {
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    return loader.getCachedAd(placement as Object);
  }

  Future<bool> showCachedAd<K>(
    K placement, {
    BuildContext? context,
    bool enableNativeCooldown = false,
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) {
    final loader = _ensureLoader<K>();
    return _showCachedAdWithAudience(
      loader,
      placement as Object,
      context: context,
      enableNativeCooldown: enableNativeCooldown,
      onUserEarnedReward: onUserEarnedReward,
    );
  }

  Future<void> preloadAll<K>({
    Iterable<K>? placements,
    bool force = false,
    String Function(K placement)? placementLabelBuilder,
  }) async {
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    await _syncLoaderConfigs(loader);
    await loader.preloadAll(
      placements: placements?.map((placement) => placement as Object),
      force: force,
    );
  }

  Future<void> clearPlacementCache<K>(K placement) async {
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    return loader.clearPlacementCache(placement as Object);
  }

  Future<LoadedAdCacheEntry?> _loadPlacementWithAudience(
    FlutterPdfAdLoader<Object> loader,
    Object placement, {
    required List<AdInfoBean>? configs,
    required bool force,
  }) async {
    await _syncLoaderConfigs(loader);
    final resolvedConfigs =
        configs ?? await _resolveConfigsForPlacement(placement);
    return loader.loadPlacement(
      placement,
      configs: resolvedConfigs,
      force: force,
    );
  }

  Future<bool> _showCachedAdWithAudience(
    FlutterPdfAdLoader<Object> loader,
    Object placement, {
    required BuildContext? context,
    required bool enableNativeCooldown,
    required OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    await _syncLoaderConfigs(loader);
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

  Future<void> _syncLoaderConfigs(FlutterPdfAdLoader<Object> loader) async {
    loader.updateConfigs(await _resolveActiveConfigs());
  }

  Future<Map<Object, List<AdInfoBean>>> _resolveActiveConfigs() async {
    final isFacebookUser = await _isFacebookUser();
    final keys = <Object>{..._defaultConfigs.keys, ..._facebookConfigs.keys};
    final resolved = <Object, List<AdInfoBean>>{};

    for (final key in keys) {
      final selected =
          isFacebookUser && (_facebookConfigs[key]?.isNotEmpty ?? false)
          ? _facebookConfigs[key]
          : _defaultConfigs[key];
      if (selected != null) {
        resolved[key] = selected;
      }
    }

    return resolved;
  }

  Future<List<AdInfoBean>?> _resolveConfigsForPlacement(
    Object placement,
  ) async {
    final isFacebookUser = await _isFacebookUser();
    if (isFacebookUser && (_facebookConfigs[placement]?.isNotEmpty ?? false)) {
      return _facebookConfigs[placement];
    }
    return _defaultConfigs[placement];
  }

  Future<bool> _isFacebookUser() async {
    final referrer = await AdReferrerManager.instance.getReferrer();
    final attribution = await AdAdjustManager.instance.getAttribution();
    final referrerContainsFacebook = _containsFacebook(referrer);
    final adjustContainsFacebook = AdAdjustManager.instance.containsFacebook(
      attribution,
    );
    final isFacebookUser = referrerContainsFacebook || adjustContainsFacebook;

    if (!kReleaseMode) {
      debugPrint(
        '[FlutterPdfAdPlugins] facebook-user-check '
        'isFacebookUser=$isFacebookUser '
        'referrerContainsFacebook=$referrerContainsFacebook '
        'adjustContainsFacebook=$adjustContainsFacebook '
        'referrer=${referrer ?? 'null'} '
        'adjust=${AdAdjustManager.instance.summary(attribution)}',
      );
    }

    return isFacebookUser;
  }

  bool _containsFacebook(String? value) {
    return (value ?? '').toLowerCase().contains('facebook');
  }

  void _logGeneral(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[FlutterPdfAdPlugins] $message');
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

    final blockedByShield = await _isBlockedByShield(
      placement,
      cachedEntry.info,
    );
    if (blockedByShield) {
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
      if (!context.mounted) {
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

  Future<bool> _isBlockedByShield(Object placement, AdInfoBean info) async {
    if (_isBlacklistUser) {
      _log(
        'show-blacklist-blocked',
        placement,
        info,
        extra: 'isBlacklistUser=true',
      );
      return true;
    }

    if (!_referrerBlockConfig.isEnabled) {
      return false;
    }

    if (!Platform.isAndroid) {
      return false;
    }

    final referrer = await AdReferrerManager.instance.getReferrer();
    _log(
      'show-referrer-read',
      placement,
      info,
      extra: 'referrer=${referrer ?? 'null'}',
    );
    final blocked = _referrerBlockConfig.shouldBlock(referrer);
    if (blocked) {
      _log(
        'show-referrer-blocked',
        placement,
        info,
        extra:
            'referrer=${referrer ?? 'null'} '
            'config=${_referrerBlockConfig.logSummary}',
      );
    } else {
      _log(
        'show-referrer-allowed',
        placement,
        info,
        extra:
            'referrer=${referrer ?? 'null'} '
            'config=${_referrerBlockConfig.logSummary}',
      );
    }
    return blocked;
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

  Future<FormError?> _requestConsentInfoUpdate(
    ConsentRequestParameters params,
  ) async {
    final completer = Completer<FormError?>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
      (error) {
        _logUmp(
          'request-consent-info-failed',
          extra: 'code=${error.errorCode} message=${error.message}',
        );
        if (!completer.isCompleted) {
          completer.complete(error);
        }
      },
    );
    return completer.future;
  }

  Future<FormError?> _loadAndShowConsentFormIfRequired() async {
    final completer = Completer<FormError?>();
    await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
      if (!completer.isCompleted) {
        completer.complete(formError);
      }
    });
    final error = await completer.future;
    if (error != null) {
      _logUmp(
        'load-and-show-form-failed',
        extra: 'code=${error.errorCode} message=${error.message}',
      );
    } else {
      _logUmp('load-and-show-form-success');
    }
    return error;
  }

  Future<FormError?> _showPrivacyOptionsForm() async {
    final completer = Completer<FormError?>();
    await ConsentForm.showPrivacyOptionsForm((formError) {
      if (!completer.isCompleted) {
        completer.complete(formError);
      }
    });
    final error = await completer.future;
    if (error != null) {
      _logUmp(
        'show-privacy-options-failed',
        extra: 'code=${error.errorCode} message=${error.message}',
      );
    } else {
      _logUmp('show-privacy-options-success');
    }
    return error;
  }

  void _logUmp(String stage, {String? extra}) {
    if (kReleaseMode) {
      return;
    }

    final buffer = StringBuffer()..write('[FlutterPdfAdPlugins][UMP] $stage');
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
