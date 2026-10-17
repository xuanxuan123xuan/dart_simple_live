import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/douyu/web_login_controller.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';

void main() {
  const rootUrl = 'https://douyu.com/';
  const passportUrl = 'https://passport.douyu.com/';
  const wwwUrl = 'https://www.douyu.com/';

  test('reads all three domains and saves merged authenticated cookies',
      () async {
    var revision = 4;
    final readUrls = <String>[];
    final savedCookies = <String>[];
    final controller = DouyuWebLoginController(
      cookieRevisionReader: () => revision,
      browserCookieReader: (url) async {
        readUrls.add(url);
        return switch (url) {
          rootUrl => 'dy_did=root-device; acf_uid=1',
          passportUrl => 'LTP0=passport-refresh; acf_auth=passport-auth',
          wwwUrl =>
            'LTP0=www-refresh; acf_auth=www-auth; acf_uid=55; ttwid=browser-id',
          _ => '',
        };
      },
      cookieWriter: (cookie) async {
        savedCookies.add(cookie);
        revision++;
        return true;
      },
      onSaved: () {},
      showMessage: (_) {},
    )..onInit();

    expect(await controller.saveCookie(), isTrue);

    expect(readUrls, [rootUrl, passportUrl, wwwUrl]);
    expect(savedCookies, hasLength(1));
    expect(savedCookies.single, contains('LTP0=passport-refresh'));
    expect(savedCookies.single, contains('acf_auth=www-auth'));
    expect(savedCookies.single, contains('acf_uid=55'));
    expect(savedCookies.single, contains('dy_did=root-device'));
    expect(savedCookies.single, contains('ttwid=browser-id'));
    controller.onClose();
  });

  test('does not save a browser read that completes after the page closes',
      () async {
    final pendingRead = Completer<String>();
    var revision = 10;
    var saveCount = 0;
    final controller = DouyuWebLoginController(
      cookieRevisionReader: () => revision,
      browserCookieReader: (url) =>
          url == rootUrl ? pendingRead.future : Future.value(''),
      cookieWriter: (_) async {
        saveCount++;
        revision++;
        return true;
      },
      onSaved: () {},
      showMessage: (_) {},
    )..onInit();

    final save = controller.saveCookie();
    controller.onClose();
    pendingRead.complete(
      'acf_auth=late-auth; acf_uid=42; dy_did=device; LTP0=refresh',
    );

    expect(await save, isFalse);
    expect(saveCount, 0);
  });

  test(
      'a changed account invalidates the flow and later reads cannot restore it',
      () async {
    final pendingRead = Completer<String>();
    var revision = 20;
    var saveCount = 0;
    final controller = DouyuWebLoginController(
      cookieRevisionReader: () => revision,
      browserCookieReader: (url) =>
          url == rootUrl ? pendingRead.future : Future.value(''),
      cookieWriter: (_) async {
        saveCount++;
        revision++;
        return true;
      },
      onSaved: () {},
      showMessage: (_) {},
    )..onInit();

    final save = controller.saveCookie();
    revision++;
    pendingRead.complete(
      'acf_auth=old-auth; acf_uid=42; dy_did=device; LTP0=refresh',
    );

    expect(await save, isFalse);
    expect(controller.flowInvalidated, isTrue);
    expect(await controller.saveCookie(), isFalse);
    expect(saveCount, 0);
    controller.onClose();
  });

  test('persistence errors keep the page open and show a generic message',
      () async {
    var revision = 30;
    var saved = false;
    var closed = false;
    final messages = <String>[];
    final controller = DouyuWebLoginController(
      cookieRevisionReader: () => revision,
      browserCookieReader: (_) async =>
          'acf_auth=private-session; acf_uid=9; dy_did=device; LTP0=refresh',
      cookieWriter: (_) async {
        saved = true;
        throw StateError('private-session');
      },
      onSaved: () => closed = true,
      showMessage: messages.add,
    )..onInit();

    expect(await controller.saveCookie(), isFalse);
    expect(saved, isTrue);
    expect(closed, isFalse);
    expect(messages.single, '保存斗鱼登录状态失败，请重试');
    expect(messages.join(), isNot(contains('private-session')));
    controller.onClose();
  });

  test('a rolled-back save can be retried without accepting another account',
      () async {
    var revision = 50;
    var attempts = 0;
    final controller = DouyuWebLoginController(
      cookieRevisionReader: () => revision,
      browserCookieReader: (_) async => 'acf_auth=new; acf_uid=9',
      cookieWriter: (cookie) async {
        attempts++;
        revision++;
        if (attempts == 1) {
          revision++;
          throw DouyuCookieSaveException(
            StateError('disk write failed'),
            rollbackRevision: revision,
          );
        }
        return true;
      },
      onSaved: () {},
      showMessage: (_) {},
    )..onInit();

    expect(await controller.saveCookie(), isFalse);
    expect(await controller.saveCookie(), isTrue);
    expect(attempts, 2);
    controller.onClose();
  });

  test('an external change to the old Cookie cannot impersonate a rollback',
      () async {
    var revision = 60;
    var attempts = 0;
    final controller = DouyuWebLoginController(
      cookieRevisionReader: () => revision,
      browserCookieReader: (_) async => 'acf_auth=new; acf_uid=9',
      cookieWriter: (_) async {
        attempts++;
        revision++; // The attempted login value.
        revision++; // Another user deliberately restores the old value.
        throw DouyuCookieSaveException(StateError('disk write failed'));
      },
      onSaved: () {},
      showMessage: (_) {},
    )..onInit();

    expect(await controller.saveCookie(), isFalse);
    expect(controller.flowInvalidated, isTrue);
    expect(await controller.saveCookie(), isFalse);
    expect(attempts, 1);
    controller.onClose();
  });

  test('saves authenticated sessions without LTP0 with a specific warning',
      () async {
    var revision = 40;
    final savedCookies = <String>[];
    final messages = <String>[];
    var closed = false;
    final controller = DouyuWebLoginController(
      cookieRevisionReader: () => revision,
      browserCookieReader: (_) async => 'acf_auth=auth; acf_uid=17',
      cookieWriter: (cookie) async {
        savedCookies.add(cookie);
        revision++;
        return true;
      },
      onSaved: () => closed = true,
      showMessage: messages.add,
    )..onInit();

    expect(await controller.saveCookie(silent: true), isTrue);

    expect(savedCookies, ['acf_auth=auth; acf_uid=17']);
    expect(messages.single, '斗鱼登录状态已保存，但缺少 LTP0 或设备 ID，过期后需重新登录');
    expect(closed, isTrue);
    controller.onClose();
  });
}
