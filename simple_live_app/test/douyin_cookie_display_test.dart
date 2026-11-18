import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/mine/account/douyin_cookie_display.dart';

void main() {
  group('DouyinCookieDisplay', () {
    test('distinguishes the four configuration states in summaries', () {
      expect(
        DouyinCookieDisplay.summary(''),
        contains('未配置自定义 Cookie'),
      );
      expect(
        DouyinCookieDisplay.summary('ttwid=anonymous'),
        contains('仅配置 ttwid'),
      );
      expect(
        DouyinCookieDisplay.summary('ttwid=anonymous; theme=dark'),
        contains('缺少登录字段'),
      );
      expect(
        DouyinCookieDisplay.summary('ttwid=device; sessionid=logged-in'),
        contains('已配置完整登录 Cookie'),
      );
    });

    test('save feedback does not claim incomplete cookies are login cookies',
        () {
      expect(
        DouyinCookieDisplay.savedMessage('ttwid=anonymous'),
        contains('搜索仍需完整登录 Cookie'),
      );
      expect(
        DouyinCookieDisplay.savedMessage('ttwid=anonymous; theme=dark'),
        contains('未检测到登录字段'),
      );
      expect(
        DouyinCookieDisplay.savedMessage(
          'ttwid=device; sessionid=logged-in',
        ),
        '完整抖音登录 Cookie 已保存',
      );
    });

    test('reports a parseable expired login cookie', () {
      final summary = DouyinCookieDisplay.summary(
        'ttwid=device; sid_guard=token%7C1600000000%7C86400',
        now: DateTime.utc(2026),
      );

      expect(summary, contains('可解析有效期已过'));
    });
  });
}
