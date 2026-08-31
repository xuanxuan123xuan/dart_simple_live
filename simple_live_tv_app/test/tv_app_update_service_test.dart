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
      'download_url': 'https://github.com/example/releases/tag/tv_v1.7.9',
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
}
