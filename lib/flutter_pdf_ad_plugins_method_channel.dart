import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_pdf_ad_plugins_platform_interface.dart';

/// An implementation of [FlutterPdfAdPluginsPlatform] that uses method channels.
class MethodChannelFlutterPdfAdPlugins extends FlutterPdfAdPluginsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_pdf_ad_plugins');

  @visibleForTesting
  final nativeAdHeadlineEventChannel = const EventChannel(
    'flutter_pdf_ad_plugins/native_ad_headline',
  );

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<String?> getAndroidId() async {
    return methodChannel.invokeMethod<String>('getAndroidId');
  }

  @override
  Future<void> configureSmallNativeAdLayout(String? layoutName) async {
    await methodChannel.invokeMethod<void>('configureSmallNativeAdLayout', {
      'layoutName': layoutName,
    });
  }

  @override
  Stream<Map<String, dynamic>> get nativeAdHeadlineStream =>
      nativeAdHeadlineEventChannel
          .receiveBroadcastStream()
          .where((dynamic event) => event is Map)
          .map((dynamic event) => Map<String, dynamic>.from(event as Map));

  @override
  Future<bool> closeFullScreenAd() async {
    return await methodChannel.invokeMethod<bool>('closeFullScreenAd') ?? false;
  }

  @override
  Future<void> updateCloseableFullScreenAdActivityNames(
    Iterable<String> activityNames,
  ) async {
    await methodChannel.invokeMethod<void>(
      'updateCloseableFullScreenAdActivityNames',
      {'activityNames': activityNames.toList(growable: false)},
    );
  }
}
