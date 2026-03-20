import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';

import '../flutter_pdf_ad_plugins_platform_interface.dart';

class AdUserGroupManager {
  AdUserGroupManager._();

  static final AdUserGroupManager instance = AdUserGroupManager._();
  static const String _storageContainer = 'flutter_pdf_ad_plugins_user_group';
  static const String _userGroupStorageKey = 'ad_user_group';
  static const String _userGroupVersionStorageKey = 'ad_user_group_version';
  static const int _currentUserGroupVersion = 2;

  String? _cachedAndroidId;
  int? _cachedUserGroup;
  Future<String?>? _androidIdTask;
  Future<int?>? _userGroupTask;
  Future<void>? _storageReadyFuture;
  GetStorage? _storage;

  Future<String?> getAndroidId() async {
    final cachedAndroidId = _cachedAndroidId;
    if (cachedAndroidId != null && cachedAndroidId.isNotEmpty) {
      _log('android-id-cached androidId=$cachedAndroidId');
      return cachedAndroidId;
    }

    final inFlight = _androidIdTask;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadAndroidIdInternal();
    _androidIdTask = future;
    try {
      return await future;
    } finally {
      if (identical(_androidIdTask, future)) {
        _androidIdTask = null;
      }
    }
  }

  Future<int?> getUserGroup() async {
    final cachedUserGroup = _cachedUserGroup;
    if (cachedUserGroup != null) {
      _log('user-group-cached userGroup=$cachedUserGroup');
      return cachedUserGroup;
    }

    if (!Platform.isAndroid) {
      _log('user-group-skip platform=${Platform.operatingSystem}');
      return null;
    }

    await _ensureStorageReady();

    final localUserGroup = _readLocalUserGroup();
    if (localUserGroup != null) {
      _cachedUserGroup = localUserGroup;
      _log('user-group-local userGroup=$localUserGroup');
      return localUserGroup;
    }

    final inFlight = _userGroupTask;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadUserGroupInternal();
    _userGroupTask = future;
    try {
      return await future;
    } finally {
      if (identical(_userGroupTask, future)) {
        _userGroupTask = null;
      }
    }
  }

  Future<String?> _loadAndroidIdInternal() async {
    if (!Platform.isAndroid) {
      _log('android-id-skip platform=${Platform.operatingSystem}');
      return null;
    }

    try {
      final androidId =
          (await FlutterPdfAdPluginsPlatform.instance.getAndroidId())?.trim();
      if (androidId == null || androidId.isEmpty) {
        _log('android-id-empty');
        return null;
      }
      _cachedAndroidId = androidId;
      _log('android-id-success androidId=$androidId');
      return androidId;
    } catch (error) {
      _log('android-id-failed error=$error');
      return null;
    }
  }

  Future<int?> _loadUserGroupInternal() async {
    final androidId = await getAndroidId();
    if (androidId == null || androidId.isEmpty) {
      _log('user-group-skip-empty-android-id');
      return null;
    }

    final userGroup = _calculateUserGroup(androidId);
    _cachedUserGroup = userGroup;
    await _writeLocalUserGroup(userGroup);
    _log('user-group-success androidId=$androidId userGroup=$userGroup');
    return userGroup;
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

  int? _readLocalUserGroup() {
    final localVersion = _toInt(
      _storage?.read<dynamic>(_userGroupVersionStorageKey),
    );
    if (localVersion != _currentUserGroupVersion) {
      _log(
        'user-group-local-version-mismatch '
        'localVersion=${localVersion ?? 'null'} '
        'currentVersion=$_currentUserGroupVersion',
      );
      return null;
    }

    final localValue = _storage?.read<dynamic>(_userGroupStorageKey);
    final parsed = _toInt(localValue);
    if (parsed == null || parsed < 1 || parsed > 8) {
      return null;
    }
    return parsed;
  }

  Future<void> _writeLocalUserGroup(int userGroup) async {
    await _storage?.write(_userGroupStorageKey, userGroup);
    await _storage?.write(
      _userGroupVersionStorageKey,
      _currentUserGroupVersion,
    );
    _log('user-group-local-write userGroup=$userGroup');
  }

  int _calculateUserGroup(String androidId) {
    var hash = 0;
    for (final codeUnit in androidId.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0xffffffff;
      if (hash >= 0x80000000) {
        hash -= 0x100000000;
      }
    }
    return hash.remainder(8).abs() + 1;
  }

  void _log(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[AdUserGroupManager] $message');
  }
}

int? _toInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
