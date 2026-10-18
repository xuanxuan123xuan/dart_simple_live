import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/sync/remote_sync/room/remote_sync_room_controller.dart';
import 'package:simple_live_app/services/signalr_service.dart';

RoomUser _user({
  String connectionId = 'receiver',
  String platform = 'tv',
  String app = 'Simple Live TV',
  String version = '1.8.0',
  bool isSelf = false,
}) =>
    RoomUser(
      connectionId: connectionId,
      shortId: connectionId,
      platform: platform,
      app: app,
      version: version,
      isSelf: isSelf,
    );

void main() {
  group('new account credential target compatibility', () {
    test('allows only rooms whose receivers are supported TV versions', () {
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets([
          _user(version: '1.8.0'),
          _user(connectionId: 'receiver-2', version: '1.9.2'),
        ]),
        isTrue,
      );
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets([
          _user(platform: 'windows', version: '1.8.0'),
        ]),
        isTrue,
      );
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets(
          [_user(version: '1.7.99')],
        ),
        isFalse,
      );
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets(
          [_user(version: '')],
        ),
        isFalse,
      );
    });

    test('rejects non-TV receivers and does not count the sending device', () {
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets([
          _user(isSelf: true),
          _user(),
        ]),
        isTrue,
      );
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets([
          _user(platform: 'android', app: 'Simple Live'),
        ]),
        isFalse,
      );
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets([
          _user(platform: 'android', app: 'Simple Live TV'),
        ]),
        isFalse,
      );
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets([
          _user(platform: 'linux', app: 'Simple Live TV'),
        ]),
        isFalse,
      );
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets([
          _user(app: 'Simple Live'),
        ]),
        isFalse,
      );
      expect(
        RemoteSyncRoomController.supportsNewAccountTargets(const []),
        isFalse,
      );
    });
  });
}
