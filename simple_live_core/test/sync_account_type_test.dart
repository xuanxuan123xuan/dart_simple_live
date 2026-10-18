import 'package:test/test.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  group('SyncAccountType', () {
    test('defaults only a missing type to Bilibili and rejects unknown types',
        () {
      expect(SyncAccountType.resolve(null), SyncAccountType.bilibili);
      expect(SyncAccountType.resolve('  '), SyncAccountType.bilibili);
      expect(SyncAccountType.resolve('DOUYU'), SyncAccountType.douyu);
      expect(
          SyncAccountType.resolve('xiaohongshu'), SyncAccountType.xiaohongshu);
      expect(SyncAccountType.resolve('retired-provider'), isNull);
    });

    test('new credential envelopes keep Cookie nested and type-bound', () {
      final envelope = SyncAccountType.credentialsEnvelope(
        accountType: SyncAccountType.douyu,
        cookie: 'auth=value',
      );

      expect(envelope.keys, containsAll(['accountType', 'credentials']));
      expect(envelope.containsKey('cookie'), isFalse);
      expect(
        SyncAccountType.readCredentialCookie(
          envelope,
          accountType: SyncAccountType.douyu,
        ),
        'auth=value',
      );
      expect(
        SyncAccountType.readCredentialCookie(
          envelope,
          accountType: SyncAccountType.xiaohongshu,
        ),
        isNull,
      );
      expect(
        SyncAccountType.readCredentialCookie(
          {'accountType': 'douyu', 'cookie': 'auth=value'},
          accountType: SyncAccountType.douyu,
        ),
        isNull,
      );
    });
  });
}
