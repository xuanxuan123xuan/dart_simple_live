import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/models/app_update_model.dart';
import 'package:simple_live_app/services/app_update_service.dart';

void main() {
  group('AppUpdateService release parsing', () {
    test('detects stable and dev tags', () {
      expect(
        AppUpdateService.channelFromTag('v1.13.20'),
        AppUpdateChannel.stable,
      );
      expect(
        AppUpdateService.channelFromTag('v1.13.20-dev'),
        AppUpdateChannel.dev,
      );
      expect(AppUpdateService.channelFromTag('v1.13.20-pre'), isNull);
    });

    test('extracts version and build number from release tags', () {
      expect(AppUpdateService.versionFromTag('v1.13.20-dev'), '1.13.20');
      expect(AppUpdateService.versionFromTag('v1.13.20'), '1.13.20');
      expect(AppUpdateService.buildNumberFromVersion('1.13.20'), 11320);
      expect(AppUpdateService.buildNumberFromVersion('bad.version'), 0);
    });

    test('parses SHA-256 lines from release body', () {
      const hash =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      final values = AppUpdateService.parseSha256(
        '### SHA-256\n```\n$hash  simple-live-1.13.20-windows.exe\n```',
      );

      expect(values['simple-live-1.13.20-windows.exe'], hash);
    });

    test('parses platform, package kind and ABI from asset names', () {
      final android = _asset('simple-live-1.13.20-android-arm64-v8a.apk');
      final windows = _asset('simple-live-1.13.20-windows.exe');
      final linux = _asset('simple-live-1.13.20-linux.AppImage');
      final macos = _asset('simple-live-1.13.20-macos.dmg');
      final ohos = _asset('simple-live-1.13.20-ohos-arm64-signed.hap');

      expect(android?.platform, AppUpdatePlatform.android);
      expect(android?.kind, AppUpdatePackageKind.apk);
      expect(android?.abi, 'arm64-v8a');
      expect(windows?.platform, AppUpdatePlatform.windows);
      expect(windows?.kind, AppUpdatePackageKind.exe);
      expect(linux?.kind, AppUpdatePackageKind.appImage);
      expect(macos?.platform, AppUpdatePlatform.macos);
      expect(ohos?.platform, AppUpdatePlatform.ohos);
      expect(ohos?.kind, AppUpdatePackageKind.hap);
      expect(ohos?.abi, 'arm64');
    });

    test('keeps desktop assets and filters Android TV assets from releases',
        () {
      final release = AppUpdateService.parseRelease({
        'tag_name': 'v1.13.20',
        'published_at': '2026-08-19T00:00:00Z',
        'html_url': 'https://github.com/example/releases/tag/v1.13.20',
        'body': '',
        'assets': [
          _assetJson('simple-live-1.13.20-windows.exe'),
          _assetJson('simple-live-1.13.20-windows.zip'),
          _assetJson('simple-live-tv-1.13.20-android-universal.apk'),
        ],
      });

      expect(release, isNotNull);
      expect(release!.channel, AppUpdateChannel.stable);
      expect(
        release.assets.map((asset) => asset.name),
        containsAll([
          'simple-live-1.13.20-windows.exe',
          'simple-live-1.13.20-windows.zip',
        ]),
      );
      expect(
        release.assets.any((asset) => asset.platform == AppUpdatePlatform.tv),
        isFalse,
      );
    });
  });
}

AppUpdateAsset? _asset(String name) {
  return AppUpdateService.parseAsset(_assetJson(name));
}

Map<String, dynamic> _assetJson(String name) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
      'size': 1024,
    };
