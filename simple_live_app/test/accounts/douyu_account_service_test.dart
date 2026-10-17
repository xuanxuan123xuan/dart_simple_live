import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/modules/mine/account/douyu/web_login_controller.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

typedef _RefreshOperation = Future<DouyuCookieRefreshResult> Function({
  required Duration refreshAhead,
  required bool proactive,
});

String _cookieWithExpiry(DateTime expires, {bool refreshable = true}) {
  final payload = base64Url
      .encode(utf8
          .encode(jsonEncode({'exp': expires.millisecondsSinceEpoch ~/ 1000})))
      .replaceAll('=', '');
  return 'acf_jwt_token=header.$payload.signature${refreshable ? '; dy_did=device; LTP0=refresh' : ''}';
}

class _CallWaiter {
  _CallWaiter(this.callNumber) : completer = Completer<void>();

  final int callNumber;
  final Completer<void> completer;
}

class _FakeDouyuSite extends DouyuSite {
  _RefreshOperation? refreshOperation;
  int refreshCalls = 0;
  Duration? lastRefreshAhead;
  bool? lastProactive;

  final _callWaiters = <_CallWaiter>[];

  Future<void> waitForCalls(int callNumber) {
    if (refreshCalls >= callNumber) return Future<void>.value();
    final waiter = _CallWaiter(callNumber);
    _callWaiters.add(waiter);
    return waiter.completer.future;
  }

  @override
  Future<DouyuCookieRefreshResult> refreshCookieIfNeeded({
    Duration refreshAhead = Duration.zero,
    bool proactive = false,
  }) {
    refreshCalls++;
    lastRefreshAhead = refreshAhead;
    lastProactive = proactive;
    for (final waiter in List<_CallWaiter>.of(_callWaiters)) {
      if (refreshCalls >= waiter.callNumber) {
        _callWaiters.remove(waiter);
        waiter.completer.complete();
      }
    }
    return refreshOperation?.call(
          refreshAhead: refreshAhead,
          proactive: proactive,
        ) ??
        Future<DouyuCookieRefreshResult>.value(
          DouyuCookieRefreshResult.unchanged,
        );
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.interval, this._onTick);

  final Duration interval;
  final void Function() _onTick;
  bool _isActive = true;
  int _tick = 0;

  void fire() {
    if (!_isActive) return;
    _tick++;
    _onTick();
  }

  @override
  void cancel() => _isActive = false;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;
}

class _DelayedStorage extends LocalStorageService {
  final firstWriteGate = Completer<void>();
  int writes = 0;

  @override
  Future<void> setValue<T>(dynamic key, T value) async {
    writes++;
    if (writes == 1) await firstWriteGate.future;
    await super.setValue(key, value);
  }
}

class _FailingStorage extends LocalStorageService {
  bool failNextWrite = false;
  Completer<void>? failureGate;

  @override
  Future<void> setValue<T>(dynamic key, T value) async {
    if (failNextWrite) {
      failNextWrite = false;
      await failureGate?.future;
      throw StateError('disk write failed');
    }
    await super.setValue(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;
  late Box settingsBox;
  late LocalStorageService storage;
  late _FakeDouyuSite douyuSite;
  late DouyuAccountService account;
  late List<_ManualTimer> timers;

  Future<void> installService({
    LocalStorageService? newStorage,
    String? initialCookie,
  }) async {
    Get.reset();
    storage = newStorage ?? LocalStorageService();
    storage.settingsBox = settingsBox;
    if (initialCookie != null) {
      await storage.setValue(LocalStorageService.kDouyuCookie, initialCookie);
    }
    Get.put<LocalStorageService>(storage);
    douyuSite = _FakeDouyuSite();
    timers = [];
    account = Get.put(
      DouyuAccountService(
        site: douyuSite,
        storage: storage,
        periodicTimerFactory: (interval, onTick) {
          final timer = _ManualTimer(interval, onTick);
          timers.add(timer);
          return timer;
        },
      ),
    );
  }

  setUpAll(() async {
    hiveDirectory =
        await Directory.systemTemp.createTemp('douyu_account_test_');
    Hive.init(hiveDirectory.path);
    CoreLog.requestLogType = RequestLogType.none;
  });

  setUp(() async {
    settingsBox =
        await Hive.openBox('douyu_${DateTime.now().microsecondsSinceEpoch}');
    await installService();
  });

  tearDown(() async {
    Get.reset();
    await settingsBox.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('saves normalized Cookie using the existing storage key and site',
      () async {
    expect(await account.setCookie('Cookie: dy_did=device; LTP0=a=b'), isTrue);
    expect(account.cookie, 'dy_did=device; LTP0=a=b');
    expect(douyuSite.cookie, account.cookie);
    expect(account.hasCookie.value, isTrue);
    expect(
      storage.getValue(LocalStorageService.kDouyuCookie, ''),
      account.cookie,
    );
    expect(account.summary, contains('登录状态待确认'));
  });

  test(
      'invalid replacement preserves the account and clear removes credentials',
      () async {
    await account.setCookie('dy_did=device; LTP0=refresh');
    expect(await account.setCookie('not-cookie-text'), isFalse);
    expect(account.cookie, 'dy_did=device; LTP0=refresh');
    await account.clearCookie();
    expect(account.cookie, isEmpty);
    expect(douyuSite.cookie, isEmpty);
    expect(account.hasCookie.value, isFalse);
    expect(account.refreshStatus.value, DouyuAccountRefreshStatus.unconfigured);
    expect(
      storage.getValue(LocalStorageService.kDouyuCookie, 'missing'),
      isEmpty,
    );
  });

  test('startup checks proactively with a five minute refresh window',
      () async {
    final cookie =
        _cookieWithExpiry(DateTime.now().add(const Duration(minutes: 4)));
    await installService(initialCookie: cookie);

    expect(douyuSite.refreshCalls, 1);
    expect(douyuSite.lastRefreshAhead, const Duration(minutes: 5));
    expect(douyuSite.lastProactive, isTrue);
    expect(timers.single.interval, const Duration(minutes: 1));
    expect(account.refreshStatus.value, DouyuAccountRefreshStatus.waiting);
  });

  test('foreground timer and resume check; inactive states stop the timer',
      () async {
    await installService(
      initialCookie: 'dy_did=device; LTP0=refresh',
    );
    expect(douyuSite.refreshCalls, 1);
    expect(timers.single.isActive, isTrue);
    await Future<void>.delayed(Duration.zero);

    timers.single.fire();
    await douyuSite.waitForCalls(2);
    await Future<void>.delayed(Duration.zero);
    expect(douyuSite.refreshCalls, 2);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      final timer = timers.last;
      account.didChangeAppLifecycleState(state);
      expect(timer.isActive, isFalse);
      final callsWhileStopped = douyuSite.refreshCalls;
      timer.fire();
      await Future<void>.delayed(Duration.zero);
      expect(douyuSite.refreshCalls, callsWhileStopped);

      account.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await douyuSite.waitForCalls(callsWhileStopped + 1);
      await Future<void>.delayed(Duration.zero);
      expect(timers.last.isActive, isTrue);
    }
  });

  test('close cancels periodic checks and detaches the refresh callback',
      () async {
    await installService(
      initialCookie: 'dy_did=device; LTP0=refresh',
    );
    final timer = timers.single;
    await Get.delete<DouyuAccountService>(force: true);

    expect(timer.isActive, isFalse);
    expect(douyuSite.onCookieRefreshed, isNull);
    final callsAtClose = douyuSite.refreshCalls;
    timer.fire();
    expect(douyuSite.refreshCalls, callsAtClose);
  });

  test('manual set triggers one proactive check and concurrent checks coalesce',
      () async {
    final gate = Completer<DouyuCookieRefreshResult>();
    final started = douyuSite.waitForCalls(1);
    douyuSite.refreshOperation = ({
      required refreshAhead,
      required proactive,
    }) =>
        gate.future;

    await account.setCookie('dy_did=device; LTP0=refresh');
    await started;
    final first = account.checkCookieRefresh();
    final second = account.checkCookieRefresh();

    expect(douyuSite.refreshCalls, 1);
    gate.complete(DouyuCookieRefreshResult.unchanged);
    await Future.wait([first, second]);
    expect(douyuSite.refreshCalls, 1);
  });

  test('manual clear prevents an older refresh result changing account status',
      () async {
    final gate = Completer<DouyuCookieRefreshResult>();
    final started = douyuSite.waitForCalls(1);
    douyuSite.refreshOperation = ({
      required refreshAhead,
      required proactive,
    }) =>
        gate.future;

    await account.setCookie('dy_did=device; LTP0=refresh');
    await started;
    await account.clearCookie();
    gate.complete(DouyuCookieRefreshResult.failed);
    await Future<void>.delayed(Duration.zero);

    expect(account.cookie, isEmpty);
    expect(account.refreshStatus.value, DouyuAccountRefreshStatus.unconfigured);
    expect(account.summary, '未配置 Cookie（可选）');
  });

  test('missing refresh credentials and failed refresh are observable',
      () async {
    await account.setCookie('acf_auth=auth; acf_uid=123');
    await Future<void>.delayed(Duration.zero);
    expect(account.refreshStatus.value,
        DouyuAccountRefreshStatus.missingRefreshCredentials);
    expect(account.summary, contains('缺少自动续期凭据'));
    expect(douyuSite.refreshCalls, 0);

    douyuSite.refreshOperation = ({
      required refreshAhead,
      required proactive,
    }) async =>
        DouyuCookieRefreshResult.failed;
    await account.setCookie('dy_did=device; LTP0=refresh');
    await Future<void>.delayed(Duration.zero);
    expect(account.refreshStatus.value, DouyuAccountRefreshStatus.failure);
    expect(account.summary, contains('自动续期失败'));
  });

  test('failed user save restores the previous Cookie and refresh status',
      () async {
    final failingStorage = _FailingStorage();
    await installService(newStorage: failingStorage);
    await account.setCookie('acf_auth=auth; acf_uid=123');
    await Future<void>.delayed(Duration.zero);
    final previousStatus = account.refreshStatus.value;
    final previousRevision = account.userCookieRevision;

    failingStorage.failNextWrite = true;
    await expectLater(
      account.setCookie('dy_did=new-device; LTP0=new-refresh'),
      throwsA(isA<DouyuCookieSaveException>()
          .having((error) => error.cause, 'cause', isA<StateError>())
          .having((error) => error.rollbackRevision, 'owned rollback revision',
              previousRevision + 2)),
    );

    expect(account.cookie, 'acf_auth=auth; acf_uid=123');
    expect(douyuSite.cookie, account.cookie);
    expect(account.refreshStatus.value, previousStatus);
    expect(
      failingStorage.getValue(LocalStorageService.kDouyuCookie, ''),
      account.cookie,
    );
  });

  test('failed save cannot claim a concurrent user restore as its rollback',
      () async {
    final failingStorage = _FailingStorage();
    await installService(newStorage: failingStorage);
    const oldCookie = 'acf_auth=old; acf_uid=123';
    await account.setCookie(oldCookie);
    final previousRevision = account.userCookieRevision;
    failingStorage.failNextWrite = true;
    final gate = failingStorage.failureGate = Completer<void>();
    final failedSave = account.setCookie('acf_auth=new; acf_uid=456');
    final failure = expectLater(
      failedSave,
      throwsA(isA<DouyuCookieSaveException>().having(
        (error) => error.rollbackRevision,
        'owned rollback revision',
        isNull,
      )),
    );
    await Future<void>.delayed(Duration.zero);
    final restore = account.setCookie(oldCookie);
    gate.complete();
    await failure;
    expect(await restore, isTrue);

    expect(account.cookie, oldCookie);
    expect(account.userCookieRevision, previousRevision + 2);
  });

  test('web login succeeds when proactive refresh rotates its saved Cookie',
      () async {
    final renewed =
        _cookieWithExpiry(DateTime.now().add(const Duration(hours: 1)));
    douyuSite.refreshOperation = ({
      required refreshAhead,
      required proactive,
    }) async {
      douyuSite.cookie = renewed;
      await douyuSite.onCookieRefreshed!(renewed);
      return DouyuCookieRefreshResult.refreshed;
    };
    var saved = false;
    final controller = DouyuWebLoginController(
      browserCookieReader: (_) async =>
          'acf_auth=login; acf_uid=9; dy_did=device; LTP0=refresh',
      onSaved: () => saved = true,
      showMessage: (_) {},
    )..onInit();

    expect(await controller.saveCookie(), isTrue);
    expect(saved, isTrue);
    expect(controller.flowInvalidated, isFalse);
    expect(account.userCookieRevision, 1);
    expect(account.cookieRevision.value, 2);
    expect(account.cookie, renewed);
    controller.onClose();
  });

  test('refresh callback persists in order and ignores a stale callback',
      () async {
    await account.setCookie('dy_did=device; LTP0=refresh');
    final userRevision = account.userCookieRevision;
    final callback = douyuSite.onCookieRefreshed!;
    final renewed =
        _cookieWithExpiry(DateTime.now().add(const Duration(hours: 1)));
    douyuSite.cookie = renewed;
    await callback(renewed);
    expect(account.cookie, renewed);
    expect(
      storage.getValue(LocalStorageService.kDouyuCookie, ''),
      renewed,
    );
    expect(account.refreshStatus.value, DouyuAccountRefreshStatus.refreshed);
    expect(account.userCookieRevision, userRevision);
    await account.clearCookie();
    expect(account.userCookieRevision, greaterThan(userRevision));
    await callback(renewed);
    expect(account.cookie, isEmpty);
    expect(
      storage.getValue(LocalStorageService.kDouyuCookie, 'missing'),
      isEmpty,
    );
  });

  test('refresh stays in memory and reports a save failure without throwing',
      () async {
    final failingStorage = _FailingStorage();
    await installService(newStorage: failingStorage);
    const initial = 'dy_did=device; LTP0=refresh';
    await account.setCookie(initial);
    await Future<void>.delayed(Duration.zero);

    final renewed =
        _cookieWithExpiry(DateTime.now().add(const Duration(hours: 1)));
    douyuSite.refreshOperation = ({
      required refreshAhead,
      required proactive,
    }) async {
      douyuSite.cookie = renewed;
      await douyuSite.onCookieRefreshed!(renewed);
      return DouyuCookieRefreshResult.refreshed;
    };
    failingStorage.failNextWrite = true;

    expect(
        await account.checkCookieRefresh(), DouyuCookieRefreshResult.refreshed);
    expect(account.cookie, renewed);
    expect(account.summary, '已续期，保存失败');
    expect(
      failingStorage.getValue(LocalStorageService.kDouyuCookie, ''),
      initial,
    );
  });

  test('save failure summary survives later unchanged checks', () async {
    final failingStorage = _FailingStorage();
    await installService(newStorage: failingStorage);
    await account.setCookie('dy_did=device; LTP0=refresh');
    await Future<void>.delayed(Duration.zero);

    final renewed =
        _cookieWithExpiry(DateTime.now().add(const Duration(hours: 1)));
    douyuSite.cookie = renewed;
    failingStorage.failNextWrite = true;
    await douyuSite.onCookieRefreshed!(renewed);
    expect(account.summary, '已续期，保存失败');

    await account.checkCookieRefresh();
    expect(account.summary, '已续期，保存失败');
  });

  test('concurrent disk writes preserve the latest manual change', () async {
    final delayed = _DelayedStorage();
    await installService(newStorage: delayed);
    final firstSave = account.setCookie('acf_auth=first');
    await Future<void>.delayed(Duration.zero);
    final clear = account.clearCookie();
    expect(douyuSite.cookie, isEmpty);
    expect(account.cookie, isEmpty);
    delayed.firstWriteGate.complete();
    await Future.wait([firstSave, clear]);
    expect(delayed.writes, 2);
    expect(
      delayed.getValue(LocalStorageService.kDouyuCookie, 'missing'),
      isEmpty,
    );
  });

  test('refreshed Cookie write is ordered before a later user clear', () async {
    final delayed = _DelayedStorage();
    await installService(newStorage: delayed);
    final firstSave = account.setCookie('acf_auth=first');
    await Future<void>.delayed(Duration.zero);

    final renewed =
        _cookieWithExpiry(DateTime.now().add(const Duration(hours: 1)));
    douyuSite.cookie = renewed;
    final refreshSave = douyuSite.onCookieRefreshed!(renewed);
    final clear = account.clearCookie();
    delayed.firstWriteGate.complete();
    await Future.wait([firstSave, refreshSave, clear]);

    expect(delayed.writes, 3);
    expect(account.cookie, isEmpty);
    expect(
      delayed.getValue(LocalStorageService.kDouyuCookie, 'missing'),
      isEmpty,
    );
  });
}
