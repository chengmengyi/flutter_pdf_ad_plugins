import 'package:google_mobile_ads/google_mobile_ads.dart';

class UmpConsentResult {
  const UmpConsentResult({
    required this.countryCode,
    required this.requiresCmpByLocale,
    required this.canRequestAds,
    required this.consentStatus,
    required this.privacyOptionsRequirementStatus,
    this.formError,
  });

  final String countryCode;
  final bool requiresCmpByLocale;
  final bool canRequestAds;
  final ConsentStatus consentStatus;
  final PrivacyOptionsRequirementStatus privacyOptionsRequirementStatus;
  final FormError? formError;
}
