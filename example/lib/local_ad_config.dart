import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const String _androidLocalAdConfigPath =
    'assets/admob_test_config_android.json';
const String _iosLocalAdConfigPath = 'assets/admob_test_config_ios.json';

String get localAdConfigAssetPath =>
    Platform.isIOS ? _iosLocalAdConfigPath : _androidLocalAdConfigPath;

Future<Map<String, dynamic>> loadLocalAdConfig() async {
  final jsonString = await rootBundle.loadString(localAdConfigAssetPath);
  return jsonDecode(jsonString) as Map<String, dynamic>;
}
