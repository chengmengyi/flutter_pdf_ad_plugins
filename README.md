# flutter_pdf_ad_plugins

`flutter_pdf_ad_plugins` 是一个基于 `google_mobile_ads` 的广告封装插件，提供了以下能力：

- AdMob 初始化
- 广告位配置管理
- 广告预加载与缓存
- Banner / Native / Interstitial / Rewarded / AppOpen 展示
- 收益回调与收益阈值事件
- Facebook 用户分流
- 风控、黑名单、referrer 屏蔽
- UMP 隐私授权流程

## 安装

在业务工程的 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  flutter_pdf_ad_plugins:
    git:
      url: https://github.com/chengmengyi/flutter_pdf_ad_plugins
```

然后执行：

```bash
flutter pub get
```

## 宿主工程准备

### 1. Android 配置 AdMob App ID

在业务工程的 `android/app/src/main/AndroidManifest.xml` 里添加：

```xml
<application>
    <meta-data
        android:name="com.google.android.gms.ads.APPLICATION_ID"
        android:value="ca-app-pub-xxxxxxxxxxxxxxxx~xxxxxxxxxx" />
</application>
```

### 2. iOS 配置 AdMob App ID

在业务工程的 `ios/Runner/Info.plist` 里添加：

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-xxxxxxxxxxxxxxxx~xxxxxxxxxx</string>
```

### 3. Adjust 可选

`initAdmob` 需要传入 `adjustAppToken`。如果你暂时不用 Adjust，可以传空字符串 `''`。

## 快速开始

### 1. 导入

```dart
import 'package:flutter/material.dart';
import 'package:flutter_pdf_ad_plugins/flutter_pdf_ad_plugins.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
```

### 2. 定义广告位

建议业务侧自己定义广告位枚举：

```dart
enum AdPlacement {
  splash,
  homeBanner,
  homeNative,
  chapterEndInterstitial,
  reward,
}
```

### 3. 初始化插件

通常在应用启动时初始化：

```dart
Future<void> initAds() async {
  final ad = FlutterPdfAdPlugins.instance;

  await ad.initAdmob(
    adjustAppToken: '',
    distinctId: 'user_10001',
    fengKongLogic: () {
      // 返回 true 表示命中风控，不允许请求或展示广告
      return false;
    },
  );
}
```

### 4. 可选：处理 UMP 隐私授权

如果你的投放地区需要 GDPR / CMP，可以在初始化后调用：

```dart
Future<void> initUmp() async {
  final result = await FlutterPdfAdPlugins.instance.handleUmpConsent();
  debugPrint('canRequestAds: ${result.canRequestAds}');
}
```

也可以先判断当前地区是否需要：

```dart
final needCmp = FlutterPdfAdPlugins.instance.shouldUseCmpForCurrentLocale();
```

## 广告位配置

### 1. 配置广告数据结构

插件使用 `AdInfoBean` 描述每一个广告配置：

```dart
final Map<AdPlacement, List<AdInfoBean>> configs = {
  AdPlacement.homeBanner: [
    AdInfoBean(
      adId: 'ca-app-pub-xxx/banner1',
      adType: AdType.banner.rawValue,
      sort: 100,
      exportTime: 3600,
      userGroup: [1, 2],
    ),
  ],
  AdPlacement.homeNative: [
    AdInfoBean(
      adId: 'ca-app-pub-xxx/native1',
      adType: AdType.native.rawValue,
      sort: 100,
      exportTime: 1800,
    ),
  ],
  AdPlacement.chapterEndInterstitial: [
    AdInfoBean(
      adId: 'ca-app-pub-xxx/interstitial1',
      adType: AdType.interstitial.rawValue,
      sort: 100,
      exportTime: 1800,
    ),
  ],
  AdPlacement.reward: [
    AdInfoBean(
      adId: 'ca-app-pub-xxx/reward1',
      adType: AdType.rewarded.rawValue,
      sort: 100,
      exportTime: 1800,
    ),
  ],
};
```

### 2. 下发配置到插件

```dart
void configAds() {
  final ad = FlutterPdfAdPlugins.instance;

  ad.updateConfigs<AdPlacement>(
    configs,
    placementLabelBuilder: (placement) => placement.name,
  );
}
```

### 3. 可选配置项

```dart
void configAdvancedOptions() {
  final ad = FlutterPdfAdPlugins.instance;

  // Native 按插屏样式展示，并参与冷却时间控制
  ad.updateInterstitialLikeNativePlacements([
    AdPlacement.homeNative,
  ]);

  // 某些 Native 使用小模板
  ad.updateSmallTemplateNativePlacements([
    AdPlacement.homeNative,
  ]);

  // 某些 Banner 使用大尺寸
  ad.updateLargeBannerPlacements([
    AdPlacement.homeBanner,
  ]);

  // 可折叠 Banner，方向一般传 top 或 bottom
  ad.updateCollapsibleBannerPlacements({
    AdPlacement.homeBanner: 'bottom',
  });

  // 需要经过屏蔽逻辑的广告位
  ad.updateShieldPlacements([
    AdPlacement.chapterEndInterstitial,
  ]);

  // 关闭后不自动补加载
  ad.updateSkipReloadAfterClosePlacements([
    AdPlacement.reward,
  ]);

  // 不同广告类型之间的冷却时间
  ad.updateProductCooldownSeconds(30);

  // 同一素材的冷却时间
  ad.updateInventoryCooldownSeconds(30);
}
```

## 广告加载与展示

### 1. 预加载广告

```dart
Future<void> preloadAds() async {
  await FlutterPdfAdPlugins.instance.preloadAll<AdPlacement>(
    placements: [
      AdPlacement.homeBanner,
      AdPlacement.homeNative,
      AdPlacement.chapterEndInterstitial,
    ],
  );
}
```

也可以加载单个广告位：

```dart
await FlutterPdfAdPlugins.instance.loadPlacement(AdPlacement.reward);
```

### 2. Banner / Native 直接构建缓存组件

适合已经预加载完成的场景：

```dart
class HomeBannerView extends StatelessWidget {
  const HomeBannerView({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget?>(
      future: FlutterPdfAdPlugins.instance.buildCachedAdWidget(
        AdPlacement.homeBanner,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        return snapshot.data!;
      },
    );
  }
}
```

### 3. 取出一个可消费的 Widget

这个接口会把缓存里的广告取出来，适合列表流里按需消费：

```dart
final widget = await FlutterPdfAdPlugins.instance.takeCachedAdWidget(
  AdPlacement.homeNative,
  loadIfNeeded: true,
  reloadAfterTake: true,
);
```

### 4. 展示缓存广告

适合插屏、激励、开屏，也支持原生广告弹窗展示：

```dart
final shown = await FlutterPdfAdPlugins.instance.showCachedAd(
  AdPlacement.chapterEndInterstitial,
  context: context,
);
```

激励广告可以监听奖励回调：

```dart
await FlutterPdfAdPlugins.instance.showCachedAd(
  AdPlacement.reward,
  onUserEarnedReward: (ad, reward) {
    debugPrint('reward: ${reward.amount} ${reward.type}');
  },
);
```

### 5. 加载后立即展示

如果你不确定缓存里有没有广告，可以直接调用：

```dart
final shown = await FlutterPdfAdPlugins.instance.loadAndShow(
  AdPlacement.chapterEndInterstitial,
  context: context,
);
```

## 收益与事件回调

推荐使用 `setListener` 统一监听：

```dart
class AdListener extends FlutterPdfAdListener {
  @override
  void onAdPaidEvent(
    Object placement,
    double revenue,
    String currencyCode,
    String adNetwork,
    String precisionType,
    AdInfoBean info,
  ) {
    debugPrint(
      'placement=$placement revenue=$revenue currency=$currencyCode network=$adNetwork',
    );
  }

  @override
  void onTachi25OneDayRevenueEvent(String eventName) {
    debugPrint('one day revenue event: $eventName');
  }

  @override
  void onTachi25TotalRevenueEvent(String eventName) {
    debugPrint('total revenue event: $eventName');
  }
}

void bindAdListener() {
  FlutterPdfAdPlugins.instance.setListener(AdListener());
}
```

### 收益阈值事件配置

```dart
FlutterPdfAdPlugins.instance.updateTachi25RevenueConfig({
  'reader_oneday_top10': 1.0,
  'reader_oneday_top20': 0.8,
  'reader_oneday_top30': 0.5,
  'reader_oneday_top40': 0.3,
  'reader_oneday_top50': 0.1,
});
```

## Facebook 用户配置

如果 Facebook 来源用户需要走另一套广告位配置，可以单独设置：

```dart
FlutterPdfAdPlugins.instance.updateFacebookConfigs<AdPlacement>({
  AdPlacement.homeBanner: [
    AdInfoBean(
      adId: 'ca-app-pub-xxx/facebook_banner',
      adType: AdType.banner.rawValue,
    ),
  ],
});
```

插件会结合 install referrer 和 Adjust attribution 判断是否为 Facebook 用户。

## 风控与屏蔽

### 1. 黑名单用户

```dart
FlutterPdfAdPlugins.instance.updateBlacklistStatus(true);
```

### 2. Referrer 屏蔽

```dart
FlutterPdfAdPlugins.instance.updateReferrerBlockConfig({
  'door': 1,
  'ilve': ['facebook', 'restricted_source'],
});
```

### 3. 检查当前是否正在展示广告

```dart
final showing = FlutterPdfAdPlugins.instance.isShowingAd();
```

## 调试能力

### 打开 Ad Inspector

```dart
final error = await FlutterPdfAdPlugins.instance.openAdInspector();
debugPrint('ad inspector error: $error');
```

### 设置调试收益区间

在 Debug 环境下，当收益为 0 时可模拟收益值：

```dart
FlutterPdfAdPlugins.instance.updateDebugPaidRevenueRange(
  minRevenue: 0.008,
  maxRevenue: 0.02,
);
```

## 常用接口速查

```dart
final ad = FlutterPdfAdPlugins.instance;

await ad.initAdmob(
  adjustAppToken: '',
  distinctId: 'user_10001',
  fengKongLogic: () => false,
);

ad.updateConfigs<AdPlacement>(configs);
await ad.preloadAll<AdPlacement>();

final banner = await ad.buildCachedAdWidget(AdPlacement.homeBanner);
final native = await ad.takeCachedAdWidget(AdPlacement.homeNative);
final shown = await ad.loadAndShow(
  AdPlacement.chapterEndInterstitial,
  context: context,
);
```

## 销毁

页面或业务模块结束时，如果需要释放缓存，可以调用：

```dart
await FlutterPdfAdPlugins.instance.disposeLoader();
```

## 注意事项

- `showCachedAd` 和 `loadAndShow` 在展示 Native 弹窗时需要传 `context`
- `takeCachedAdWidget` 适合列表流消费，取出后会从缓存中移除
- `buildCachedAdWidget` 只是读取当前缓存，不会移除缓存
- `getAndroidId()` 只有 Android 有值，iOS 会返回 `null`
- 如果广告位配置里设置了 `exportTime`，缓存到期后会自动失效
- `userGroup` 为空时表示全部用户可用

