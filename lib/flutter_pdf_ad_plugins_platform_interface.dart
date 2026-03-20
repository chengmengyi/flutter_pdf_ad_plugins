import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_pdf_ad_plugins_method_channel.dart';

abstract class FlutterPdfAdPluginsPlatform extends PlatformInterface {
  /// Constructs a FlutterPdfAdPluginsPlatform.
  FlutterPdfAdPluginsPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterPdfAdPluginsPlatform _instance =
      MethodChannelFlutterPdfAdPlugins();

  /// The default instance of [FlutterPdfAdPluginsPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterPdfAdPlugins].
  static FlutterPdfAdPluginsPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterPdfAdPluginsPlatform] when
  /// they register themselves.
  static set instance(FlutterPdfAdPluginsPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
