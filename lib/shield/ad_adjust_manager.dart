import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

class AdAdjustManager {
  AdAdjustManager._();

  static final AdAdjustManager instance = AdAdjustManager._();

  static const String _storageContainer = 'flutter_pdf_ad_plugins_adjust';
  static const String _networkStorageKey = 'attribution_network';

  String? _network;
  Future<void>? _storageReadyFuture;
  Future<void>? _restoreFuture;
  GetStorage? _storage;
  bool _hasRestored = false;

  String? get network => _network;

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
      final localNetwork = _readLocalNetwork();
      if (_hasRestored) {
        return;
      }
      if (localNetwork == null) {
        _log('restore-empty');
      } else {
        _network = localNetwork;
        _log('restore network=$localNetwork');
      }
      _hasRestored = true;
    }();
    _restoreFuture = future;
    return future;
  }

  Future<bool> updateAttribution({String? network}) async {
    await _ensureStorageReady();
    final normalizedNetwork = (network ?? '').trim();
    final nextNetwork = normalizedNetwork.isEmpty ? null : normalizedNetwork;
    if (_network == nextNetwork) {
      _log('update-skip-same network=${nextNetwork ?? 'null'}');
      return false;
    }

    _network = nextNetwork;
    _hasRestored = true;
    if (nextNetwork == null) {
      await _storage?.remove(_networkStorageKey);
      _log('local-remove network=null');
    } else {
      await _storage?.write(_networkStorageKey, nextNetwork);
      _log('local-write network=$nextNetwork');
    }
    return true;
  }

  bool containsFacebook() {
    return (_network ?? '').toLowerCase().contains('facebook');
  }

  String summary() {
    return 'network=${_network ?? 'null'}';
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

  String? _readLocalNetwork() {
    final localValue = _storage?.read<String>(_networkStorageKey);
    return localValue == null || localValue.isEmpty ? null : localValue;
  }

  void _log(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[AdAdjustManager] $message');
  }
}
