import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../bean/ad_info_bean.dart';

class LoadedAdCacheEntry {
  LoadedAdCacheEntry({
    required this.info,
    required this.ad,
    required this.cachedAt,
    required this.requestOrder,
  });

  final AdInfoBean info;
  final Ad ad;
  final DateTime cachedAt;
  final int requestOrder;

  DateTime? get expireAt {
    final exportTime = info.exportTime;
    if (exportTime == null || exportTime <= 0) {
      return null;
    }
    return cachedAt.add(Duration(seconds: exportTime));
  }

  bool get isExpired {
    final expireAt = this.expireAt;
    if (expireAt == null) {
      return false;
    }
    return DateTime.now().isAfter(expireAt);
  }

  Future<void> dispose() async {
    await ad.dispose();
  }
}
