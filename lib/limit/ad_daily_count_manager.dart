import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

class AdDailyCountManager {
  AdDailyCountManager._();

  static final AdDailyCountManager instance = AdDailyCountManager._();

  static const _container = 'flutter_pdf_ad_plugins_daily_count';
  static const _dateKey = 'date';
  static const _showCountKey = 'show_count';
  static const _clickCountKey = 'click_count';

  int? _maxShowCount;
  int? _maxClickCount;
  GetStorage? _storage;
  Future<void>? _storageReadyFuture;
  Future<void> _operationQueue = Future<void>.value();

  bool get hasLimit => _maxShowCount != null || _maxClickCount != null;

  void configure({required int? maxShowCount, required int? maxClickCount}) {
    _maxShowCount = _normalizeLimit(maxShowCount);
    _maxClickCount = _normalizeLimit(maxClickCount);
    _log(
      'configure maxShowCount=${_maxShowCount ?? 'unlimited'} '
      'maxClickCount=${_maxClickCount ?? 'unlimited'}',
    );
  }

  Future<bool> canLoadAd() {
    if (!hasLimit) {
      return Future<bool>.value(true);
    }
    return _enqueue(() async {
      await _ensureStorageReady();
      await _resetIfNewDay();
      final showCount = _readCount(_showCountKey);
      final clickCount = _readCount(_clickCountKey);
      final showLimitReached =
          _maxShowCount != null && showCount >= _maxShowCount!;
      final clickLimitReached =
          _maxClickCount != null && clickCount >= _maxClickCount!;
      final allowed = !showLimitReached && !clickLimitReached;
      _log('can-load=$allowed showCount=$showCount clickCount=$clickCount');
      return allowed;
    });
  }

  Future<void> recordShow() => _record(_showCountKey, 'show');

  Future<void> recordClick() => _record(_clickCountKey, 'click');

  Future<void> _record(String key, String type) {
    if (!hasLimit) {
      return Future<void>.value();
    }
    return _enqueue(() async {
      await _ensureStorageReady();
      await _resetIfNewDay();
      final count = _readCount(key) + 1;
      await _storage?.write(key, count);
      _log('record-$type count=$count');
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operationQueue.then((_) => operation());
    _operationQueue = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  Future<void> _ensureStorageReady() {
    final inFlight = _storageReadyFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final future = () async {
      await GetStorage.init(_container);
      _storage = GetStorage(_container);
    }();
    _storageReadyFuture = future;
    return future;
  }

  Future<void> _resetIfNewDay() async {
    final today = _todayKey();
    if (_storage?.read<String>(_dateKey) == today) {
      return;
    }
    await _storage?.write(_dateKey, today);
    await _storage?.write(_showCountKey, 0);
    await _storage?.write(_clickCountKey, 0);
    _log('reset date=$today');
  }

  int _readCount(String key) {
    final value = _storage?.read<dynamic>(key);
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int? _normalizeLimit(int? value) {
    if (value == null) {
      return null;
    }
    return value < 0 ? 0 : value;
  }

  void _log(String message) {
    if (!kReleaseMode) {
      debugPrint('[AdDailyCountManager] $message');
    }
  }
}
