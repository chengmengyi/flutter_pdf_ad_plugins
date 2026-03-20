import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_pdf_ad_plugins/flutter_pdf_ad_plugins.dart';

import 'ad_placement.dart';
import 'local_ad_config.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const Map<String, double> _tachi25RevenueConfig = <String, double>{
    'reader_oneday_top10': 1,
    'reader_oneday_top20': 0.8,
    'reader_oneday_top30': 0.6,
    'reader_oneday_top40': 0.5,
    'reader_oneday_top50': 0.1,
  };

  String _configStatus = '正在读取本地广告配置...';
  String _startupStatus = '等待启动流程...';
  String _umpStatus = 'UMP 未执行';
  String _preloadStatus = '开屏广告未预加载';
  String _oneDayRevenueEvent = '单日收入回调未触发';
  String _totalRevenueEvent = '累计收入回调未触发';
  String? _configPath;
  int _placementCount = 0;
  int _adUnitCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(FlutterPdfAdPlugins.instance.disposeLoader());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadConfig();
    await _runStartupFlow();
  }

  Future<void> _loadConfig() async {
    try {
      final configs = await loadLocalPlacementConfigs();
      FlutterPdfAdPlugins.instance.updateTachi25RevenueConfig(
        _tachi25RevenueConfig,
      );
      FlutterPdfAdPlugins.instance.setOnTachi25OneDayRevenueEvent((eventName) {
        if (!mounted) {
          return;
        }
        setState(() {
          _oneDayRevenueEvent = eventName;
        });
      });
      FlutterPdfAdPlugins.instance.setOnTachi25TotalRevenueEvent((eventName) {
        if (!mounted) {
          return;
        }
        setState(() {
          _totalRevenueEvent = eventName;
        });
      });
      FlutterPdfAdPlugins.instance.updateInterstitialLikeNativePlacements(
        const [AdPlacement.prMainTools],
      );
      FlutterPdfAdPlugins.instance.updateConfigs<AdPlacement>(
        configs,
        placementLabelBuilder: (placement) => placement.jsonKey,
      );
      final adUnitCount = configs.values.fold<int>(
        0,
        (total, items) => total + items.length,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _configStatus = '已加载本地广告配置';
        _configPath = localAdConfigAssetPath;
        _placementCount = configs.length;
        _adUnitCount = adUnitCount;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _configStatus = '读取失败: $error';
      });
    }
  }

  Future<void> _runStartupFlow() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _startupStatus = '正在处理 UMP -> 初始化 AdMob -> 预加载开屏广告';
    });

    final umpResult = await FlutterPdfAdPlugins.instance.handleUmpConsent();
    if (!mounted) {
      return;
    }
    setState(() {
      _umpStatus =
          'UMP: country=${umpResult.countryCode.isEmpty ? '-' : umpResult.countryCode}, '
          'requiresCmp=${umpResult.requiresCmpByLocale}, '
          'canRequestAds=${umpResult.canRequestAds}, '
          'consent=${umpResult.consentStatus.name}';
    });

    await FlutterPdfAdPlugins.instance.initAdmob();
    await FlutterPdfAdPlugins.instance.preloadAll<AdPlacement>(
      placements: const [AdPlacement.prNewLaunch, AdPlacement.prLaunch],
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _startupStatus = '启动流程完成';
      _preloadStatus = '已预加载 pr_new_launch 和 pr_launch';
    });
  }

  Future<void> _initAdmob(BuildContext context) async {
    await FlutterPdfAdPlugins.instance.initAdmob();
    if (!mounted || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('AdMob 已初始化')));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (appContext) => Scaffold(
          appBar: AppBar(title: const Text('Plugin example app')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_configStatus),
                  const SizedBox(height: 8),
                  Text(_startupStatus),
                  const SizedBox(height: 8),
                  Text(_umpStatus),
                  const SizedBox(height: 8),
                  Text(_preloadStatus),
                  const SizedBox(height: 8),
                  Text('单日收入回调: $_oneDayRevenueEvent'),
                  const SizedBox(height: 8),
                  Text('累计收入回调: $_totalRevenueEvent'),
                  const SizedBox(height: 8),
                  Text('当前配置文件: ${_configPath ?? "-"}'),
                  const SizedBox(height: 8),
                  Text('广告位数量: $_placementCount'),
                  const SizedBox(height: 8),
                  Text('广告单元数量: $_adUnitCount'),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _runStartupFlow,
                    child: const Text('执行启动流程'),
                  ),
                  TextButton(
                    onPressed: () => _initAdmob(appContext),
                    child: const Text('初始化admob'),
                  ),
                  TextButton(
                    onPressed: () {
                      FlutterPdfAdPlugins.instance.preloadAll<AdPlacement>(
                        placements: const [
                          AdPlacement.prLaunch,
                          AdPlacement.prNewGuideNat1,
                        ],
                      );
                    },
                    child: const Text('加载pr_launch和pr_new_guide_nat1'),
                  ),
                  TextButton(
                    onPressed: () {
                      FlutterPdfAdPlugins.instance.showCachedAd(
                        AdPlacement.prLaunch,
                        context: appContext,
                      );
                    },
                    child: const Text('显示pr_launch'),
                  ),
                  TextButton(
                    onPressed: () {
                      FlutterPdfAdPlugins.instance.preloadAll<AdPlacement>(
                        placements: const [AdPlacement.prMainTools],
                      );
                    },
                    child: const Text('加载prMainTools'),
                  ),
                  TextButton(
                    onPressed: () {
                      FlutterPdfAdPlugins.instance.showCachedAd(
                        AdPlacement.prMainTools,
                        context: appContext,
                        enableNativeCooldown: true,
                      );
                    },
                    child: const Text('显示prMainTools'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
