import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

class AdRevenueManager {
  AdRevenueManager._();

  static final AdRevenueManager instance = AdRevenueManager._();

  static const String _storageContainer = 'flutter_pdf_ad_plugins_revenue';
  static const String _dailyDateKey = 'daily_revenue_date';
  static const String _dailyRevenueKey = 'daily_revenue_amount';
  static const String _dailyTriggeredKey = 'daily_revenue_triggered_events';
  static const String _totalRevenueKey = 'total_revenue_amount';
  static const String _totalTriggeredKey = 'total_revenue_triggered_events';

  static const Map<String, String> _dailyConfigEventMap = <String, String>{
    'reader_oneday_top10': 'AdLTV_OneDay_Top10Percent',
    'reader_oneday_top20': 'AdLTV_OneDay_Top20Percent',
    'reader_oneday_top30': 'AdLTV_OneDay_Top30Percent',
    'reader_oneday_top40': 'AdLTV_OneDay_Top40Percent',
    'reader_oneday_top50': 'AdLTV_OneDay_Top50Percent',
  };

  static const Map<String, double> _totalRevenueThresholds = <String, double>{
    'Adecpm_OneDay_100': 100,
    'Adecpm_OneDay_150': 150,
    'Adecpm_OneDay_200': 200,
  };

  Future<void>? _storageReadyFuture;
  GetStorage? _storage;
  Map<String, double> _dailyThresholds = <String, double>{};

  bool get isEnabled => _dailyThresholds.isNotEmpty;

  void updateDailyThresholdConfig(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      _dailyThresholds = <String, double>{};
      _log('update-config disabled');
      return;
    }

    final thresholds = <String, double>{};
    for (final entry in _dailyConfigEventMap.entries) {
      final value = _toDouble(json[entry.key]);
      if (value == null || value <= 0) {
        continue;
      }
      thresholds[entry.value] = value;
    }
    _dailyThresholds = thresholds;
    _log('update-config thresholds=$_dailyThresholds');
  }

  Future<AdRevenueRecordResult> recordRevenue(double revenue) async {
    if (!isEnabled || revenue <= 0) {
      return const AdRevenueRecordResult(
        revenue: 0,
        dailyRevenue: 0,
        totalRevenue: 0,
        triggeredEvents: <String>[],
      );
    }

    await _ensureStorageReady();
    await _rollDailyIfNeeded();

    final dailyRevenue = (_readDouble(_dailyRevenueKey) ?? 0) + revenue;
    final totalRevenue = (_readDouble(_totalRevenueKey) ?? 0) + revenue;
    await _storage?.write(_dailyRevenueKey, dailyRevenue);
    await _storage?.write(_totalRevenueKey, totalRevenue);

    final triggeredEvents = <String>[];
    triggeredEvents.addAll(await _consumeDailyThresholds(dailyRevenue));
    triggeredEvents.addAll(await _consumeTotalThresholds(totalRevenue));

    _log(
      'record-revenue revenue=$revenue '
      'dailyRevenue=$dailyRevenue totalRevenue=$totalRevenue '
      'triggered=$triggeredEvents',
    );

    return AdRevenueRecordResult(
      revenue: revenue,
      dailyRevenue: dailyRevenue,
      totalRevenue: totalRevenue,
      triggeredEvents: triggeredEvents,
    );
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

  Future<void> _rollDailyIfNeeded() async {
    final today = _todayKey();
    final localDate = _storage?.read<String>(_dailyDateKey);
    if (localDate == today) {
      return;
    }

    await _storage?.write(_dailyDateKey, today);
    await _storage?.write(_dailyRevenueKey, 0.0);
    await _storage?.write(_dailyTriggeredKey, <String>[]);
    _log('daily-rollover date=$today previousDate=${localDate ?? 'null'}');
  }

  Future<List<String>> _consumeDailyThresholds(double dailyRevenue) async {
    final triggered = _readStringSet(_dailyTriggeredKey);
    final newlyTriggered = <String>[];
    final sortedEntries = _dailyThresholds.entries.toList(growable: false)
      ..sort((left, right) => left.value.compareTo(right.value));

    for (final entry in sortedEntries) {
      if (dailyRevenue < entry.value || triggered.contains(entry.key)) {
        continue;
      }
      triggered.add(entry.key);
      newlyTriggered.add(entry.key);
    }

    if (newlyTriggered.isNotEmpty) {
      await _storage?.write(
        _dailyTriggeredKey,
        triggered.toList(growable: false),
      );
    }
    return newlyTriggered;
  }

  Future<List<String>> _consumeTotalThresholds(double totalRevenue) async {
    final triggered = _readStringSet(_totalTriggeredKey);
    final newlyTriggered = <String>[];
    final sortedEntries = _totalRevenueThresholds.entries.toList(
      growable: false,
    )..sort((left, right) => left.value.compareTo(right.value));

    for (final entry in sortedEntries) {
      if (totalRevenue < entry.value || triggered.contains(entry.key)) {
        continue;
      }
      triggered.add(entry.key);
      newlyTriggered.add(entry.key);
    }

    if (newlyTriggered.isNotEmpty) {
      await _storage?.write(
        _totalTriggeredKey,
        triggered.toList(growable: false),
      );
    }
    return newlyTriggered;
  }

  Set<String> _readStringSet(String key) {
    final raw = _storage?.read<List<dynamic>>(key) ?? const <dynamic>[];
    return raw.map((value) => value.toString()).toSet();
  }

  double? _readDouble(String key) {
    return _toDouble(_storage?.read<dynamic>(key));
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  void _log(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[AdRevenueManager] $message');
  }
}

class AdRevenueRecordResult {
  const AdRevenueRecordResult({
    required this.revenue,
    required this.dailyRevenue,
    required this.totalRevenue,
    required this.triggeredEvents,
  });

  final double revenue;
  final double dailyRevenue;
  final double totalRevenue;
  final List<String> triggeredEvents;
}

double? _toDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is int) {
    return value.toDouble();
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
