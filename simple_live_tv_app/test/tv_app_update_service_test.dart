import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/models/version_model.dart';
import 'package:simple_live_tv_app/services/tv_app_update_service.dart';

void main() {
  setUp(() {
    Utils.packageInfo = PackageInfo(
      appName: 'Simple Live TV',
      packageName: 'com.simplelive.tv',
      version: '1.7.8',
      buildNumber: '10708',
    );
  });

  test('parses optional and numeric version metadata safely', () {
    final version = VersionModel.fromJson({
      'version': '1.7.9',
      'version_num': '10709',
      'version_desc': '- 修复问题',
      'download_url': 'https://github.com/example/repo/releases/tag/tv_v1.7.9',
      'prerelease': true,
    });

    expect(version.version, '1.7.9');
    expect(version.versionNum, 10709);
    expect(version.prerelease, isTrue);
  });

  test('compares remote build number with the installed TV build', () {
    final service = TvAppUpdateService();
    expect(
      service.isNewer(
        VersionModel(
          version: '1.7.9',
          versionNum: 10709,
          versionDesc: '',
          downloadUrl: '',
        ),
      ),
      isTrue,
    );
    expect(
      service.isNewer(
        VersionModel(
          version: '1.7.8',
          versionNum: 10708,
          versionDesc: '',
          downloadUrl: '',
        ),
      ),
      isFalse,
    );
  });

  group('TV release source validation', () {
    test('accepts only tv_v release tag URLs', () {
      expect(
        TvAppUpdateService.tvReleaseTagFromUrl(
          'https://github.com/example/repo/releases/tag/tv_v1.7.9',
        ),
        'tv_v1.7.9',
      );
      expect(
        TvAppUpdateService.tvReleaseTagFromUrl(
          'https://github.com/example/repo/releases/tag/tv_v26.3.20?x=1',
        ),
        'tv_v26.3.20',
      );
      expect(
        TvAppUpdateService.tvReleaseTagFromUrl(
          'https://github.com/example/repo/releases/tag/tv_v26.3.20-dev',
        ),
        'tv_v26.3.20-dev',
      );
      expect(
        TvAppUpdateService.tvReleaseTagFromUrl(
          'https://github.com/example/repo/releases/tag/tv_v26.3.20-pre',
        ),
        'tv_v26.3.20-pre',
      );
    });

    test('rejects normal, dev and malformed release URLs', () {
      for (final url in [
        'https://github.com/example/repo/releases/tag/v1.7.9',
        'https://github.com/example/repo/releases/tag/v1.7.9-dev',
        'https://github.com/example/repo/releases/tag/1.7.9',
        'https://github.com/example/repo/releases/tv_v1.7.9',
        'tv_v1.7.9',
        '',
      ]) {
        expect(TvAppUpdateService.tvReleaseTagFromUrl(url), isNull);
      }
    });
  });

  group('TV asset selection', () {
    test('selects only the TV APK or TV EXE and never extension fallbacks', () {
      final assets = [
        const TvAppDownloadAsset(
          name: 'simple-live-1.7.9-android-universal.apk',
          url: 'https://example.com/ordinary.apk',
        ),
        const TvAppDownloadAsset(
          name: 'simple-live-tv-1.7.9-android-universal.apk',
          url: 'https://example.com/tv.apk',
        ),
        const TvAppDownloadAsset(
          name: 'simple-live-tv-1.7.9-windows.exe',
          url: 'https://example.com/tv.exe',
        ),
        const TvAppDownloadAsset(
          name: 'simple-live-1.7.9-windows.zip',
          url: 'https://example.com/tv.zip',
        ),
      ];

      expect(
        TvAppUpdateService.selectTvAsset(
          assets,
          version: '1.7.9',
          platform: TvAppDownloadPlatform.android,
        )?.name,
        'simple-live-tv-1.7.9-android-universal.apk',
      );
      expect(
        TvAppUpdateService.selectTvAsset(
          assets,
          version: '1.7.9',
          platform: TvAppDownloadPlatform.windows,
        )?.name,
        'simple-live-tv-1.7.9-windows.exe',
      );
    });

    test('rejects ordinary assets when no TV package name is present', () {
      final assets = [
        const TvAppDownloadAsset(
          name: 'simple-live-1.7.9-android-universal.apk',
          url: 'https://example.com/ordinary.apk',
        ),
        const TvAppDownloadAsset(
          name: 'simple-live-1.7.9-windows.exe',
          url: 'https://example.com/ordinary.exe',
        ),
      ];

      expect(
        TvAppUpdateService.selectTvAsset(
          assets,
          version: '1.7.9',
          platform: TvAppDownloadPlatform.android,
        ),
        isNull,
      );
      expect(
        TvAppUpdateService.selectTvAsset(
          assets,
          version: '1.7.9',
          platform: TvAppDownloadPlatform.windows,
        ),
        isNull,
      );
    });
  });
}
