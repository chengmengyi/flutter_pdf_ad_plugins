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
  String _configStatus = '正在读取本地广告配置...';
  String _startupStatus = '等待启动流程...';
  String _umpStatus = 'UMP 未执行';
  String _preloadStatus = '开屏广告未预加载';
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

  Future<void> _initAdmob() async {
    await FlutterPdfAdPlugins.instance.initAdmob();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('AdMob 已初始化')));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
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
                  onPressed: _initAdmob,
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
                      context: context,
                    );
                  },
                  child: const Text('显示pr_launch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
