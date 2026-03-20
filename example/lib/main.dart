import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_pdf_ad_plugins/flutter_pdf_ad_plugins.dart';

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
  String? _configPath;
  int _placementCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfig());
  }

  Future<void> _loadConfig() async {
    try {
      final config = await loadLocalAdConfig();
      if (!mounted) {
        return;
      }
      setState(() {
        _configStatus = '已加载本地广告配置';
        _configPath = localAdConfigAssetPath;
        _placementCount = config.length;
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
                Text('当前配置文件: ${_configPath ?? "-"}'),
                const SizedBox(height: 8),
                Text('广告位数量: $_placementCount'),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _initAdmob,
                  child: const Text('初始化admob'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
