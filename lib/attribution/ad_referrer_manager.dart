import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

class AdReferrerManager {
  AdReferrerManager._();

  static final AdReferrerManager instance = AdReferrerManager._();

  static const String _storageContainer = 'flutter_pdf_ad_plugins_referrer';
  static const String _referrerStorageKey = 'install_referrer';

  String? _installReferrer;
  Future<void>? _storageReadyFuture;
  Future<void>? _restoreFuture;
  GetStorage? _storage;
  bool _hasRestored = false;

  String? get cachedReferrer => _installReferrer;

  Future<void> restore() async {
    if (_hasRestored) {
      return;
    }

    final inFlight = _restoreFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
      await _ensureStorageReady();
      if (_hasRestored) {
        return;
      }
      final localReferrer = _readLocalReferrer();
      if (_hasRestored) {
        return;
      }
      if (localReferrer == null) {
        _log('restore-empty');
      } else {
        _installReferrer = localReferrer;
        _log('restore referrer=$localReferrer');
      }
      _hasRestored = true;
    }();
    _restoreFuture = future;
    return future;
  }

  Future<bool> updateReferrer({String? referrer}) async {
    await _ensureStorageReady();
    final normalizedReferrer = (referrer ?? '').trim();
    final nextReferrer = normalizedReferrer.isEmpty ? null : normalizedReferrer;
    if (_installReferrer == nextReferrer) {
      _log('update-skip-same referrer=${nextReferrer ?? 'null'}');
      return false;
    }

    _installReferrer = nextReferrer;
    _hasRestored = true;
    if (nextReferrer == null) {
      await _storage?.remove(_referrerStorageKey);
      _log('local-remove referrer=null');
    } else {
      await _storage?.write(_referrerStorageKey, nextReferrer);
      _log('local-write referrer=$nextReferrer');
    }
    return true;
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

  void _log(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[AdReferrerManager] $message');
  }
}
