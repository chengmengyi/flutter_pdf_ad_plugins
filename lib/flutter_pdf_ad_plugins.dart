import 'package:google_mobile_ads/google_mobile_ads.dart';

export 'bean/ad_info_bean.dart';
export 'enum/ad_placement.dart';
export 'enum/ad_type.dart';
export 'load/flutter_pdf_ad_loader.dart';
export 'load/loaded_ad_cache_entry.dart';

class FlutterPdfAdPlugins {
  static final FlutterPdfAdPlugins _adPlugins = FlutterPdfAdPlugins();
  static FlutterPdfAdPlugins get instance => _adPlugins;

  Future<void> initAdmob() async {
    await MobileAds.instance.initialize();
  }
}
