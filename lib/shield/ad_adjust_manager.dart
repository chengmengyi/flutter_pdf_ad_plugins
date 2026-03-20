import 'dart:async';

import 'package:adjust_sdk/adjust.dart';
import 'package:adjust_sdk/adjust_attribution.dart';
import 'package:adjust_sdk/adjust_config.dart';
import 'package:adjust_sdk/adjust_event_success.dart';
import 'package:flutter/foundation.dart';

class AdAdjustManager {
  AdAdjustManager._();

  static final AdAdjustManager instance = AdAdjustManager._();

  AdjustAttribution? _cachedAttribution;
  Completer<AdjustAttribution?>? _attributionCompleter;
  String? _initializedAppToken;
  String _initializedDistinctId = '';
  bool _hasInitialized = false;

  Future<void> initialize({
    required String appToken,
    String? distinctId,
  }) async {
    final normalizedAppToken = appToken.trim();
    final normalizedDistinctId = (distinctId ?? '').trim();

    if (normalizedAppToken.isEmpty) {
      _log('init-skip-empty-app-token');
      return;
    }

    if (_hasInitialized &&
        _initializedAppToken == normalizedAppToken &&
        _initializedDistinctId == normalizedDistinctId) {
      _log(
        'init-skip-same-config appToken=$normalizedAppToken '
        'distinctId=${normalizedDistinctId.isEmpty ? 'empty' : normalizedDistinctId}',
      );
      return;
    }

    _hasInitialized = true;
    _initializedAppToken = normalizedAppToken;
    _initializedDistinctId = normalizedDistinctId;
    _attributionCompleter = Completer<AdjustAttribution?>();

    try {
      Adjust.removeGlobalCallbackParameter('customer_user_id');
      if (normalizedDistinctId.isNotEmpty) {
        Adjust.addGlobalCallbackParameter(
          'customer_user_id',
          normalizedDistinctId,
        );
      }

      final adjustConfig = AdjustConfig(
        normalizedAppToken,
        AdjustEnvironment.production,
      );
      adjustConfig.attributionCallback =
          (AdjustAttribution attributionChangedData) {
            _cachedAttribution = attributionChangedData;
            _log('attribution-callback ${summary(attributionChangedData)}');
            final completer = _attributionCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.complete(attributionChangedData);
            }
          };
      adjustConfig.eventSuccessCallback =
          (AdjustEventSuccess eventSuccessData) {
            _log(
              'event-success eventToken=${eventSuccessData.eventToken}, '
              'message=${eventSuccessData.message}, '
              'callbackId=${eventSuccessData.callbackId}',
            );
          };

      _log(
        'init-sdk-start appToken=$normalizedAppToken '
        'distinctId=${normalizedDistinctId.isEmpty ? 'empty' : normalizedDistinctId}',
      );
      Adjust.initSdk(adjustConfig);
      _log('init-sdk-finished');
    } catch (error) {
      _log('init-sdk-failed error=$error');
      final completer = _attributionCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(null);
      }
    }
  }

  Future<AdjustAttribution?> getAttribution({
    Duration waitTimeout = Duration.zero,
  }) async {
    final cached = _cachedAttribution;
    if (cached != null) {
      _log('cached ${summary(cached)}');
      return cached;
    }

    if (!_hasInitialized) {
      _log('get-attribution-before-init');
      return null;
    }

    if (waitTimeout <= Duration.zero) {
      _log('get-attribution-no-cache');
      return null;
    }

    final completer = _attributionCompleter ??= Completer<AdjustAttribution?>();
    try {
      return await completer.future.timeout(
        waitTimeout,
        onTimeout: () {
          _log('await-timeout timeoutMs=${waitTimeout.inMilliseconds}');
          return _cachedAttribution;
        },
      );
    } catch (error) {
      _log('await-failed error=$error');
      return _cachedAttribution;
    }
  }

  bool containsFacebook(AdjustAttribution? attribution) {
    if (attribution == null) {
      return false;
    }

    return (attribution.network ?? '').toLowerCase().contains('facebook');
  }

  String summary(AdjustAttribution? attribution) {
    if (attribution == null) {
      return 'null';
    }

    return 'network=${attribution.network}';
  }

  void _log(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[AdAdjustManager] $message');
  }
}
