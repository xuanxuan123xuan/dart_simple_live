import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

String _cookieWithExpiry(DateTime expires, {bool refreshable = true}) {
  final payload = base64Url
      .encode(utf8
          .encode(jsonEncode({'exp': expires.millisecondsSinceEpoch ~/ 1000})))
      .replaceAll('=', '');
  return 'acf_jwt_token=header.$payload.signature${refreshable ? '; dy_did=device; LTP0=refresh' : ''}';
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

void main() {
  late Directory hiveDirectory;
  late Box settingsBox;
  late LocalStorageService storage;
  late DouyuAccountService account;
  DouyuSite site() => Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite;

  setUpAll(() async {
    hiveDirectory =
        await Directory.systemTemp.createTemp('douyu_account_test_');
    Hive.init(hiveDirectory.path);
    CoreLog.requestLogType = RequestLogType.none;
  });

  setUp(() async {
    settingsBox =
        await Hive.openBox('douyu_${DateTime.now().microsecondsSinceEpoch}');
    storage = LocalStorageService()..settingsBox = settingsBox;
    Get.put<LocalStorageService>(storage);
    account = Get.put(DouyuAccountService());
  });

  tearDown(() async {
    Get.reset();
    await settingsBox.deleteFromDisk();
    site().cookie = '';
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('saves normalized Cookie using the existing storage key and site',
      () async {
    expect(await account.setCookie('Cookie: dy_did=device; LTP0=a=b'), isTrue);
    expect(account.cookie, 'dy_did=device; LTP0=a=b');
    expect(site().cookie, account.cookie);
    expect(account.hasCookie.value, isTrue);
    expect(
        storage.getValue(LocalStorageService.kDouyuCookie, ''), account.cookie);
    expect(account.summary, contains('登录状态待确认'));
  });

  test(
      'invalid replacement preserves the account and clear removes all credentials',
      () async {
    await account.setCookie('dy_did=device; LTP0=refresh');
    expect(await account.setCookie('not-cookie-text'), isFalse);
    expect(account.cookie, 'dy_did=device; LTP0=refresh');
    await account.clearCookie();
    expect(account.cookie, isEmpty);
    expect(site().cookie, isEmpty);
    expect(account.hasCookie.value, isFalse);
    expect(
        storage.getValue(LocalStorageService.kDouyuCookie, 'missing'), isEmpty);
  });

  test('expiry presentation distinguishes renewability from saved status',
      () async {
    await account.setCookie(
        _cookieWithExpiry(DateTime.now().add(const Duration(hours: 1))));
    expect(account.summary, '已配置 Cookie，可自动续期');
    await account.setCookie(
        _cookieWithExpiry(DateTime.now().subtract(const Duration(minutes: 1))));
    expect(account.summary, contains('播放时尝试自动续期'));
    await account.setCookie(_cookieWithExpiry(
      DateTime.now().subtract(const Duration(minutes: 1)),
      refreshable: false,
    ));
    expect(account.summary, 'Cookie 已过期，请重新粘贴');
  });

  test('accepted refresh is persisted and stale refresh after clear is ignored',
      () async {
    await account.setCookie('dy_did=device; LTP0=refresh');
    final callback = site().onCookieRefreshed!;
    final renewed =
        _cookieWithExpiry(DateTime.now().add(const Duration(hours: 1)));
    site().cookie = renewed;
    await callback(renewed);
    expect(account.cookie, renewed);
    expect(storage.getValue(LocalStorageService.kDouyuCookie, ''), renewed);
    await account.clearCookie();
    await callback(renewed);
    expect(account.cookie, isEmpty);
    expect(
        storage.getValue(LocalStorageService.kDouyuCookie, 'missing'), isEmpty);
  });

  test('concurrent disk writes preserve the latest manual change', () async {
    Get.reset();
    final delayed = _DelayedStorage()..settingsBox = settingsBox;
    Get.put<LocalStorageService>(delayed);
    account = Get.put(DouyuAccountService());
    final firstSave = account.setCookie('acf_auth=first');
    await Future<void>.delayed(Duration.zero);
    final clear = account.clearCookie();
    expect(site().cookie, isEmpty);
    expect(account.cookie, isEmpty);
    delayed.firstWriteGate.complete();
    await Future.wait([firstSave, clear]);
    expect(delayed.writes, 2);
    expect(
        delayed.getValue(LocalStorageService.kDouyuCookie, 'missing'), isEmpty);
  });
}
