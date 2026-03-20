import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_pdf_ad_plugins_platform_interface.dart';

/// An implementation of [FlutterPdfAdPluginsPlatform] that uses method channels.
class MethodChannelFlutterPdfAdPlugins extends FlutterPdfAdPluginsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_pdf_ad_plugins');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
