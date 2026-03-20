import 'dart:async';
import 'dart:io';

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

class AdReferrerManager {
  AdReferrerManager._();

  static final AdReferrerManager instance = AdReferrerManager._();

  static const int _maxImmediateRetryCount = 20;
  static const Duration _delayedRetryInterval = Duration(minutes: 5);
  static const String _storageContainer = 'flutter_pdf_ad_plugins_referrer';
  static const String _referrerStorageKey = 'install_referrer';

  String? _installReferrer;
  Future<String?>? _loadingFuture;
  Timer? _retryTimer;
  Future<void>? _storageReadyFuture;
  GetStorage? _storage;

  String? get cachedReferrer => _installReferrer;

  Future<String?> getReferrer() async {
    if (!Platform.isAndroid) {
      _log('skip-non-android');
      return null;
    }

    await _ensureStorageReady();

    if (_installReferrer != null) {
      _log('cached referrer=$_installReferrer');
      return _installReferrer;
    }

    final localReferrer = _readLocalReferrer();
    if (localReferrer != null && localReferrer.isNotEmpty) {
      _installReferrer = localReferrer;
      _log('local referrer=$localReferrer');
      return localReferrer;
    }

    final inFlight = _loadingFuture;
    if (inFlight != null) {
      _log('await-inflight');
      return inFlight;
    }

    final future = _loadReferrerInternal();
    _loadingFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_loadingFuture, future)) {
        _loadingFuture = null;
      }
    }
  }

  Future<String?> _loadReferrerInternal() async {
    for (var index = 0; index < _maxImmediateRetryCount; index++) {
      try {
        final details = await AndroidPlayInstallReferrer.installReferrer;
        final referrer = details.installReferrer;
        if (referrer != null && referrer.isNotEmpty) {
          _installReferrer = referrer;
          await _writeLocalReferrer(referrer);
          _retryTimer?.cancel();
          _retryTimer = null;
          _log('load-success referrer=$referrer attempt=${index + 1}');
          return referrer;
        }
      } catch (error) {
        _log('load-failed attempt=${index + 1} error=$error');
      }
    }

    _scheduleRetry();
    _log('load-empty referrer=${_installReferrer ?? 'null'}');
    return _installReferrer;
  }

  Future<void> _ensureStorageReady() {
    final inFlight = _storageReadyFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
      await GetStorage.init(_storageContainer);
      _storage = GetStorage(_storageContainer);
      _log('storage-ready');
    }();
    _storageReadyFuture = future;
    return future;
  }

  String? _readLocalReferrer() {
    final localValue = _storage?.read<String>(_referrerStorageKey);
    return localValue == null || localValue.isEmpty ? null : localValue;
  }

  Future<void> _writeLocalReferrer(String referrer) async {
    await _storage?.write(_referrerStorageKey, referrer);
    _log('local-write referrer=$referrer');
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) {
      return;
    }

    _retryTimer = Timer(_delayedRetryInterval, () {
      _retryTimer = null;
      _log('retry-start');
      unawaited(getReferrer());
    });
    _log('retry-scheduled interval=${_delayedRetryInterval.inMinutes}m');
  }

  void _log(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[AdReferrerManager] $message');
  }
}
