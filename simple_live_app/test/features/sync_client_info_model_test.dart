import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/sync_client_info_model.dart';

void main() {
  Map<String, dynamic> baseJson({
    List<dynamic>? supportedAccountTypes,
  }) =>
      {
        'name': 'TV',
        'version': '1.8.0',
        'address': '192.168.1.20',
        'port': 23234,
        'type': 'tv',
        if (supportedAccountTypes != null)
          'supportedAccountTypes': supportedAccountTypes,
      };

  test('parses and normalizes supported account capabilities', () {
    final info = SyncClientInfoModel.fromJson(
      baseJson(supportedAccountTypes: [
        'BILIBILI',
        'douyu',
        'douyu',
        1,
        '',
      ]),
    );

    expect(info.supportedAccountTypes, ['bilibili', 'douyu']);
    expect(info.supportsAccountType('DOUYU'), isTrue);
    expect(info.supportsAccountType('xiaohongshu'), isFalse);
    expect(info.toJson()['supportedAccountTypes'], ['bilibili', 'douyu']);
  });

  test('keeps peers without capability data compatible and conservative', () {
    final info = SyncClientInfoModel.fromJson(baseJson());

    expect(info.supportedAccountTypes, isEmpty);
    expect(info.supportsAccountType('douyu'), isFalse);
    expect(info.supportsAccountType('xiaohongshu'), isFalse);
  });
}
