import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';
import 'package:simple_live_tv_app/services/xiaohongshu_account_service.dart';

class _Storage extends LocalStorageService {
  final values = <dynamic, dynamic>{};
  bool fail = false;
  Completer<void>? gate;
  @override
  T getValue<T>(dynamic key, T defaultValue) =>
      values[key] as T? ?? defaultValue;
  @override
  Future<void> setValue<T>(dynamic key, T value) async {
    final wait = gate;
    gate = null;
    await wait?.future;
    if (fail) throw StateError('disk failed');
    values[key] = value;
  }
}

void main() {
  late _Storage storage;
  late XiaohongshuSite site;
  late XiaohongshuAccountService account;
  setUp(() {
    storage = _Storage();
    site = XiaohongshuSite();
    account = XiaohongshuAccountService(storage: storage, site: site);
    account.onInit();
  });
  test('normalizes complete headers, persists and reloads optional Cookie',
      () async {
    expect(
        await account
            .setCookie('Host: www.xiaohongshu.com\nCookie: a=1; b=x=y'),
        isTrue);
    expect(account.cookie, 'a=1; b=x=y');
    expect(site.cookie, account.cookie);
    final restored = XiaohongshuAccountService(storage: storage, site: site)
      ..onInit();
    expect(restored.cookie, account.cookie);
    expect(restored.hasCookie.value, isTrue);
  });
  test('invalid replacement is rejected and clear persists anonymous state',
      () async {
    await account.setCookie('a=1');
    expect(await account.setCookie('invalid'), isFalse);
    expect(site.cookie, 'a=1');
    await account.clearCookie();
    expect(site.cookie, isEmpty);
    expect(account.hasCookie.value, isFalse);
    expect(storage.values[LocalStorageService.kXiaohongshuCookie], isEmpty);
  });
  test('failed save keeps the accepted account and later writes recover',
      () async {
    await account.setCookie('a=1');
    storage.fail = true;
    await expectLater(account.setCookie('a=2'), throwsStateError);
    expect(site.cookie, 'a=1');
    expect(account.cookie, 'a=1');
    storage.fail = false;
    await account.clearCookie();
    expect(site.cookie, isEmpty);
  });
  test('overlapping saves preserve user order on disk and in memory', () async {
    final gate = Completer<void>();
    storage.gate = gate;
    final first = account.setCookie('a=first');
    final second = account.setCookie('a=second');
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([first, second]);
    expect(account.cookie, 'a=second');
    expect(site.cookie, 'a=second');
    expect(storage.values[LocalStorageService.kXiaohongshuCookie], 'a=second');
    expect(account.cookieRevision.value, 2);
  });
}
