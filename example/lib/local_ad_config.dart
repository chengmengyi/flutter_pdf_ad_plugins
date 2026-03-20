import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_pdf_ad_plugins/flutter_pdf_ad_plugins.dart';

const String _androidLocalAdConfigPath =
    'assets/admob_test_config_android.json';
const String _iosLocalAdConfigPath = 'assets/admob_test_config_ios.json';

String get localAdConfigAssetPath =>
    Platform.isIOS ? _iosLocalAdConfigPath : _androidLocalAdConfigPath;

Future<Map<String, dynamic>> loadLocalAdConfig() async {
  final jsonString = await rootBundle.loadString(localAdConfigAssetPath);
  return jsonDecode(jsonString) as Map<String, dynamic>;
}

Future<Map<AdPlacement, List<AdInfoBean>>> loadLocalPlacementConfigs() async {
  final rawConfig = await loadLocalAdConfig();
  return parseLocalPlacementConfigs(rawConfig);
}

Map<AdPlacement, List<AdInfoBean>> parseLocalPlacementConfigs(
  Map<String, dynamic> rawConfig,
) {
  final result = <AdPlacement, List<AdInfoBean>>{};

  for (final entry in rawConfig.entries) {
    final placement = AdPlacementX.tryParse(entry.key);
    final value = entry.value;
    if (placement == null || value is! List) {
      continue;
    }

    result[placement] = value
        .whereType<Map>()
        .map(
          (item) =>
              AdInfoBean.fromPlacementJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  return result;
}
