import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'bean/ad_info_bean.dart';
import 'enum/ad_type.dart';
import 'group/ad_user_group_manager.dart';
import 'load/flutter_pdf_ad_loader.dart';
import 'load/loaded_ad_cache_entry.dart';
import 'revenue/ad_revenue_manager.dart';
import 'shield/ad_adjust_manager.dart';
import 'shield/ad_referrer_manager.dart';
import 'shield/referrer_block_config.dart';
import 'ump/ump_consent_result.dart';

export 'bean/ad_info_bean.dart';
export 'enum/ad_type.dart';
export 'load/flutter_pdf_ad_loader.dart';
export 'load/loaded_ad_cache_entry.dart';
export 'ump/ump_consent_result.dart';

abstract class FlutterPdfAdListener {
  const FlutterPdfAdListener();

  void onAdPaidEvent(
    Object placement,
    double revenue,
    String currencyCode,
    String adNetwork,
    String precisionType,
    AdInfoBean info,
  ) {}

  void onTachi25OneDayRevenueEvent(String eventName) {}

  void onTachi25TotalRevenueEvent(String eventName) {}
}

class _CallbackFlutterPdfAdListener extends FlutterPdfAdListener {
  _CallbackFlutterPdfAdListener();

  void Function(
    Object placement,
    double revenue,
    String currencyCode,
    String adNetwork,
    String precisionType,
    AdInfoBean info,
  )?
  onAdPaidEventCallback;
  void Function(String eventName)? onTachi25OneDayRevenueEventCallback;
  void Function(String eventName)? onTachi25TotalRevenueEventCallback;

  @override
  void onAdPaidEvent(
    Object placement,
    double revenue,
    String currencyCode,
    String adNetwork,
    String precisionType,
    AdInfoBean info,
  ) {
    onAdPaidEventCallback?.call(
      placement,
      revenue,
      currencyCode,
      adNetwork,
      precisionType,
      info,
    );
  }

  @override
  void onTachi25OneDayRevenueEvent(String eventName) {
    onTachi25OneDayRevenueEventCallback?.call(eventName);
  }

  @override
  void onTachi25TotalRevenueEvent(String eventName) {
    onTachi25TotalRevenueEventCallback?.call(eventName);
  }
}

class FlutterPdfAdPlugins {
  static final FlutterPdfAdPlugins _adPlugins = FlutterPdfAdPlugins();
  static FlutterPdfAdPlugins get instance => _adPlugins;
  static final Random _debugRevenueRandom = Random();
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
  final Set<Object> _smallTemplateNativePlacements = <Object>{};
  final Set<Object> _skipReloadAfterClosePlacements = <Object>{};
  final Map<Object, Set<VoidCallback>> _placementLoadedListeners =
      <Object, Set<VoidCallback>>{};
  final Set<Object> _showingPlacements = <Object>{};
  _LastShownAdRecord? _lastShownAdRecord;
  FlutterPdfAdListener? _listener;
  final _CallbackFlutterPdfAdListener _legacyCallbackListener =
      _CallbackFlutterPdfAdListener();
  bool _isBlacklistUser = false;
  final Set<String> _cmpCountryCodes = <String>{..._defaultCmpCountryCodes};
  ReferrerBlockConfig _referrerBlockConfig = const ReferrerBlockConfig(
    door: 0,
    ilve: <String>[],
  );

  Future<void> initAdmob({String? adjustAppToken, String? distinctId}) async {
    await MobileAds.instance.initialize();
    unawaited(AdReferrerManager.instance.getReferrer());
    unawaited(AdUserGroupManager.instance.getUserGroup());
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

  Future<String?> getAndroidId() {
    return AdUserGroupManager.instance.getAndroidId();
  }

  Future<int?> getCurrentUserGroup() {
    return AdUserGroupManager.instance.getUserGroup();
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

  void updateSmallTemplateNativePlacements<K>(Iterable<K> placements) {
    _smallTemplateNativePlacements
      ..clear()
      ..addAll(placements.map((placement) => placement as Object));
  }

  void addPlacementLoadedListener<K>(K placement, VoidCallback listener) {
    _placementLoadedListeners
        .putIfAbsent(placement as Object, () => <VoidCallback>{})
        .add(listener);
  }

  void removePlacementLoadedListener<K>(K placement, VoidCallback listener) {
    final listeners = _placementLoadedListeners[placement as Object];
    if (listeners == null) {
      return;
    }
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _placementLoadedListeners.remove(placement);
    }
  }

  void updateSkipReloadAfterClosePlacements<K>(Iterable<K> placements) {
    _skipReloadAfterClosePlacements
      ..clear()
      ..addAll(placements.map((placement) => placement as Object));
    _adLoader?.updateSkipReloadAfterClosePlacements(
      _skipReloadAfterClosePlacements,
    );
  }

  void updateTachi25RevenueConfig(Map<String, dynamic>? json) {
    AdRevenueManager.instance.updateDailyThresholdConfig(json);
  }

  void setListener(FlutterPdfAdListener? listener) {
    _listener = listener;
  }

  @Deprecated('Use setListener(FlutterPdfAdListener?) instead.')
  void setOnAdPaidEvent(
    void Function(
      Object placement,
      double revenue,
      String currencyCode,
      String adNetwork,
      String precisionType,
      AdInfoBean info,
    )?
    callback,
  ) {
    _legacyCallbackListener.onAdPaidEventCallback = callback;
    _listener = _legacyCallbackListener;
  }

  @Deprecated('Use setListener(FlutterPdfAdListener?) instead.')
  void setOnTachi25OneDayRevenueEvent(
    void Function(String eventName)? callback,
  ) {
    _legacyCallbackListener.onTachi25OneDayRevenueEventCallback = callback;
    _listener = _legacyCallbackListener;
  }

  @Deprecated('Use setListener(FlutterPdfAdListener?) instead.')
  void setOnTachi25TotalRevenueEvent(
    void Function(String eventName)? callback,
  ) {
    _legacyCallbackListener.onTachi25TotalRevenueEventCallback = callback;
    _listener = _legacyCallbackListener;
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
    bool fetchStatusSnapshot = false,
  }) async {
    final countryCode = getCurrentCountryCode();
    final requiresCmpByLocale = _cmpCountryCodes.contains(countryCode);

    if (!requiresCmpByLocale) {
      final consentStatus = fetchStatusSnapshot
          ? await ConsentInformation.instance.getConsentStatus()
          : ConsentStatus.notRequired;
      final canRequestAds = fetchStatusSnapshot
          ? await ConsentInformation.instance.canRequestAds()
          : true;
      final privacyStatus = fetchStatusSnapshot
          ? await ConsentInformation.instance
                .getPrivacyOptionsRequirementStatus()
          : PrivacyOptionsRequirementStatus.notRequired;
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

    final consentStatus = fetchStatusSnapshot
        ? await ConsentInformation.instance.getConsentStatus()
        : requestError == null && formError == null
        ? ConsentStatus.obtained
        : ConsentStatus.unknown;
    final canRequestAds = fetchStatusSnapshot
        ? await ConsentInformation.instance.canRequestAds()
        : requestError == null && formError == null;
    final privacyStatus = fetchStatusSnapshot
        ? await ConsentInformation.instance.getPrivacyOptionsRequirementStatus()
        : PrivacyOptionsRequirementStatus.unknown;

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
      nativeTemplateStyleBuilder: (placement) {
        if (_smallTemplateNativePlacements.contains(placement)) {
          return NativeTemplateStyle(templateType: TemplateType.small);
        }
        return null;
      },
      onPlacementLoaded: _handlePlacementLoaded,
      onPaidEvent: _handleAdPaidEvent,
      placementLabelBuilder: placementLabelBuilder == null
          ? null
          : (placement) => placementLabelBuilder(placement as K),
    );
    _adLoader?.updateSkipReloadAfterClosePlacements(
      _skipReloadAfterClosePlacements,
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

  Future<Widget?> buildCachedAdWidget<K>(K placement) async {
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    final boxedPlacement = placement as Object;
    final cachedEntry = await loader.getCachedEntry(boxedPlacement);
    if (cachedEntry == null) {
      return null;
    }
    final blockedByShield = await _isBlockedByShield(
      boxedPlacement,
      cachedEntry.info,
    );
    if (blockedByShield) {
      _log(
        'build-native-blocked',
        boxedPlacement,
        cachedEntry.info,
        extra: 'reason=shield-blocked',
      );
      return null;
    }
    return loader.buildCachedAdWidget(boxedPlacement);
  }

  Future<bool> showCachedAd<K>(
    K placement, {
    BuildContext? context,
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) {
    final loader = _ensureLoader<K>();
    return _showCachedAdWithAudience(
      loader,
      placement as Object,
      context: context,
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
    final resolvedConfigs = await _resolveConfigsForLoad(placement, configs);
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
    required OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    await _syncLoaderConfigs(loader);
    if (context != null && !context.mounted) {
      _logGeneral(
        'show-failed placement=$placement reason=context-unmounted-before-show',
      );
      return false;
    }
    return _showPlacement(
      loader,
      placement,
      context: context,
      onUserEarnedReward: onUserEarnedReward,
    );
  }

  Future<bool> loadAndShow<K>(
    K placement, {
    BuildContext? context,
    List<AdInfoBean>? configs,
    bool forceReload = false,
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
      onUserEarnedReward: onUserEarnedReward,
    );
  }

  Future<void> disposeLoader() async {
    final loader = _adLoader;
    _adLoader = null;
    _lastShownAdRecord = null;
    _interstitialLikeNativePlacements.clear();
    _smallTemplateNativePlacements.clear();
    _placementLoadedListeners.clear();
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
    final activeConfigs = await _resolveActiveConfigs();
    loader.updateConfigs(activeConfigs);
    final stalePlacements = loader.cacheMap.keys
        .where((placement) => !activeConfigs.containsKey(placement))
        .toList(growable: false);
    for (final placement in stalePlacements) {
      await loader.clearPlacementCache(placement);
      _logGeneral('clear-stale-cache placement=$placement');
    }
  }

  Future<Map<Object, List<AdInfoBean>>> _resolveActiveConfigs() async {
    final isFacebookUser = await _isFacebookUser();
    final userGroup = await AdUserGroupManager.instance.getUserGroup();
    final keys = <Object>{..._defaultConfigs.keys, ..._facebookConfigs.keys};
    final resolved = <Object, List<AdInfoBean>>{};

    for (final key in keys) {
      final selected =
          isFacebookUser && (_facebookConfigs[key]?.isNotEmpty ?? false)
          ? _facebookConfigs[key]
          : _defaultConfigs[key];
      if (selected != null) {
        final filtered = _filterConfigsByUserGroup(
          key,
          selected,
          userGroup: userGroup,
        );
        if (filtered.isNotEmpty) {
          resolved[key] = filtered;
        }
      }
    }

    return resolved;
  }

  Future<List<AdInfoBean>?> _resolveConfigsForPlacement(
    Object placement,
  ) async {
    final isFacebookUser = await _isFacebookUser();
    final userGroup = await AdUserGroupManager.instance.getUserGroup();
    final selected =
        isFacebookUser && (_facebookConfigs[placement]?.isNotEmpty ?? false)
        ? _facebookConfigs[placement]
        : _defaultConfigs[placement];
    if (selected == null) {
      return null;
    }
    return _filterConfigsByUserGroup(placement, selected, userGroup: userGroup);
  }

  Future<List<AdInfoBean>?> _resolveConfigsForLoad(
    Object placement,
    List<AdInfoBean>? configs,
  ) async {
    if (configs == null) {
      return _resolveConfigsForPlacement(placement);
    }
    final userGroup = await AdUserGroupManager.instance.getUserGroup();
    return _filterConfigsByUserGroup(placement, configs, userGroup: userGroup);
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

  List<AdInfoBean> _filterConfigsByUserGroup(
    Object placement,
    List<AdInfoBean> configs, {
    required int? userGroup,
  }) {
    final filtered = configs
        .where((config) {
          final groups = config.userGroup ?? const <int>[];
          if (groups.isEmpty) {
            return true;
          }
          if (userGroup == null) {
            return false;
          }
          return groups.contains(userGroup);
        })
        .toList(growable: false);

    if (!kReleaseMode) {
      debugPrint(
        '[FlutterPdfAdPlugins] user-group-filter '
        'placement=$placement '
        'userGroup=${userGroup ?? 'null'} '
        'before=${configs.length} '
        'after=${filtered.length}',
      );
    }

    return filtered;
  }

  void _logGeneral(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[FlutterPdfAdPlugins] $message');
  }

  void _handlePlacementLoaded(Object placement, LoadedAdCacheEntry entry) {
    final listeners = _placementLoadedListeners[placement];
    if (listeners == null || listeners.isEmpty) {
      return;
    }
    for (final listener in List<VoidCallback>.from(listeners)) {
      listener();
    }
  }

  Future<bool> _loadAndShowPlacement(
    FlutterPdfAdLoader<Object> loader,
    Object placement, {
    required BuildContext? context,
    required List<AdInfoBean>? configs,
    required bool forceReload,
    required OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    if (!forceReload) {
      final shown = await _showPlacement(
        loader,
        placement,
        context: context,
        onUserEarnedReward: onUserEarnedReward,
      );
      if (shown) {
        _logGeneral(
          'load-and-show-return placement=$placement result=shown-from-cache',
        );
        return true;
      }
    }

    final resolvedConfigs = await _resolveConfigsForLoad(placement, configs);
    final entry = await loader.loadPlacement(
      placement,
      configs: resolvedConfigs,
      force: forceReload,
    );
    if (entry == null) {
      _logGeneral(
        'load-and-show-return placement=$placement result=load-failed',
      );
      return false;
    }

    if (context != null && !context.mounted) {
      _logGeneral(
        'load-and-show-return placement=$placement result=context-unmounted-after-load',
      );
      return false;
    }

    final shown = await _showPlacement(
      loader,
      placement,
      context: context,
      onUserEarnedReward: onUserEarnedReward,
    );
    _logGeneral('load-and-show-return placement=$placement result=$shown');
    return shown;
  }

  Future<bool> _showPlacement(
    FlutterPdfAdLoader<Object> loader,
    Object placement, {
    required BuildContext? context,
    required OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    _logGeneral('show-start placement=$placement');

    var cachedEntry = loader.cacheMap[placement];
    if (cachedEntry == null) {
      _logGeneral('show-cache-miss placement=$placement');
      cachedEntry = await loader.loadPlacement(placement);
      if (cachedEntry == null) {
        _logGeneral(
          'show-failed placement=$placement reason=load-on-show-failed',
        );
        return false;
      }
    }

    if (cachedEntry.isExpired) {
      await loader.clearPlacementCache(placement);
      unawaited(loader.loadPlacement(placement, force: true));
      _log('show-expired', placement, cachedEntry.info);
      _logGeneral('show-failed placement=$placement reason=cache-expired');
      return false;
    }

    final blockedByShield = await _isBlockedByShield(
      placement,
      cachedEntry.info,
    );
    if (blockedByShield) {
      _logGeneral('show-failed placement=$placement reason=shield-blocked');
      return false;
    }

    final cooldownResult = _getCooldownBlockReason(placement, cachedEntry.info);
    if (cooldownResult != null) {
      _log(
        'show-cooldown-blocked',
        placement,
        cachedEntry.info,
        extra:
            'cooldownType=${cooldownResult.cooldownType} '
            'remainingSeconds=${cooldownResult.remainingSeconds}',
      );
      _logGeneral('show-failed placement=$placement reason=cooldown-blocked');
      return false;
    }

    final adType = cachedEntry.info.parsedAdType;
    if (adType == AdType.native) {
      if (!_showingPlacements.add(placement)) {
        _log(
          'show-failed',
          placement,
          cachedEntry.info,
          extra: 'adType=native reason=already-showing',
        );
        return false;
      }
      if (context == null) {
        _log('show-native-missing-context', placement, cachedEntry.info);
        _logGeneral(
          'show-failed placement=$placement reason=native-missing-context',
        );
        _showingPlacements.remove(placement);
        return false;
      }
      if (!context.mounted) {
        _logGeneral(
          'show-failed placement=$placement reason=context-unmounted',
        );
        _showingPlacements.remove(placement);
        return false;
      }

      try {
        final shown = await _showNativeAd(
          context,
          loader,
          placement,
          cachedEntry,
        );
        if (shown.shown) {
          _recordShownAd(placement, cachedEntry.info);
          _log(
            'show-success',
            placement,
            cachedEntry.info,
            extra: 'adType=native',
          );
        } else {
          _log(
            'show-failed',
            placement,
            cachedEntry.info,
            extra:
                'adType=native '
                'reason=${shown.failureReason ?? 'unknown'}',
          );
        }
        return shown.shown;
      } finally {
        _showingPlacements.remove(placement);
      }
    }

    final shown = await loader.showCachedAdWithResult(
      placement,
      onUserEarnedReward: onUserEarnedReward,
    );
    if (shown.shown) {
      _recordShownAd(placement, cachedEntry.info);
      _log(
        'show-success',
        placement,
        cachedEntry.info,
        extra: 'adType=${cachedEntry.info.adType}',
      );
    } else {
      _log(
        'show-failed',
        placement,
        cachedEntry.info,
        extra:
            'adType=${cachedEntry.info.adType} '
            'reason=${shown.failureReason ?? 'unknown'}',
      );
    }
    return shown.shown;
  }

  Future<void> _handleAdPaidEvent(
    Object placement,
    AdInfoBean info,
    Ad ad,
    double valueMicros,
    PrecisionType precision,
    String currencyCode,
  ) async {
    final effectiveValueMicros = _resolvePaidValueMicros(valueMicros);
    final revenue = effectiveValueMicros / 1000000;
    final adNetwork =
        ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName ?? "Admob";
    final precisionType = precision.name;
    _log(
      'paid-event',
      placement,
      info,
      extra:
          'valueMicros=$effectiveValueMicros originalValueMicros=$valueMicros revenue=$revenue '
          'precision=$precision precisionType=$precisionType currencyCode=$currencyCode '
          'adNetwork=$adNetwork '
          'adClass=${ad.runtimeType}',
    );

    final revenueResult = await AdRevenueManager.instance.recordRevenue(
      revenue,
    );
    _log(
      'show-revenue',
      placement,
      info,
      extra:
          'revenue=${revenueResult.revenue} '
          'dailyRevenue=${revenueResult.dailyRevenue} '
          'totalRevenue=${revenueResult.totalRevenue} '
          'currencyCode=$currencyCode',
    );
    _listener?.onAdPaidEvent(
      placement,
      revenue,
      currencyCode,
      adNetwork,
      precisionType,
      info,
    );

    final triggeredEvents = revenueResult.triggeredEvents;
    if (triggeredEvents.isEmpty) {
      return;
    }

    for (final eventName in triggeredEvents) {
      if (eventName.startsWith('AdLTV_OneDay_')) {
        _log(
          'paid-event-trigger-one-day',
          placement,
          info,
          extra: 'eventName=$eventName revenue=$revenue',
        );
        _listener?.onTachi25OneDayRevenueEvent(eventName);
        continue;
      }

      _log(
        'paid-event-trigger-total',
        placement,
        info,
        extra: 'eventName=$eventName revenue=$revenue',
      );
      _listener?.onTachi25TotalRevenueEvent(eventName);
    }
  }

  double _resolvePaidValueMicros(double valueMicros) {
    if (!kDebugMode || valueMicros > 0) {
      return valueMicros;
    }

    const minRevenue = 0.008;
    const maxRevenue = 0.08;
    final mockedRevenue =
        minRevenue +
        _debugRevenueRandom.nextDouble() * (maxRevenue - minRevenue);
    final mockedValueMicros = mockedRevenue * 1000000;
    _logGeneral(
      'paid-event-debug-mock '
      'originalValueMicros=$valueMicros '
      'mockedValueMicros=$mockedValueMicros '
      'mockedRevenue=$mockedRevenue',
    );
    return mockedValueMicros;
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
    Object placement,
    AdInfoBean info,
  ) {
    final adType = info.parsedAdType;
    if (adType == null) {
      return null;
    }

    if (adType == AdType.native && !_shouldApplyNativeCooldown(placement)) {
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

  void _recordShownAd(Object placement, AdInfoBean info) {
    final adType = info.parsedAdType;
    if (adType == null) {
      return;
    }

    if (adType == AdType.native && !_shouldApplyNativeCooldown(placement)) {
      return;
    }

    _lastShownAdRecord = _LastShownAdRecord(
      adId: info.adId,
      adType: adType,
      shownAt: DateTime.now(),
    );
  }

  bool _shouldApplyNativeCooldown(Object placement) {
    return _interstitialLikeNativePlacements.contains(placement);
  }

  Future<_ShowResult> _showNativeAd(
    BuildContext context,
    FlutterPdfAdLoader<Object> loader,
    Object placement,
    LoadedAdCacheEntry entry,
  ) async {
    final ad = entry.ad;
    if (ad is! NativeAd) {
      _log('show-native-invalid-ad', placement, entry.info);
      return const _ShowResult.failure('invalid-native-ad');
    }

    final interstitialLike = _interstitialLikeNativePlacements.contains(
      placement,
    );
    final navigator =
        Navigator.maybeOf(context, rootNavigator: true) ??
        Navigator.maybeOf(context);
    if (navigator == null) {
      _log('show-native-missing-navigator', placement, entry.info);
      return const _ShowResult.failure('missing-navigator');
    }

    if (interstitialLike) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => _NativeInterstitialPage(ad: ad),
          fullscreenDialog: true,
        ),
      );
    } else {
      await showDialog<void>(
        context: navigator.context,
        useRootNavigator: true,
        builder: (_) => _NativeDialog(ad: ad),
      );
    }

    await loader.consumeShownEntryAfterClose(placement, entry);
    _log('native-closed-consume', placement, entry.info);
    return const _ShowResult.success();
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

class _ShowResult {
  const _ShowResult._({required this.shown, this.failureReason});

  const _ShowResult.success() : this._(shown: true);

  const _ShowResult.failure(String reason)
    : this._(shown: false, failureReason: reason);

  final bool shown;
  final String? failureReason;
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
