import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/bilibili/web_login_controller.dart';

void main() {
  group('hasBilibiliAuthenticatedSession', () {
    test('accepts a non-empty SESSDATA credential', () {
      expect(
        hasBilibiliAuthenticatedSession(
          'bili_jct=csrf; SESSDATA=credential; DedeUserID=123',
        ),
        isTrue,
      );
    });

    test('rejects anonymous and empty sessions', () {
      expect(
        hasBilibiliAuthenticatedSession('bili_jct=csrf; DedeUserID=123'),
        isFalse,
      );
      expect(
        hasBilibiliAuthenticatedSession('SESSDATA=; bili_jct=csrf'),
        isFalse,
      );
    });
  });
}
