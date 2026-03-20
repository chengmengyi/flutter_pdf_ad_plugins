import 'package:google_mobile_ads/google_mobile_ads.dart';

class FlutterPdfAdPlugins {
  static final FlutterPdfAdPlugins _adPlugins = FlutterPdfAdPlugins();
  static FlutterPdfAdPlugins get instance => _adPlugins;

  Future<void> initAdmob() async {
    await MobileAds.instance.initialize();
  }
}
