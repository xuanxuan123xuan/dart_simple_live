import 'package:simple_live_core/src/common/http_log_sanitizer.dart';
import 'package:test/test.dart';

void main() {
  group('isSensitiveKey', () {
    test('识别常见敏感 key', () {
      for (final key in [
        'cookie',
        'Cookie',
        'authorization',
        'Authorization',
        'password',
        'secret',
        'token',
        'session',
        'csrf',
        'signature',
        'ttwid',
        'a_bogus',
        'a-bogus',
        'sid_guard',
        'sid-guard',
      ]) {
        expect(HttpLogSanitizer.isSensitiveKey(key), isTrue, reason: key);
      }
    });

    test('普通 key 不误伤', () {
      for (final key in ['aid', 'room_id', 'page', 'offset', 'limit']) {
        expect(HttpLogSanitizer.isSensitiveKey(key), isFalse, reason: key);
      }
    });
  });

  group('redact', () {
    test('map 中敏感 key 的值被抹掉', () {
      final result = HttpLogSanitizer.redact({
        'cookie': 'kuaishou.server.web_st=SECRET',
        'User-Agent': 'ok',
        'room_id': '123',
      });
      expect(result['cookie'], '<redacted>');
      expect(result['User-Agent'], 'ok');
      expect(result['room_id'], '123');
    });

    test('嵌套 map 与列表递归脱敏', () {
      final result = HttpLogSanitizer.redact({
        'headers': {'authorization': 'Bearer abc', 'x-ok': '1'},
        'list': ['token=leak', 'plain'],
      });
      expect((result['headers'] as Map)['authorization'], '<redacted>');
      expect((result['headers'] as Map)['x-ok'], '1');
      final list = result['list'] as List;
      expect(list[0], 'token=<redacted>');
      expect(list[1], 'plain');
    });
  });

  group('redactUri', () {
    test('query 中的签名参数被抹掉', () {
      final uri = Uri.parse(
        'https://live.kuaishou.com/api?room_id=123&ttwid=ABC&a_bogus=SIG&page=1',
      );
      final result = HttpLogSanitizer.redactUri(uri);
      // query 值会被 URL 编码，断言脱敏标记出现即可。
      expect(result, contains('ttwid=%3Credacted%3E'));
      expect(result, contains('a_bogus=%3Credacted%3E'));
      expect(result, contains('room_id=123'));
      expect(result, contains('page=1'));
    });
  });

  group('redactText', () {
    test('cookie/authorization 行被抹掉', () {
      final result = HttpLogSanitizer.redactText(
        'Request Headers: cookie: SECRET_COOKIE; authorization: Bearer TOKEN',
      );
      // 正则为贪婪匹配整行（authorization 随 cookie 一起被吞），
      // 只需断言敏感值不再出现且已替换为脱敏标记。
      expect(result, isNot(contains('SECRET_COOKIE')));
      expect(result, isNot(contains('Bearer TOKEN')));
      expect(result, contains('cookie=<redacted>'));
    });

    test('token= 形式的敏感值被抹掉', () {
      final result = HttpLogSanitizer.redactText('token=abc123&page=1');
      expect(result, contains('token=<redacted>'));
      expect(result, contains('page=1'));
    });

    test('完整 URL 被替换为脱敏 URL', () {
      final uri = Uri.parse('https://api.huya.com/live?ttwid=SECRET');
      final result = HttpLogSanitizer.redactText(
        'error at https://api.huya.com/live?ttwid=SECRET',
        requestUri: uri,
      );
      expect(result, isNot(contains('ttwid=SECRET')));
      expect(result, contains('ttwid=<redacted>'));
    });
  });
}
