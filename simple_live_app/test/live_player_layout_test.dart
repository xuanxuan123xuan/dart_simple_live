import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/live_player_layout.dart';

void main() {
  group('LivePlayerLayoutMode', () {
    test('uses stable numeric and textual storage values', () {
      expect(
        LivePlayerLayoutMode.values.map((mode) => mode.index),
        [0, 1, 2],
      );
      expect(
        LivePlayerLayoutMode.values.map((mode) => mode.storageValue),
        ['auto', 'portrait-dual-screen', 'landscape-dual-screen'],
      );
      expect(LivePlayerLayoutMode.fromStorage(null),
          LivePlayerLayoutMode.automatic);
      expect(LivePlayerLayoutMode.fromStorage(1),
          LivePlayerLayoutMode.portraitDualScreen);
      expect(LivePlayerLayoutMode.fromStorage('landscapeDualScreen'),
          LivePlayerLayoutMode.landscapeDualScreen);
      expect(LivePlayerLayoutMode.fromStorage('unknown'),
          LivePlayerLayoutMode.automatic);
    });

    test('exposes portrait and landscape forced ratios', () {
      expect(LivePlayerLayoutMode.automatic.forcedAspectRatio, isNull);
      expect(
        LivePlayerLayoutMode.portraitDualScreen.forcedAspectRatio,
        closeTo(9 / 16, 0.0001),
      );
      expect(
        LivePlayerLayoutMode.landscapeDualScreen.forcedAspectRatio,
        closeTo(16 / 9, 0.0001),
      );
    });
  });

  group('live player aspect ratio helpers', () {
    test('parses valid dimensions and rejects invalid dimensions', () {
      expect(parseLivePlayerAspectRatio(1080, 1920), closeTo(9 / 16, 0.0001));
      expect(parseLivePlayerAspectRatio('1920', '1080'), closeTo(16 / 9, 0.0001));
      expect(parseLivePlayerAspectRatio(0, 1080), isNull);
      expect(parseLivePlayerAspectRatio('bad', 1080), isNull);
    });

    test('parses resolution strings and metadata maps', () {
      expect(
        parseLivePlayerResolutionAspectRatio('1080x1920'),
        closeTo(9 / 16, 0.0001),
      );
      expect(
        parseLivePlayerResolutionAspectRatio({'width': 1920, 'height': 1080}),
        closeTo(16 / 9, 0.0001),
      );
      expect(
        parseLivePlayerResolutionAspectRatio({'resolution': '720*1280'}),
        closeTo(9 / 16, 0.0001),
      );
    });

    test('prefers decoded dimensions and falls back to metadata', () {
      expect(
        resolveDualScreenAspectRatio(
          mode: LivePlayerLayoutMode.automatic,
          videoWidth: 1080,
          videoHeight: 1920,
          streamOrientation: 'landscape',
        ),
        closeTo(9 / 16, 0.0001),
      );
      expect(
        resolveDualScreenAspectRatio(
          mode: LivePlayerLayoutMode.automatic,
          sdkParamsResolution: '1920x1080',
        ),
        closeTo(16 / 9, 0.0001),
      );
      expect(
        resolveDualScreenAspectRatio(
          mode: LivePlayerLayoutMode.automatic,
          streamOrientation: 'portrait',
        ),
        closeTo(9 / 16, 0.0001),
      );
    });

    test('manual mode always wins over stream dimensions', () {
      expect(
        resolveDualScreenAspectRatio(
          mode: LivePlayerLayoutMode.landscapeDualScreen,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        closeTo(16 / 9, 0.0001),
      );
    });

    test('infers dual-screen direction when dimensions are available', () {
      expect(
        inferDualScreenLayoutMode(videoWidth: 1080, videoHeight: 1920),
        LivePlayerLayoutMode.portraitDualScreen,
      );
      expect(
        inferDualScreenLayoutMode(streamOrientation: 'horizontal'),
        LivePlayerLayoutMode.landscapeDualScreen,
      );
      expect(inferDualScreenLayoutMode(), isNull);
    });
  });
}
