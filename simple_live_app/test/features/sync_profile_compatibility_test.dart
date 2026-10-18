import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/sync/remote_sync/webdav/remote_sync_webdav_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';

void main() {
  group('profile sync compatibility', () {
    test('exports schema 4 and accepts legacy schemas 1 through 4', () {
      expect(ProfileBackupService.schemaVersion, 4);
      for (final version in [1, 2, 3, 4]) {
        expect(
          ProfileBackupService.isSupportedSchemaVersion(version),
          isTrue,
          reason: 'schema $version remains importable',
        );
      }
      expect(ProfileBackupService.isSupportedSchemaVersion(5), isFalse);
    });

    test('never exports account cookies as settings', () {
      final filtered = ProfileBackupService().filterTransportSettings({
        LocalStorageService.kBilibiliCookie: 'bili-secret',
        LocalStorageService.kDouyinCookie: 'douyin-secret',
        LocalStorageService.kDouyuCookie: 'douyu-secret',
        LocalStorageService.kXiaohongshuCookie: 'xhs-secret',
        LocalStorageService.kKuaishouCookie: 'ks-secret',
        LocalStorageService.kKuaishouSecondaryCookie: 'ks-secondary-secret',
        'playerVolume': 65,
      });

      expect(filtered, {'playerVolume': 65});
    });

    test('recognizes profile archives so legacy files are fallback only', () {
      expect(
        RemoteSyncWebDAVController.archiveContainsProfile([
          'SimpleLive_Profile_v4.json',
        ]),
        isTrue,
      );
      expect(
        RemoteSyncWebDAVController.archiveContainsProfile([
          'SimpleLive_Profile_v3.json',
        ]),
        isTrue,
      );
      expect(
        RemoteSyncWebDAVController.archiveContainsProfile([
          'SimpleLive_Profile_v2.json',
        ]),
        isTrue,
      );
      expect(
        RemoteSyncWebDAVController.archiveContainsProfile([
          'SimpleLive_Settings.json',
          'SimpleLive_bilibili_account.json',
        ]),
        isFalse,
      );
    });
  });
}
