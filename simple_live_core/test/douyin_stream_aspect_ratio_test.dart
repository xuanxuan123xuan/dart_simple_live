import 'dart:convert';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('DouyinSite.resolveStreamAspectRatio', () {
    test('reads portrait dimensions from stream_url extra', () {
      final ratio = DouyinSite.resolveStreamAspectRatio({
        'extra': {'width': 1080, 'height': 1920},
      });

      expect(ratio, closeTo(9 / 16, 0.000001));
    });

    test('accepts JSON encoded stream_url extra', () {
      final ratio = DouyinSite.resolveStreamAspectRatio({
        'extra': jsonEncode({'width': '1920', 'height': '1080'}),
      });

      expect(ratio, closeTo(16 / 9, 0.000001));
    });

    test('reads resolution from nested sdk_params stream data', () {
      final ratio = DouyinSite.resolveStreamAspectRatio({
        'live_core_sdk_data': {
          'pull_data': {
            'stream_data': jsonEncode({
              'data': {},
              'common': {
                'sdk_params': {'resolution': '1920x1080'},
              },
            }),
          },
        },
      });

      expect(ratio, closeTo(16 / 9, 0.000001));
    });

    test('accepts JSON encoded sdk_params and compact separators', () {
      final ratio = DouyinSite.resolveStreamAspectRatio({
        'live_core_sdk_data': {
          'pull_data': {
            'stream_data': jsonEncode({
              'sdk_params': jsonEncode({'resolution': '1080×1920'}),
            }),
          },
        },
      });

      expect(ratio, closeTo(9 / 16, 0.000001));
    });

    test('falls back to sdk_params when extra is malformed', () {
      final ratio = DouyinSite.resolveStreamAspectRatio({
        'extra': {'width': 0, 'height': 'unknown'},
        'live_core_sdk_data': {
          'pull_data': {
            'stream_data': jsonEncode({
              'sdk_params': {'resolution': '720:1280'},
            }),
          },
        },
      });

      expect(ratio, closeTo(9 / 16, 0.000001));
    });

    test('uses textual stream orientation as a last resort', () {
      expect(
        DouyinSite.resolveStreamAspectRatio({'stream_orientation': 'portrait'}),
        closeTo(9 / 16, 0.000001),
      );
    });

    test('returns null for missing or malformed metadata', () {
      expect(DouyinSite.resolveStreamAspectRatio(null), isNull);
      expect(
        DouyinSite.resolveStreamAspectRatio({
          'extra': {'width': 'bad', 'height': 1920},
          'live_core_sdk_data': {
            'pull_data': {'stream_data': '{not-json}'},
          },
        }),
        isNull,
      );
    });
  });
}
