import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/live_room/live_room_channel.dart';

void main() {
  const channels = [
    LiveRoomChannel(siteId: 'douyu', roomId: 'alias-1'),
    LiveRoomChannel(siteId: 'douyu', roomId: '2'),
    LiveRoomChannel(siteId: 'bilibili', roomId: '3'),
  ];

  test('matches the current room by an alternate canonical id', () {
    expect(
      LiveRoomChannelResolver.findCurrentIndex(
        channels,
        siteId: 'douyu',
        roomIds: ['1001', 'alias-1'],
      ),
      0,
    );
  });

  test('wraps previous and next channels in the captured order', () {
    expect(
      LiveRoomChannelResolver.neighbor(
        channels,
        siteId: 'douyu',
        roomIds: ['2'],
        direction: LiveRoomChannelDirection.next,
      )?.key,
      'bilibili_3',
    );
    expect(
      LiveRoomChannelResolver.neighbor(
        channels,
        siteId: 'douyu',
        roomIds: ['alias-1'],
        direction: LiveRoomChannelDirection.previous,
      )?.key,
      'bilibili_3',
    );
  });

  test('returns no target when the current room is absent or list is empty', () {
    expect(
      LiveRoomChannelResolver.neighbor(
        channels,
        siteId: 'huya',
        roomIds: ['404'],
        direction: LiveRoomChannelDirection.next,
      ),
      isNull,
    );
    expect(
      LiveRoomChannelResolver.neighbor(
        const [],
        siteId: 'douyu',
        roomIds: ['alias-1'],
        direction: LiveRoomChannelDirection.next,
      ),
      isNull,
    );
  });

  test('normalizes room ids from list and detail responses before matching', () {
    expect(
      LiveRoomChannelResolver.findCurrentIndex(
        const [LiveRoomChannel(siteId: 'douyu', roomId: '  alias-1  ')],
        siteId: 'douyu',
        roomIds: ['alias-1'],
      ),
      0,
    );
  });
}
