import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyuCookieSaveException implements Exception {
  const DouyuCookieSaveException(this.cause, {this.rollbackRevision});

  final Object cause;

  /// The user revision restored by this write, only when it owned the rollback.
  final int? rollbackRevision;

  @override
  String toString() => 'DouyuCookieSaveException: Cookie persistence failed';
}

enum DouyuAccountRefreshStatus {
  unconfigured,
  missingRefreshCredentials,
  waiting,
  failure,
  refreshed,
}

typedef DouyuAccountPeriodicTimerFactory = Timer Function(
  Duration interval,
  void Function() onTick,
);

class DouyuAccountService extends GetxService with WidgetsBindingObserver {
  DouyuAccountService({
    DouyuSite? site,
    LocalStorageService? storage,
    DateTime Function()? clock,
    DouyuAccountPeriodicTimerFactory? periodicTimerFactory,
    Duration refreshCheckInterval = const Duration(minutes: 1),
  })  : _siteOverride = site,
        _storageOverride = storage,
        _clock = clock ?? DateTime.now,
        _periodicTimerFactory = periodicTimerFactory ?? _createPeriodicTimer,
        _refreshCheckInterval = refreshCheckInterval;

  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  static const Duration _refreshAhead = Duration(minutes: 5);

  static Timer _createPeriodicTimer(
    Duration interval,
    void Function() onTick,
  ) =>
      Timer.periodic(interval, (_) => onTick());

  final DouyuSite? _siteOverride;
  final LocalStorageService? _storageOverride;
  final DateTime Function() _clock;
  final DouyuAccountPeriodicTimerFactory _periodicTimerFactory;
  final Duration _refreshCheckInterval;

  String _cookie = '';
  String get cookie => _cookie;
  int get userCookieRevision => _userCookieGeneration;

  final hasCookie = false.obs;
  final cookieRevision = 0.obs;
  final refreshStatus = DouyuAccountRefreshStatus.unconfigured.obs;

  Future<void> _pendingWrite = Future<void>.value();
  Future<DouyuCookieRefreshResult?>? _refreshInFlight;
  Timer? _refreshTimer;
  int? _refreshInFlightGeneration;
  int _userCookieGeneration = 0;
  bool _isForeground = true;
  bool _closed = false;
  bool _lifecycleObserverAdded = false;
  bool _refreshedCookieSaveFailed = false;

  DouyuSite get _site =>
      _siteOverride ?? Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite;

  LocalStorageService get _storage =>
      _storageOverride ?? LocalStorageService.instance;

  @override
  void onInit() {
    _cookie = DouyuCookieHelper.normalizeInput(
      _storage.getValue(LocalStorageService.kDouyuCookie, ''),
    );
    hasCookie.value = _cookie.isNotEmpty;
    refreshStatus.value = _statusForCookie(_cookie);
    setSite();

    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _lifecycleObserverAdded = true;

    super.onInit();
    if (_isForeground) {
      _startForegroundChecks();
      _requestRefreshCheck();
    }
  }

  void setSite() {
    _site.cookie = _cookie;
    _site.onCookieRefreshed = _persistRefreshedCookie;
  }

  Future<bool> setCookie(String input) async {
    final normalized = DouyuCookieHelper.normalizeInput(input);
    if (input.trim().isNotEmpty && normalized.isEmpty) return false;

    // Apply the user's choice immediately so an older refresh cannot take
    // ownership of the newly selected session while its disk write is pending.
    final previous = _cookie;
    final previousRefreshStatus = refreshStatus.value;
    final previousRefreshSaveFailed = _refreshedCookieSaveFailed;
    _userCookieGeneration++;
    _refreshedCookieSaveFailed = false;
    _acceptCookie(normalized);
    _site.cookie = normalized;
    final revision = cookieRevision.value;
    try {
      await _persistCookie(normalized);
    } catch (error, stackTrace) {
      int? rollbackRevision;
      if (!_closed && cookieRevision.value == revision) {
        _userCookieGeneration++;
        _acceptCookie(previous, resetRefreshStatus: false);
        refreshStatus.value = previousRefreshStatus;
        _refreshedCookieSaveFailed = previousRefreshSaveFailed;
        _site.cookie = previous;
        rollbackRevision = userCookieRevision;
      }
      Error.throwWithStackTrace(
        DouyuCookieSaveException(error, rollbackRevision: rollbackRevision),
        stackTrace,
      );
    }

    if (!_closed && _isForeground && normalized.isNotEmpty) {
      _requestRefreshCheck();
    }
    return true;
  }

  Future<void> clearCookie() async {
    await setCookie('');
  }

  /// Runs one proactive check for the current account. Concurrent checks for
  /// the same manual Cookie revision share a single core request.
  Future<DouyuCookieRefreshResult?> checkCookieRefresh() {
    if (_closed || !_isForeground || _cookie.isEmpty) {
      return Future<DouyuCookieRefreshResult?>.value();
    }

    final generation = _userCookieGeneration;
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      if (_refreshInFlightGeneration == generation) return inFlight;
      // A newer user choice arrived while an older request was finishing.
      // Check that choice once the old request releases the shared slot.
      return inFlight.then((_) => checkCookieRefresh());
    }

    final operation = _performRefreshCheck(generation);
    _refreshInFlight = operation;
    _refreshInFlightGeneration = generation;
    operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
        _refreshInFlightGeneration = null;
      }
    });
    return operation;
  }

  Future<DouyuCookieRefreshResult?> _performRefreshCheck(
    int userGeneration,
  ) async {
    final cookieSnapshot = _cookie;
    if (!DouyuCookieHelper.hasRefreshCredentials(cookieSnapshot)) {
      if (_isCurrentUserGeneration(userGeneration)) {
        refreshStatus.value =
            DouyuAccountRefreshStatus.missingRefreshCredentials;
      }
      return DouyuCookieRefreshResult.missingCredentials;
    }

    if (_isCurrentUserGeneration(userGeneration)) {
      refreshStatus.value = DouyuAccountRefreshStatus.waiting;
    }
    try {
      final result = await _site.refreshCookieIfNeeded(
        refreshAhead: _refreshAhead,
        proactive: true,
      );
      if (!_isCurrentUserGeneration(userGeneration)) return result;

      switch (result) {
        case DouyuCookieRefreshResult.unchanged:
        case DouyuCookieRefreshResult.deferred:
          refreshStatus.value = DouyuAccountRefreshStatus.waiting;
          break;
        case DouyuCookieRefreshResult.refreshed:
          refreshStatus.value = DouyuAccountRefreshStatus.refreshed;
          break;
        case DouyuCookieRefreshResult.missingCredentials:
          refreshStatus.value =
              DouyuAccountRefreshStatus.missingRefreshCredentials;
          break;
        case DouyuCookieRefreshResult.failed:
          if (!_refreshedCookieSaveFailed) {
            refreshStatus.value = DouyuAccountRefreshStatus.failure;
          }
          break;
      }
      return result;
    } on CoreCancelledError {
      // Cookie replacement or clear invalidates this request by design.
      return null;
    } catch (_) {
      if (_isCurrentUserGeneration(userGeneration)) {
        refreshStatus.value = DouyuAccountRefreshStatus.failure;
      }
      return DouyuCookieRefreshResult.failed;
    }
  }

  bool _isCurrentUserGeneration(int generation) =>
      !_closed && generation == _userCookieGeneration;

  void _requestRefreshCheck() {
    unawaited(checkCookieRefresh());
  }

  void _startForegroundChecks() {
    if (_closed || !_isForeground || _refreshTimer?.isActive == true) return;
    _refreshTimer = _periodicTimerFactory(
      _refreshCheckInterval,
      _requestRefreshCheck,
    );
  }

  void _stopForegroundChecks() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      _startForegroundChecks();
      _requestRefreshCheck();
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
      _stopForegroundChecks();
    }
  }

  String get summary {
    cookieRevision.value;
    final status = refreshStatus.value;
    if (_cookie.isEmpty || status == DouyuAccountRefreshStatus.unconfigured) {
      return '未配置 Cookie（可选）';
    }
    if (_refreshedCookieSaveFailed) {
      return '已续期，保存失败';
    }

    switch (status) {
      case DouyuAccountRefreshStatus.unconfigured:
        return '未配置 Cookie（可选）';
      case DouyuAccountRefreshStatus.missingRefreshCredentials:
        return '已配置 Cookie，缺少自动续期凭据';
      case DouyuAccountRefreshStatus.failure:
        return 'Cookie 自动续期失败，登录状态待确认';
      case DouyuAccountRefreshStatus.refreshed:
        return 'Cookie 已续期，服务端状态待确认';
      case DouyuAccountRefreshStatus.waiting:
        final expiry = DouyuCookieHelper.jwtExpiresAt(_cookie);
        if (expiry != null && !expiry.isAfter(_clock().toUtc())) {
          return 'Cookie 本地登录凭据已到期，等待自动续期';
        }
        if (DouyuCookieHelper.hasAuthenticatedSession(
          _cookie,
          now: _clock(),
        )) {
          return '已配置 Cookie，可自动续期（服务端状态待确认）';
        }
        return '已配置 Cookie，登录状态待确认';
    }
  }

  DouyuAccountRefreshStatus _statusForCookie(String value) {
    if (value.isEmpty) return DouyuAccountRefreshStatus.unconfigured;
    if (!DouyuCookieHelper.hasRefreshCredentials(value)) {
      return DouyuAccountRefreshStatus.missingRefreshCredentials;
    }
    return DouyuAccountRefreshStatus.waiting;
  }

  void _acceptCookie(String value, {bool resetRefreshStatus = true}) {
    _cookie = value;
    hasCookie.value = value.isNotEmpty;
    cookieRevision.value++;
    if (resetRefreshStatus) {
      refreshStatus.value = _statusForCookie(value);
    }
  }

  Future<void> _persistRefreshedCookie(String value) async {
    if (_closed || _site.cookie != value) return;

    final userGeneration = _userCookieGeneration;
    _acceptCookie(value, resetRefreshStatus: false);
    _refreshedCookieSaveFailed = false;
    try {
      // Core has already accepted the refreshed Cookie. Reassigning it here
      // would invalidate that session and cancel its own request.
      await _persistCookie(value);
      if (_isCurrentUserGeneration(userGeneration) && _cookie == value) {
        refreshStatus.value = DouyuAccountRefreshStatus.refreshed;
      }
    } catch (_) {
      // Keep the accepted in-memory Cookie so playback can continue. The UI
      // reports the disk failure without exposing credentials or throwing it
      // back into the playback refresh path.
      if (_isCurrentUserGeneration(userGeneration) && _cookie == value) {
        _refreshedCookieSaveFailed = true;
        refreshStatus.value = DouyuAccountRefreshStatus.refreshed;
      }
    }
  }

  Future<void> _persistCookie(String value) {
    final write = _pendingWrite.then((_) async {
      await _storage.setValue(
        LocalStorageService.kDouyuCookie,
        value,
      );
    });
    // Preserve write ordering while allowing later user changes after a
    // failed write. The caller still observes this write's failure.
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  @override
  void onClose() {
    _closed = true;
    _isForeground = false;
    _stopForegroundChecks();
    if (_lifecycleObserverAdded) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverAdded = false;
    }
    if (_site.onCookieRefreshed == _persistRefreshedCookie) {
      _site.onCookieRefreshed = null;
    }
    super.onClose();
  }
}
