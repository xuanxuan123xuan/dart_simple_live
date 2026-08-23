import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';

void main() {
  group('MpvOptionsService.filterForPlatform', () {
    test('drops the Android ao that silences playback on Windows', () {
      // Reported case: ao/vo/hwdec copied from an Android config. libmpv on
      // Windows has no 'audiotrack', fails audio init, and plays with no sound.
      final result = MpvOptionsService.filterForPlatform(
        {
          'ao': 'audiotrack',
          'vo': 'mediacodec_embed',
          'hwdec': 'mediacodec',
          'cache-secs': '0.5',
        },
        'windows',
      );

      expect(result.options.containsKey('ao'), isFalse);
      expect(result.options.containsKey('vo'), isFalse);
      expect(result.options.containsKey('hwdec'), isFalse);
      expect(result.ignored, {
        'ao': 'audiotrack',
        'vo': 'mediacodec_embed',
        'hwdec': 'mediacodec',
      });
      // Unrelated keys must survive untouched.
      expect(result.options['cache-secs'], '0.5');
    });

    test('keeps the same values on the platform that provides them', () {
      final result = MpvOptionsService.filterForPlatform(
        {'ao': 'audiotrack', 'hwdec': 'mediacodec'},
        'android',
      );

      expect(result.ignored, isEmpty);
      expect(result.options['ao'], 'audiotrack');
      expect(result.options['hwdec'], 'mediacodec');
    });

    test('keeps unlisted values instead of guessing (fail-open)', () {
      final result = MpvOptionsService.filterForPlatform(
        {'ao': 'openal', 'vo': 'gpu-next', 'hwdec': 'auto-safe'},
        'windows',
      );

      expect(result.ignored, isEmpty);
      expect(result.options['ao'], 'openal');
      expect(result.options['vo'], 'gpu-next');
      expect(result.options['hwdec'], 'auto-safe');
    });

    test('keeps debugging and disabling values on every platform', () {
      for (final platform in ['windows', 'macos', 'linux', 'android']) {
        final result = MpvOptionsService.filterForPlatform(
          {'ao': 'null', 'vo': 'null', 'hwdec': 'no'},
          platform,
        );
        expect(result.ignored, isEmpty, reason: 'on $platform');
      }
    });

    test('matches values case-insensitively and ignores padding', () {
      final result = MpvOptionsService.filterForPlatform(
        {'ao': '  AudioTrack '},
        'windows',
      );

      expect(result.ignored['ao'], '  AudioTrack ');
      expect(result.options.containsKey('ao'), isFalse);
    });

    test('drops desktop values that do not exist on the other desktops', () {
      expect(
        MpvOptionsService.filterForPlatform({'ao': 'wasapi'}, 'linux').ignored,
        {'ao': 'wasapi'},
      );
      expect(
        MpvOptionsService.filterForPlatform({'ao': 'pulse'}, 'windows').ignored,
        {'ao': 'pulse'},
      );
      expect(
        MpvOptionsService.filterForPlatform({'ao': 'coreaudio'}, 'windows')
            .ignored,
        {'ao': 'coreaudio'},
      );
    });

    test('keeps values shared by more than one platform', () {
      // videotoolbox exists on both Apple platforms.
      expect(
        MpvOptionsService.filterForPlatform(
          {'hwdec': 'videotoolbox'},
          'ios',
        ).ignored,
        isEmpty,
      );
      expect(
        MpvOptionsService.filterForPlatform(
          {'hwdec': 'videotoolbox'},
          'macos',
        ).ignored,
        isEmpty,
      );
      expect(
        MpvOptionsService.filterForPlatform(
          {'hwdec': 'videotoolbox'},
          'windows',
        ).ignored,
        {'hwdec': 'videotoolbox'},
      );
    });

    test('leaves absent keys absent instead of inventing them', () {
      final result = MpvOptionsService.filterForPlatform(
        {'cache': 'yes'},
        'windows',
      );

      expect(result.options, {'cache': 'yes'});
      expect(result.ignored, isEmpty);
    });

    test('only filters platform-scoped keys', () {
      // A non-ao/vo/hwdec key holding a platform-exclusive-looking value must
      // not be touched.
      final result = MpvOptionsService.filterForPlatform(
        {'audio-device': 'wasapi/some-device-id'},
        'linux',
      );

      expect(result.ignored, isEmpty);
      expect(result.options['audio-device'], 'wasapi/some-device-id');
    });
  });

  group('MpvOptionsService.isValueSupportedOn', () {
    test('reports platform exclusivity for the values users hit', () {
      expect(MpvOptionsService.isValueSupportedOn('audiotrack', 'android'),
          isTrue);
      expect(MpvOptionsService.isValueSupportedOn('audiotrack', 'windows'),
          isFalse);
      expect(MpvOptionsService.isValueSupportedOn('wasapi', 'windows'), isTrue);
      expect(MpvOptionsService.isValueSupportedOn('auto', 'windows'), isTrue);
    });
  });
}
