// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart'
    show instanceManager;

import 'bean/ad_info_bean.dart';
import 'enum/ad_type.dart';
import 'flutter_pdf_ad_plugins_platform_interface.dart';
import 'group/ad_user_group_manager.dart';
import 'load/flutter_pdf_ad_loader.dart';
import 'load/loaded_ad_cache_entry.dart';
import 'revenue/ad_revenue_manager.dart';
import 'attribution/ad_adjust_manager.dart';
import 'attribution/ad_referrer_manager.dart';
import 'ump/ump_consent_result.dart';

export 'bean/ad_info_bean.dart';
export 'enum/ad_type.dart';
export 'load/flutter_pdf_ad_loader.dart';
export 'load/loaded_ad_cache_entry.dart';
export 'ump/ump_consent_result.dart';

typedef FengKongLogic = bool Function();

const String _fullScreenNativeFactoryId = 'full_screen_native';

abstract class FlutterPdfAdListener {
  const FlutterPdfAdListener();

  /// AdMob 初始化成功时回调。
  void onAdmobInitialized() {}

  /// 用户分组解析成功时回调。
  void onUserGroupResolved(int userGroup) {}

  /// 进入 UMP 隐私协议流程时回调。
  void onUmpConsentFlowStart(String countryCode, bool requiresCmpByLocale) {}

  /// UMP 请求开始时回调。
  void onUmpFormRequest() {}

  /// UMP 表单加载流程开始时回调。
  void onUmpFormLoad() {}

  /// 准备调用 UMP 隐私协议表单加载/展示逻辑时回调。
  void onUmpConsentFormShow() {}

  /// UMP 隐私协议流程完成时回调。
  void onUmpConsentFlowComplete(UmpConsentResult result) {}

  /// UMP 隐私协议流程结束后是否可以请求广告。
  void onUmpConsentCanRequestAds(bool canRequestAds) {}

  /// 发起广告请求时回调。
  void onAdRequestStart(Object placement, AdInfoBean info) {}

  /// 广告请求成功时回调。
  void onAdRequestSuccess(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {}

  /// 广告请求失败时回调。
  void onAdRequestFailure(
    Object placement,
    AdInfoBean info,
    String failReason,
    String adNetwork,
    String adSourceName,
  ) {}

  /// 广告满足展示条件，准备调用展示逻辑时回调。
  void onAdShowStart(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {}

  /// 广告展示成功时回调。
  void onAdShowSuccess(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {}

  /// 广告展示失败时回调。
  void onAdShowFailure(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
    String errorMessage,
  ) {}

  /// 广告点击时回调。
  void onAdClicked(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {}

  /// 广告关闭时回调。
  void onAdClosed(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {}

  /// 广告产生收益时回调。
  void onAdPaidEvent(
    Object placement,
    double revenue,
    String currencyCode,
    String adNetwork,
    String precisionType,
    AdInfoBean info,
  ) {}

  /// 单日收益达到阈值时回调。
  void onTachi25OneDayRevenueEvent(String eventName) {}

  /// 总收益达到阈值时回调。
  void onTachi25TotalRevenueEvent(String eventName) {}
}

class FlutterPdfAdPlugins {
  static final FlutterPdfAdPlugins _adPlugins = FlutterPdfAdPlugins();

  /// 获取插件单例。
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

  double _debugMinRevenue = 0.008;
  double _debugMaxRevenue = 0.02;

  FlutterPdfAdLoader<Object>? _adLoader;
  final Map<Object, List<AdInfoBean>> _defaultConfigs =
      <Object, List<AdInfoBean>>{};
  final Map<Object, List<AdInfoBean>> _facebookConfigs =
      <Object, List<AdInfoBean>>{};
  final Set<Object> _interstitialLikeNativePlacements = <Object>{};
  final Set<Object> _smallTemplateNativePlacements = <Object>{};
  final Set<Object> _largeBannerPlacements = <Object>{};
  final Map<Object, String> _collapsibleBannerDirections = <Object, String>{};
  final Set<Object> _skipReloadAfterClosePlacements = <Object>{};
  final Set<Object> _singleFillPlacements = <Object>{};
  final Map<Object, Set<VoidCallback>> _placementLoadedListeners =
      <Object, Set<VoidCallback>>{};
  final Set<Object> _showingPlacements = <Object>{};
  final Set<Object> _showingAdPlacements = <Object>{};
  final Map<Object, String> _userGroupFilterLogCache = <Object, String>{};
  Duration? _adRequestTimeout;
  String? _lastFacebookUserCheckLogSignature;
  FlutterPdfAdListener? _listener;
  final Set<String> _cmpCountryCodes = <String>{..._defaultCmpCountryCodes};
  FengKongLogic? _fengKongLogic;
  String? _smallNativeAdLayoutName;
  AdChoicesPlacement _nativeAdChoicesPlacement =
      AdChoicesPlacement.bottomLeftCorner;

  /// 初始化插件本地配置，并启动归因和用户分组信息拉取。
  ///
  /// 这个方法不会调用 [MobileAds.initialize]。如果业务需要显式初始化
  /// Google Mobile Ads SDK，请先设置监听器，再调用 [initializeAdmob]。
  Future<void> initPlugins({
    required String distinctId,
    required FengKongLogic fengKongLogic,
    String? smallNativeAdLayoutName,
    AdChoicesPlacement nativeAdChoicesPlacement =
        AdChoicesPlacement.bottomLeftCorner,
  }) async {
    _fengKongLogic = fengKongLogic;
    _smallNativeAdLayoutName = _normalizeLayoutName(smallNativeAdLayoutName);
    _nativeAdChoicesPlacement = nativeAdChoicesPlacement;
    await FlutterPdfAdPluginsPlatform.instance.configureSmallNativeAdLayout(
      _smallNativeAdLayoutName,
    );
    unawaited(AdUserGroupManager.instance.getUserGroup());
    unawaited(AdAdjustManager.instance.restore());
    unawaited(AdReferrerManager.instance.restore());
  }

  /// 初始化 Google Mobile Ads SDK。
  ///
  /// 建议在 [setListener] 之后调用，这样初始化完成时可以收到
  /// [FlutterPdfAdListener.onAdmobInitialized]。此方法会等待 SDK 初始化完成；
  /// 如果不希望阻塞启动流程，业务侧可以自行使用 `unawaited` 调用。
  Future<void> initializeAdmob() async {
    try {
      AdUserGroupManager.instance.onUserGroupResolved =
          _notifyUserGroupResolved;
      await MobileAds.instance.initialize();
      _notifyAdmobInitialized();
    } catch (error) {
      _logGeneral('admob-initialize-failed error=$error');
    }
  }

  /// 更新外部 Adjust 归因结果。
  Future<void> updateAdjustAttribution({String? network}) async {
    await AdReferrerManager.instance.restore();
    final referrerContainsFacebook = _containsFacebook(
      AdReferrerManager.instance.cachedReferrer,
    );
    final wasFacebookUser =
        referrerContainsFacebook || AdAdjustManager.instance.containsFacebook();
    final changed = await AdAdjustManager.instance.updateAttribution(
      network: network,
    );
    if (!changed) {
      return;
    }

    final isFacebookUser =
        referrerContainsFacebook || AdAdjustManager.instance.containsFacebook();
    if (wasFacebookUser == isFacebookUser) {
      return;
    }

    final loader = _adLoader;
    if (loader == null) {
      return;
    }
    await _syncLoaderConfigs(loader, clearExistingCache: true);
  }

  /// 更新外部传入的安装来源 referrer。
  Future<void> updateInstallReferrer({String? referrer}) async {
    await AdAdjustManager.instance.restore();
    await AdReferrerManager.instance.restore();
    final wasFacebookUser =
        _containsFacebook(AdReferrerManager.instance.cachedReferrer) ||
        AdAdjustManager.instance.containsFacebook();
    final changed = await AdReferrerManager.instance.updateReferrer(
      referrer: referrer,
    );
    if (!changed) {
      return;
    }

    final isFacebookUser =
        _containsFacebook(AdReferrerManager.instance.cachedReferrer) ||
        AdAdjustManager.instance.containsFacebook();
    if (wasFacebookUser == isFacebookUser) {
      return;
    }

    final loader = _adLoader;
    if (loader == null) {
      return;
    }
    await _syncLoaderConfigs(loader, clearExistingCache: true);
  }

  /// 获取 Android 设备标识。
  Future<String?> getAndroidId() {
    return AdUserGroupManager.instance.getAndroidId();
  }

  /// 获取当前用户分组。
  Future<int?> getCurrentUserGroup() {
    return AdUserGroupManager.instance.getUserGroup();
  }

  /// 设置调试环境下的收益模拟区间。
  void updateDebugPaidRevenueRange({
    required double minRevenue,
    required double maxRevenue,
  }) {
    final double normalizedMinRevenue = minRevenue < 0 ? 0.0 : minRevenue;
    final normalizedMaxRevenue = maxRevenue < normalizedMinRevenue
        ? normalizedMinRevenue
        : maxRevenue;
    _debugMinRevenue = normalizedMinRevenue;
    _debugMaxRevenue = normalizedMaxRevenue;
    if (kReleaseMode) {
      return;
    }
    debugPrint(
      '[FlutterPdfAdPlugins] update-debug-paid-revenue-range '
      'minRevenue=$_debugMinRevenue maxRevenue=$_debugMaxRevenue',
    );
  }

  /// 配置同一广告位多层级请求的超时时间。
  ///
  /// 未配置或传入小于等于 0 的秒数时，不启用定时超时，只在 SDK 请求失败后
  /// 请求下一层广告；传入正数时，当前层超过该时间未返回就会请求下一层。
  void updateAdRequestTimeoutSeconds(int seconds) {
    _adRequestTimeout = seconds <= 0 ? null : Duration(seconds: seconds);
    _adLoader?.updateRequestFallbackDelay(_adRequestTimeout);
  }

  /// 标记哪些原生广告位按插屏逻辑处理。
  void updateInterstitialLikeNativePlacements<K>(Iterable<K> placements) {
    _interstitialLikeNativePlacements
      ..clear()
      ..addAll(placements.map((placement) => placement as Object));
  }

  /// 标记哪些原生广告位使用小模板样式。
  void updateSmallTemplateNativePlacements<K>(Iterable<K> placements) {
    _smallTemplateNativePlacements
      ..clear()
      ..addAll(placements.map((placement) => placement as Object));
  }

  /// 标记哪些 Banner 广告位使用大尺寸。
  void updateLargeBannerPlacements<K>(Iterable<K> placements) {
    _largeBannerPlacements
      ..clear()
      ..addAll(placements.map((placement) => placement as Object));
  }

  /// 配置可折叠 Banner 的展开方向。
  void updateCollapsibleBannerPlacements<K>(Map<K, String> placements) {
    _collapsibleBannerDirections
      ..clear()
      ..addAll(
        placements.map(
          (placement, direction) =>
              MapEntry(placement as Object, direction.trim()),
        ),
      );
  }

  /// 监听指定广告位加载完成。
  void addPlacementLoadedListener<K>(K placement, VoidCallback listener) {
    _placementLoadedListeners
        .putIfAbsent(placement as Object, () => <VoidCallback>{})
        .add(listener);
  }

  /// 移除指定广告位的加载监听。
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

  /// 配置关闭后不自动补加载的广告位。
  void updateSkipReloadAfterClosePlacements<K>(Iterable<K> placements) {
    _skipReloadAfterClosePlacements
      ..clear()
      ..addAll(placements.map((placement) => placement as Object));
    _adLoader?.updateSkipReloadAfterClosePlacements(
      _skipReloadAfterClosePlacements,
    );
  }

  /// 配置首个成功后不再接收后续成功结果的广告位。
  void updateSingleFillPlacements<K>(Iterable<K> placements) {
    _singleFillPlacements
      ..clear()
      ..addAll(placements.map((placement) => placement as Object));
    _adLoader?.updateSingleFillPlacements(_singleFillPlacements);
    _adLoader?.updateRequestFallbackDelay(_adRequestTimeout);
  }

  /// 更新收益阈值事件配置。
  void updateTachi25RevenueConfig(Map<String, dynamic>? json) {
    AdRevenueManager.instance.updateDailyThresholdConfig(json);
  }

  /// 设置广告事件监听器。
  void setListener(FlutterPdfAdListener? listener) {
    _listener = listener;
  }

  /// 判断当前是否有广告正在展示。
  bool isShowingAd() {
    return _showingAdPlacements.isNotEmpty;
  }

  /// 更新需要走 CMP 的国家列表。
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

  /// 重置为默认的 CMP 国家列表。
  void resetCmpCountryCodes() {
    _cmpCountryCodes
      ..clear()
      ..addAll(_defaultCmpCountryCodes);
  }

  /// 获取当前设备地区码。
  String getCurrentCountryCode() {
    final locale = ui.PlatformDispatcher.instance.locale;
    return (locale.countryCode ?? '').toUpperCase();
  }

  /// 判断当前地区是否需要走 CMP。
  bool shouldUseCmpForCurrentLocale() {
    final countryCode = getCurrentCountryCode();
    return _cmpCountryCodes.contains(countryCode);
  }

  /// 处理 UMP 隐私授权流程。
  Future<UmpConsentResult> handleUmpConsent({
    ConsentRequestParameters? params,
    bool loadAndShowFormIfRequired = true,
    bool fetchStatusSnapshot = false,
  }) async {
    final countryCode = getCurrentCountryCode();
    final requiresCmpByLocale = _cmpCountryCodes.contains(countryCode);
    _handleUmpConsentFlowStart(countryCode, requiresCmpByLocale);
    _handleUmpFormRequest();

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
      final result = UmpConsentResult(
        countryCode: countryCode,
        requiresCmpByLocale: false,
        canRequestAds: canRequestAds,
        consentStatus: consentStatus,
        privacyOptionsRequirementStatus: privacyStatus,
      );
      _handleUmpConsentCanRequestAds(canRequestAds);
      _handleUmpConsentFlowComplete(result);
      return result;
    }

    final requestParameters = params ?? ConsentRequestParameters();
    _handleUmpFormLoad();
    final requestError = await _requestConsentInfoUpdate(requestParameters);

    FormError? formError;
    if (requestError == null && loadAndShowFormIfRequired) {
      _handleUmpConsentFormShow();
      formError = await _loadAndShowConsentFormIfRequired();
    }

    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    final consentStatus = await ConsentInformation.instance.getConsentStatus();
    final privacyStatus = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    _logUmp(
      'handled',
      extra:
          'countryCode=$countryCode canRequestAds=$canRequestAds '
          'consentStatus=$consentStatus privacyStatus=$privacyStatus',
    );

    final result = UmpConsentResult(
      countryCode: countryCode,
      requiresCmpByLocale: true,
      canRequestAds: canRequestAds,
      consentStatus: consentStatus,
      privacyOptionsRequirementStatus: privacyStatus,
      formError: formError ?? requestError,
    );
    _handleUmpConsentCanRequestAds(canRequestAds);
    _handleUmpConsentFlowComplete(result);
    return result;
  }

  /// 判断当前是否可以请求广告。
  Future<bool> canRequestAds() {
    return ConsentInformation.instance.canRequestAds();
  }

  /// 获取隐私选项表单要求状态。
  Future<PrivacyOptionsRequirementStatus> getPrivacyOptionsRequirementStatus() {
    return ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
  }

  /// 打开 Ad Inspector 调试面板。
  Future<String?> openAdInspector() async {
    final completer = Completer<String?>();
    MobileAds.instance.openAdInspector((error) {
      if (!completer.isCompleted) {
        completer.complete(
          error == null
              ? null
              : 'code=${error.code} domain=${error.domain} message=${error.message}',
        );
      }
    });
    final error = await completer.future;
    if (error == null) {
      _logGeneral('open-ad-inspector-success');
    } else {
      _logGeneral('open-ad-inspector-failed $error');
    }
    return error;
  }

  /// 展示隐私选项表单。
  Future<FormError?> showPrivacyOptionsForm() {
    return _showPrivacyOptionsForm();
  }

  /// 配置广告加载器的通用参数。
  void configureLoader<K>({
    AdRequest? defaultAdRequest,
    AdSize? bannerSize,
    NativeTemplateStyle? nativeTemplateStyle,
    String Function(K placement)? placementLabelBuilder,
  }) {
    _adLoader ??= FlutterPdfAdLoader<Object>(
      defaultAdRequest: defaultAdRequest,
      bannerSize: bannerSize,
      bannerSizeBuilder: (placement) {
        if (_largeBannerPlacements.contains(placement)) {
          return AdSize.largeBanner;
        }
        return null;
      },
      adRequestBuilder: (placement, request) {
        return _buildBannerRequest(placement, request);
      },
      nativeAdFactoryIdBuilder: (placement) {
        if (_interstitialLikeNativePlacements.contains(placement)) {
          return _fullScreenNativeFactoryId;
        }
        if (_smallNativeAdLayoutName != null &&
            _smallTemplateNativePlacements.contains(placement)) {
          return 'guide_compact_native';
        }
        return null;
      },
      nativeAdOptionsBuilder: (placement) {
        if (_interstitialLikeNativePlacements.contains(placement)) {
          return NativeAdOptions(
            adChoicesPlacement: _nativeAdChoicesPlacement,
            mediaAspectRatio: MediaAspectRatio.portrait,
            videoOptions: VideoOptions(startMuted: true),
          );
        }
        return NativeAdOptions(adChoicesPlacement: _nativeAdChoicesPlacement);
      },
      nativeTemplateStyle: nativeTemplateStyle,
      nativeTemplateStyleBuilder: (placement) {
        if (_smallTemplateNativePlacements.contains(placement)) {
          return NativeTemplateStyle(templateType: TemplateType.small);
        }
        return null;
      },
      onPlacementLoaded: _handlePlacementLoaded,
      onAdRequestStart: _handleAdRequestStart,
      onAdRequestSuccess: _handleAdRequestSuccess,
      onAdRequestFailure: _handleAdRequestFailure,
      onAdShowStart: _handleAdShowStart,
      onAdShowed: _handleAdShowSuccess,
      onAdClicked: _handleAdClicked,
      onAdClosed: _handleAdClosed,
      onPaidEvent: _handleAdPaidEvent,
      placementLabelBuilder: placementLabelBuilder == null
          ? null
          : (placement) => placementLabelBuilder(placement as K),
    );
    _adLoader?.updateSkipReloadAfterClosePlacements(
      _skipReloadAfterClosePlacements,
    );
    _adLoader?.updateSingleFillPlacements(_singleFillPlacements);
  }

  String? _normalizeLayoutName(String? layoutName) {
    final value = layoutName?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  /// 批量更新默认广告位配置。
  void updateConfigs<K>(
    Map<K, List<AdInfoBean>> configs, {
    String Function(K placement)? placementLabelBuilder,
  }) {
    _defaultConfigs
      ..clear()
      ..addAll(_boxConfigs(configs));
    _ensureLoader<K>(placementLabelBuilder: placementLabelBuilder);
  }

  /// 更新单个默认广告位配置。
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

  /// 批量更新 Facebook 用户的广告位配置。
  void updateFacebookConfigs<K>(
    Map<K, List<AdInfoBean>> configs, {
    String Function(K placement)? placementLabelBuilder,
  }) {
    _facebookConfigs
      ..clear()
      ..addAll(_boxConfigs(configs));
    _ensureLoader<K>(placementLabelBuilder: placementLabelBuilder);
  }

  /// 更新单个 Facebook 用户广告位配置。
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

  /// 加载指定广告位并写入缓存。
  Future<LoadedAdCacheEntry?> loadPlacement<K>(
    K placement, {
    List<AdInfoBean>? configs,
    bool force = false,
    String Function(K placement)? placementLabelBuilder,
  }) async {
    final boxedPlacement = placement as Object;
    if (_isFengKongBlocked('load', boxedPlacement)) {
      return null;
    }
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    return _loadPlacementWithAudience(
      loader,
      boxedPlacement,
      configs: configs,
      force: force,
    );
  }

  /// 获取指定广告位的缓存条目。
  Future<LoadedAdCacheEntry?> getCachedEntry<K>(K placement) async {
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    return loader.getCachedEntry(placement as Object);
  }

  /// 获取指定广告位的缓存广告对象。
  Future<Ad?> getCachedAd<K>(K placement) async {
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    return loader.getCachedAd(placement as Object);
  }

  /// 获取指定广告位当前可用的缓存广告信息。
  ///
  /// 当缓存不存在、已过期，或当前不可用于展示时返回 `null`。
  Future<AdInfoBean?> getAvailableCachedAdInfo<K>(K placement) async {
    final boxedPlacement = placement as Object;
    if (_isFengKongBlocked('check-cache', boxedPlacement)) {
      return null;
    }
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    final cachedEntry = await loader.getCachedEntry(boxedPlacement);
    if (cachedEntry == null || cachedEntry.isExpired) {
      return null;
    }
    if (_isFengKongBlocked(
      'check-cache-entry',
      boxedPlacement,
      info: cachedEntry.info,
    )) {
      return null;
    }
    return cachedEntry.info;
  }

  /// 判断指定广告位当前是否满足展示条件。
  ///
  /// 仅判断配置和风控，不要求当前已有缓存。
  Future<bool> canDisplayPlacement<K>(K placement) async {
    final boxedPlacement = placement as Object;
    if (_isFengKongBlocked('check-display', boxedPlacement)) {
      return false;
    }
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    final cachedEntry = await loader.getCachedEntry(boxedPlacement);
    final info =
        cachedEntry?.info ??
        _pickPreferredAdInfo(await _resolveConfigsForPlacement(boxedPlacement));
    if (info == null) {
      return false;
    }
    if (_isFengKongBlocked('check-display-entry', boxedPlacement, info: info)) {
      return false;
    }
    return true;
  }

  /// 构建指定广告位的缓存广告组件。
  Future<Widget?> buildCachedAdWidget<K>(K placement) async {
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    final boxedPlacement = placement as Object;
    final cachedEntry = await loader.getCachedEntry(boxedPlacement);
    if (cachedEntry == null) {
      return null;
    }
    if (_isFengKongBlocked(
      'build-widget',
      boxedPlacement,
      info: cachedEntry.info,
    )) {
      return null;
    }
    return loader.buildCachedAdWidget(boxedPlacement);
  }

  /// 取出一个可直接消费的缓存广告组件。
  Future<Widget?> takeCachedAdWidget<K>(
    K placement, {
    bool loadIfNeeded = true,
    bool reloadAfterTake = false,
  }) async {
    final loader = _ensureLoader<K>();
    await _syncLoaderConfigs(loader);
    final boxedPlacement = placement as Object;
    LoadedAdCacheEntry? cachedEntry = await loader.getCachedEntry(
      boxedPlacement,
    );
    if (cachedEntry == null && loadIfNeeded) {
      cachedEntry = await _loadPlacementWithAudience(
        loader,
        boxedPlacement,
        configs: null,
        force: true,
      );
    }
    if (cachedEntry == null) {
      return null;
    }
    if (_isFengKongBlocked(
      'take-widget',
      boxedPlacement,
      info: cachedEntry.info,
    )) {
      return null;
    }
    final takenEntry = await loader.takeCachedEntry(
      boxedPlacement,
      reloadAfterTake: reloadAfterTake,
    );
    if (takenEntry == null) {
      return null;
    }
    if (takenEntry.ad is! AdWithView) {
      await takenEntry.dispose();
      return null;
    }
    _handleAdShowStartForAd(boxedPlacement, takenEntry.info, takenEntry.ad);
    return _ConsumableCachedAdWidget(entry: takenEntry);
  }

  /// 展示指定广告位的缓存广告。
  Future<bool> showCachedAd<K>(
    K placement, {
    BuildContext? context,
    OnUserEarnedRewardCallback? onUserEarnedReward,
  }) {
    final boxedPlacement = placement as Object;
    if (_isFengKongBlocked('show', boxedPlacement)) {
      return Future<bool>.value(false);
    }
    final loader = _ensureLoader<K>();
    return _showCachedAdWithAudience(
      loader,
      boxedPlacement,
      context: context,
      onUserEarnedReward: onUserEarnedReward,
    );
  }

  /// 预加载全部或指定广告位。
  Future<void> preloadAll<K>({
    Iterable<K>? placements,
    bool force = false,
    String Function(K placement)? placementLabelBuilder,
  }) async {
    if (_isFengKongBlocked(
      'preload',
      placements == null ? 'all' : placements.toList(growable: false),
    )) {
      return;
    }
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    await _syncLoaderConfigs(loader);
    final activeConfigs = await _resolveActiveConfigs();
    final targetPlacements =
        placements?.map((placement) => placement as Object).toList() ??
        activeConfigs.keys.toList(growable: false);
    final allowedPlacements = <Object>[];
    for (final placement in targetPlacements) {
      final canRequest = await _canRequestPlacement(
        placement,
        activeConfigs[placement],
        action: 'preload',
      );
      if (canRequest) {
        allowedPlacements.add(placement);
      } else {
        await loader.clearPlacementCache(placement);
      }
    }
    if (allowedPlacements.isEmpty) {
      return;
    }
    await loader.preloadAll(placements: allowedPlacements, force: force);
  }

  /// 清理指定广告位的缓存。
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
    if (_isFengKongBlocked('load', placement)) {
      return null;
    }
    await _syncLoaderConfigs(loader);
    final resolvedConfigs = await _resolveConfigsForLoad(placement, configs);
    final canRequest = await _canRequestPlacement(
      placement,
      resolvedConfigs,
      action: 'load',
    );
    if (!canRequest) {
      await loader.clearPlacementCache(placement);
      return null;
    }
    return loader.loadPlacement(
      placement,
      configs: resolvedConfigs,
      force: force,
    );
  }

  Future<bool> _canRequestPlacement(
    Object placement,
    List<AdInfoBean>? configs, {
    required String action,
  }) async {
    final info = _pickPreferredAdInfo(configs);
    if (info == null) {
      _logGeneral('$action-blocked placement=$placement reason=no-config');
      return false;
    }
    if (_isFengKongBlocked('$action-entry', placement, info: info)) {
      _logGeneral(
        '$action-blocked placement=$placement reason=fengkong-blocked',
      );
      return false;
    }
    return true;
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

  /// 加载后立即展示指定广告位。
  Future<bool> loadAndShow<K>(
    K placement, {
    BuildContext? context,
    List<AdInfoBean>? configs,
    bool forceReload = false,
    OnUserEarnedRewardCallback? onUserEarnedReward,
    String Function(K placement)? placementLabelBuilder,
  }) {
    final boxedPlacement = placement as Object;
    if (_isFengKongBlocked('load-and-show', boxedPlacement)) {
      return Future<bool>.value(false);
    }
    final loader = _ensureLoader<K>(
      placementLabelBuilder: placementLabelBuilder,
    );
    return _loadAndShowPlacement(
      loader,
      boxedPlacement,
      context: context,
      configs: configs,
      forceReload: forceReload,
      onUserEarnedReward: onUserEarnedReward,
    );
  }

  /// 释放加载器和所有广告缓存。
  Future<void> disposeLoader() async {
    final loader = _adLoader;
    _adLoader = null;
    _interstitialLikeNativePlacements.clear();
    _smallTemplateNativePlacements.clear();
    _largeBannerPlacements.clear();
    _collapsibleBannerDirections.clear();
    _placementLoadedListeners.clear();
    _showingPlacements.clear();
    _showingAdPlacements.clear();
    _singleFillPlacements.clear();
    AdUserGroupManager.instance.onUserGroupResolved = null;
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

  AdRequest _buildBannerRequest(Object placement, AdRequest defaultRequest) {
    final direction = _collapsibleBannerDirections[placement];
    if (direction == null || direction.isEmpty) {
      return defaultRequest;
    }
    return AdRequest(
      keywords: defaultRequest.keywords,
      contentUrl: defaultRequest.contentUrl,
      neighboringContentUrls: defaultRequest.neighboringContentUrls,
      nonPersonalizedAds: defaultRequest.nonPersonalizedAds,
      httpTimeoutMillis: defaultRequest.httpTimeoutMillis,
      extras: <String, String>{
        ...?defaultRequest.extras,
        'collapsible': direction,
      },
      mediationExtras: defaultRequest.mediationExtras,
    );
  }

  Future<void> _syncLoaderConfigs(
    FlutterPdfAdLoader<Object> loader, {
    bool clearExistingCache = false,
  }) async {
    final activeConfigs = await _resolveActiveConfigs();
    loader.updateConfigs(activeConfigs);
    final cachedPlacements = loader.cacheMap.keys.toList(growable: false);
    final placementsToClear = clearExistingCache
        ? cachedPlacements
        : cachedPlacements
              .where((placement) => !activeConfigs.containsKey(placement))
              .toList(growable: false);
    for (final placement in placementsToClear) {
      await loader.clearPlacementCache(placement);
      _logGeneral(
        clearExistingCache
            ? 'clear-cache-after-adjust-attribution placement=$placement'
            : 'clear-stale-cache placement=$placement',
      );
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

  AdInfoBean? _pickPreferredAdInfo(List<AdInfoBean>? configs) {
    if (configs == null || configs.isEmpty) {
      return null;
    }
    final sorted =
        configs
            .where(
              (config) => config.adId != null && config.parsedAdType != null,
            )
            .toList(growable: false)
          ..sort((left, right) => (right.sort ?? 0).compareTo(left.sort ?? 0));
    if (sorted.isEmpty) {
      return null;
    }
    return sorted.first;
  }

  Future<bool> _isFacebookUser() async {
    await AdAdjustManager.instance.restore();
    await AdReferrerManager.instance.restore();
    final referrer = AdReferrerManager.instance.cachedReferrer;
    final referrerContainsFacebook = _containsFacebook(referrer);
    final adjustContainsFacebook = AdAdjustManager.instance.containsFacebook();
    final isFacebookUser = referrerContainsFacebook || adjustContainsFacebook;

    final logSignature =
        'isFacebookUser=$isFacebookUser|'
        'referrerContainsFacebook=$referrerContainsFacebook|'
        'adjustContainsFacebook=$adjustContainsFacebook|'
        'referrer=${referrer ?? 'null'}|'
        'adjust=${AdAdjustManager.instance.summary()}';

    if (!kReleaseMode && _lastFacebookUserCheckLogSignature != logSignature) {
      _lastFacebookUserCheckLogSignature = logSignature;
      debugPrint(
        '[FlutterPdfAdPlugins] facebook-user-check '
        'isFacebookUser=$isFacebookUser '
        'referrerContainsFacebook=$referrerContainsFacebook '
        'adjustContainsFacebook=$adjustContainsFacebook '
        'referrer=${referrer ?? 'null'} '
        'adjust=${AdAdjustManager.instance.summary()}',
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
          if (groups.contains(0)) {
            return true;
          }
          if (groups.isEmpty) {
            return false;
          }
          if (userGroup == null) {
            return false;
          }
          return groups.contains(userGroup);
        })
        .toList(growable: false);

    final logSignature =
        'userGroup=${userGroup ?? 'null'}|'
        'before=${configs.length}|'
        'after=${filtered.length}';

    if (!kReleaseMode && _userGroupFilterLogCache[placement] != logSignature) {
      _userGroupFilterLogCache[placement] = logSignature;
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

  bool _isFengKongBlocked(String stage, Object placement, {AdInfoBean? info}) {
    final blocked = checkFengKong();
    if (!blocked) {
      return false;
    }
    if (info != null) {
      _log(stage, placement, info, extra: 'reason=fengkong-blocked');
    } else {
      _logGeneral(
        '$stage-blocked placement=$placement reason=fengkong-blocked',
      );
    }
    return true;
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

  void _notifyAdmobInitialized() {
    _logGeneral('notify onAdmobInitialized===${null == _listener}');
    _listener?.onAdmobInitialized();
  }

  void _notifyUserGroupResolved(int userGroup) {
    _logGeneral('notify onUserGroupResolved userGroup=$userGroup');
    _listener?.onUserGroupResolved(userGroup);
  }

  void _handleUmpConsentFlowStart(
    String countryCode,
    bool requiresCmpByLocale,
  ) {
    _listener?.onUmpConsentFlowStart(countryCode, requiresCmpByLocale);
  }

  void _handleUmpFormRequest() {
    _listener?.onUmpFormRequest();
  }

  void _handleUmpFormLoad() {
    _listener?.onUmpFormLoad();
  }

  void _handleUmpConsentFormShow() {
    _listener?.onUmpConsentFormShow();
  }

  void _handleUmpConsentFlowComplete(UmpConsentResult result) {
    _listener?.onUmpConsentFlowComplete(result);
  }

  void _handleUmpConsentCanRequestAds(bool canRequestAds) {
    _listener?.onUmpConsentCanRequestAds(canRequestAds);
  }

  void _handleAdRequestStart(Object placement, AdInfoBean info) {
    _listener?.onAdRequestStart(placement, info);
  }

  void _handleAdRequestSuccess(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {
    _listener?.onAdRequestSuccess(placement, info, adNetwork, adSourceName);
  }

  void _handleAdRequestFailure(
    Object placement,
    AdInfoBean info,
    String failReason,
    String adNetwork,
    String adSourceName,
  ) {
    _listener?.onAdRequestFailure(
      placement,
      info,
      failReason,
      adNetwork,
      adSourceName,
    );
  }

  void _handleAdShowStart(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {
    _listener?.onAdShowStart(placement, info, adNetwork, adSourceName);
  }

  void _handleAdShowSuccess(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {
    _listener?.onAdShowSuccess(placement, info, adNetwork, adSourceName);
  }

  void _handleAdShowFailure(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
    String errorMessage,
  ) {
    _listener?.onAdShowFailure(
      placement,
      info,
      adNetwork,
      adSourceName,
      errorMessage,
    );
  }

  void _handleAdClicked(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {
    _listener?.onAdClicked(placement, info, adNetwork, adSourceName);
  }

  void _handleAdClosed(
    Object placement,
    AdInfoBean info,
    String adNetwork,
    String adSourceName,
  ) {
    _listener?.onAdClosed(placement, info, adNetwork, adSourceName);
  }

  void _handleAdShowStartForAd(Object placement, AdInfoBean info, Ad? ad) {
    _handleAdShowStart(
      placement,
      info,
      _resolveAdNetwork(ad),
      _resolveAdSourceName(ad),
    );
  }

  void _handleAdShowSuccessForAd(Object placement, AdInfoBean info, Ad? ad) {
    _handleAdShowSuccess(
      placement,
      info,
      _resolveAdNetwork(ad),
      _resolveAdSourceName(ad),
    );
  }

  void _handleAdShowFailureForAd(
    Object placement,
    AdInfoBean info,
    Ad? ad,
    String errorMessage,
  ) {
    _handleAdShowFailure(
      placement,
      info,
      _resolveAdNetwork(ad),
      _resolveAdSourceName(ad),
      errorMessage,
    );
  }

  void _handleAdClosedForAd(Object placement, AdInfoBean info, Ad? ad) {
    _handleAdClosed(
      placement,
      info,
      _resolveAdNetwork(ad),
      _resolveAdSourceName(ad),
    );
  }

  Future<bool> _loadAndShowPlacement(
    FlutterPdfAdLoader<Object> loader,
    Object placement, {
    required BuildContext? context,
    required List<AdInfoBean>? configs,
    required bool forceReload,
    required OnUserEarnedRewardCallback? onUserEarnedReward,
  }) async {
    if (_isFengKongBlocked('load-and-show', placement)) {
      return false;
    }
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

    final entry = await _loadPlacementWithAudience(
      loader,
      placement,
      configs: configs,
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
    if (_isFengKongBlocked('show', placement)) {
      return false;
    }
    _logGeneral('show-start placement=$placement');

    var cachedEntry = loader.cacheMap[placement];
    if (cachedEntry == null) {
      _logGeneral('show-cache-miss placement=$placement');
      if (_skipReloadAfterClosePlacements.contains(placement)) {
        _logGeneral(
          'show-failed placement=$placement reason=no-cached-ad-skip-reload',
        );
        return false;
      }
      if (_isFengKongBlocked('load-on-show', placement)) {
        _logGeneral('show-failed placement=$placement reason=fengkong-blocked');
        return false;
      }
      unawaited(
        _loadPlacementWithAudience(
          loader,
          placement,
          configs: null,
          force: false,
        ),
      );
      _logGeneral('show-failed placement=$placement reason=no-cached-ad');
      return false;
    }

    if (cachedEntry.isExpired) {
      if (_skipReloadAfterClosePlacements.contains(placement)) {
        final failedInfo = cachedEntry.info;
        await loader.clearPlacementCache(placement);
        _log('show-expired', placement, failedInfo);
        _logGeneral(
          'show-failed placement=$placement reason=cache-expired-skip-reload',
        );
        _handleAdShowFailureForAd(
          placement,
          failedInfo,
          cachedEntry.ad,
          'cache-expired-skip-reload',
        );
        return false;
      }
      if (_isFengKongBlocked(
        'reload-expired',
        placement,
        info: cachedEntry.info,
      )) {
        _logGeneral('show-failed placement=$placement reason=fengkong-blocked');
        _handleAdShowFailureForAd(
          placement,
          cachedEntry.info,
          cachedEntry.ad,
          'fengkong-blocked',
        );
        return false;
      }
      unawaited(() async {
        await loader.clearPlacementCache(placement);
        await _loadPlacementWithAudience(
          loader,
          placement,
          configs: null,
          force: true,
        );
      }());
      _log('show-expired', placement, cachedEntry.info);
      _logGeneral('show-failed placement=$placement reason=cache-expired');
      _handleAdShowFailureForAd(
        placement,
        cachedEntry.info,
        cachedEntry.ad,
        'cache-expired',
      );
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
        _handleAdShowFailureForAd(
          placement,
          cachedEntry.info,
          cachedEntry.ad,
          'already-showing',
        );
        return false;
      }
      final shouldTrackShowing = _interstitialLikeNativePlacements.contains(
        placement,
      );
      if (shouldTrackShowing) {
        _showingAdPlacements.add(placement);
      }
      if (context == null) {
        _log('show-native-missing-context', placement, cachedEntry.info);
        _logGeneral(
          'show-failed placement=$placement reason=native-missing-context',
        );
        _showingPlacements.remove(placement);
        _showingAdPlacements.remove(placement);
        _handleAdShowFailureForAd(
          placement,
          cachedEntry.info,
          cachedEntry.ad,
          'native-missing-context',
        );
        return false;
      }
      if (!context.mounted) {
        _logGeneral(
          'show-failed placement=$placement reason=context-unmounted',
        );
        _showingPlacements.remove(placement);
        _showingAdPlacements.remove(placement);
        _handleAdShowFailureForAd(
          placement,
          cachedEntry.info,
          cachedEntry.ad,
          'context-unmounted',
        );
        return false;
      }

      try {
        final shown = await _showNativeAd(
          context,
          loader,
          placement,
          cachedEntry,
          onShown: () {
            _handleAdShowSuccessForAd(
              placement,
              cachedEntry.info,
              cachedEntry.ad,
            );
            _log(
              'show-success',
              placement,
              cachedEntry.info,
              extra: 'adType=native',
            );
          },
        );
        if (!shown.shown) {
          _log(
            'show-failed',
            placement,
            cachedEntry.info,
            extra:
                'adType=native '
                'reason=${shown.failureReason ?? 'unknown'}',
          );
          _handleAdShowFailureForAd(
            placement,
            cachedEntry.info,
            cachedEntry.ad,
            shown.failureReason ?? 'unknown',
          );
        }
        return shown.shown;
      } finally {
        _showingPlacements.remove(placement);
        _showingAdPlacements.remove(placement);
      }
    }

    _showingAdPlacements.add(placement);
    try {
      final shown = await loader.showCachedAdWithResult(
        placement,
        onUserEarnedReward: onUserEarnedReward,
      );
      if (shown.shown) {
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
        _handleAdShowFailureForAd(
          placement,
          cachedEntry.info,
          cachedEntry.ad,
          shown.failureReason ?? 'unknown',
        );
      }
      return shown.shown;
    } finally {
      _showingAdPlacements.remove(placement);
    }
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
    final adNetwork = _resolveAdNetwork(ad);
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
    final mockedRevenue =
        _debugMinRevenue +
        _debugRevenueRandom.nextDouble() *
            (_debugMaxRevenue - _debugMinRevenue);
    final mockedValueMicros = mockedRevenue * 1000000;
    _logGeneral(
      'paid-event-debug-mock '
      'originalValueMicros=$valueMicros '
      'mockedValueMicros=$mockedValueMicros '
      'mockedRevenue=$mockedRevenue',
    );
    return mockedValueMicros;
  }

  String _resolveAdNetwork(Ad? ad) {
    final adNetwork = ad?.responseInfo?.loadedAdapterResponseInfo?.adSourceName
        .trim();
    if (adNetwork == null || adNetwork.isEmpty) {
      return 'Admob';
    }
    return adNetwork;
  }

  String _resolveAdSourceName(Ad? ad) {
    return _resolveAdNetwork(ad);
  }

  Future<_ShowResult> _showNativeAd(
    BuildContext context,
    FlutterPdfAdLoader<Object> loader,
    Object placement,
    LoadedAdCacheEntry entry, {
    required VoidCallback onShown,
  }) async {
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
      _handleAdShowStartForAd(placement, entry.info, entry.ad);
      final routeFuture = navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => _NativeInterstitialPage(ad: ad),
          fullscreenDialog: true,
        ),
      );
      onShown();
      await routeFuture;
    } else {
      _handleAdShowStartForAd(placement, entry.info, entry.ad);
      final dialogFuture = showDialog<void>(
        context: navigator.context,
        useRootNavigator: true,
        builder: (_) => _NativeDialog(ad: ad),
      );
      onShown();
      await dialogFuture;
    }

    await loader.consumeShownEntryAfterClose(placement, entry);
    _handleAdClosedForAd(placement, entry.info, entry.ad);
    _log('native-closed-consume', placement, entry.info);
    return const _ShowResult.success();
  }

  void _log(String stage, Object placement, AdInfoBean? info, {String? extra}) {
    if (kReleaseMode) {
      return;
    }

    final buffer = StringBuffer()
      ..write('[FlutterPdfAdPlugins] $stage ')
      ..write('placement=$placement ')
      ..write('adInfo={${info?.logSummary}}');

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

  /// 执行风控拦截判断。
  bool checkFengKong() {
    if (null == _fengKongLogic) {
      return false;
    }
    return _fengKongLogic!();
  }
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            SizedBox.expand(child: AdWidget(ad: ad)),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  foregroundColor: Colors.white,
                  fixedSize: const Size.square(36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.close, size: 20),
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

class _ConsumableCachedAdWidget extends StatefulWidget {
  _ConsumableCachedAdWidget({required this.entry})
    : handle = _ConsumableAdHandle(entry);

  final LoadedAdCacheEntry entry;
  final _ConsumableAdHandle handle;

  @override
  State<_ConsumableCachedAdWidget> createState() =>
      _ConsumableCachedAdWidgetState();
}

class _ConsumableCachedAdWidgetState extends State<_ConsumableCachedAdWidget> {
  @override
  void initState() {
    super.initState();
    widget.handle.attach();
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.entry.ad;
    if (ad is! AdWithView) {
      return const SizedBox.shrink();
    }
    if (instanceManager.adIdFor(ad) == null) {
      debugPrint(
        '[FlutterPdfAdPlugins] skip-build-consumable-widget '
        'reason=ad-not-loaded-or-disposed adClass=${ad.runtimeType}',
      );
      return const SizedBox.shrink();
    }
    return AdWidget(ad: ad);
  }

  @override
  void dispose() {
    // Delay disposal a bit so list recycling / tab switches can reattach the
    // same widget without crashing, while still releasing stale ads.
    widget.handle.detach();
    super.dispose();
  }
}

class _ConsumableAdHandle {
  _ConsumableAdHandle(this.entry);

  static const Duration _disposeDelay = Duration(seconds: 2);

  final LoadedAdCacheEntry entry;
  int _attachCount = 0;
  Timer? _disposeTimer;
  bool _disposed = false;

  void attach() {
    if (_disposed) {
      return;
    }
    _attachCount++;
    _disposeTimer?.cancel();
    _disposeTimer = null;
  }

  void detach() {
    if (_disposed) {
      return;
    }
    _attachCount--;
    if (_attachCount > 0) {
      return;
    }
    _attachCount = 0;
    _disposeTimer?.cancel();
    _disposeTimer = Timer(_disposeDelay, () async {
      if (_disposed || _attachCount > 0) {
        return;
      }
      _disposed = true;
      _disposeTimer = null;
      await entry.dispose();
    });
  }
}
