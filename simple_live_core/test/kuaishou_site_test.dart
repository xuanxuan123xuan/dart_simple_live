import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('KuaishouSite.resolveRoomTitle', () {
    test('prefers the room caption over the author name', () {
      expect(
        KuaishouSite.resolveRoomTitle({
          'caption': '今晚冲榜',
          'author': {'name': '测试主播'},
          'gameInfo': {'name': '王者荣耀'},
        }),
        '今晚冲榜',
      );
    });

    test('falls back through stream, game, and author fields', () {
      expect(
        KuaishouSite.resolveRoomTitle({
          'liveStream': {'caption': '直播流标题'},
          'author': {'name': '测试主播'},
        }),
        '直播流标题',
      );
      expect(
        KuaishouSite.resolveRoomTitle({
          'gameInfo': {'name': '主机游戏'},
          'author': {'name': '测试主播'},
        }),
        '主机游戏',
      );
      expect(
        KuaishouSite.resolveRoomTitle({
          'author': {'name': '测试主播'},
        }),
        '测试主播',
      );
    });
  });

  group('KuaishouSite.resolveLiveStatus', () {
    test('accepts explicit live flags', () {
      expect(KuaishouSite.resolveLiveStatus({'isLiving': true}), isTrue);
      expect(KuaishouSite.resolveLiveStatus({'living': 1}), isTrue);
    });

    test('uses playable stream evidence when the flag is stale', () {
      expect(
        KuaishouSite.resolveLiveStatus({
          'isLiving': false,
          'liveStream': {
            'id': 'stream-id',
            'playUrls': {
              'h264': {
                'adaptationSet': {
                  'representation': [
                    {'url': 'https://example.com/live.flv'},
                  ],
                },
              },
            },
          },
        }),
        isTrue,
      );
    });

    test('accepts the flat room-list stream shape used by the live API', () {
      expect(
        KuaishouSite.resolveLiveStatus({
          'id': 'stream-id',
          'living': false,
          'playUrls': [
            {
              'adaptationSet': {
                'representation': [
                  {'url': 'https://example.com/live.flv'},
                ],
              },
            },
          ],
        }),
        isTrue,
      );
    });

    test('does not mark an empty stream as live', () {
      expect(
        KuaishouSite.resolveLiveStatus({
          'isLiving': false,
          'liveStream': {'id': '', 'playUrls': const {}},
        }),
        isFalse,
      );
    });
  });

  test('parses qualities from the flat room-list playUrls payload', () async {
    final detail = LiveRoomDetail(
      roomId: 'author-id',
      title: '直播间',
      cover: '',
      userName: '主播',
      userAvatar: '',
      online: 1,
      status: true,
      url: 'stream-id',
      data: [
        {
          'type': 'dynamic',
          'adaptationSet': {
            'representation': [
              {
                'name': '高清',
                'level': 30,
                'url': 'https://example.com/sd.flv',
              },
              {
                'name': '蓝光',
                'level': 70,
                'url': 'https://example.com/hd.flv',
              },
            ],
          },
        },
      ],
    );

    final qualities = await KuaishouSite().getPlayQualites(detail: detail);

    expect(qualities.map((item) => item.quality), ['蓝光', '高清']);
    expect(qualities.first.data, ['https://example.com/hd.flv']);
  });

  test('falls back when advertised h264 group has no stream', () async {
    final detail = LiveRoomDetail(
      roomId: 'room-id',
      title: '直播间',
      cover: '',
      userName: '主播',
      userAvatar: '',
      online: 1,
      status: true,
      url: 'stream-id',
      data: {
        'h264': const [],
        'hevc': [
          {
            'name': '蓝光',
            'level': 70,
            'url': 'https://example.com/hevc.flv',
          },
        ],
      },
    );

    final qualities = await KuaishouSite().getPlayQualites(detail: detail);

    expect(qualities, hasLength(1));
    expect(qualities.first.quality, '蓝光');
    expect(qualities.first.data, ['https://example.com/hevc.flv']);
  });

  group('KuaishouSite live-state aggregation', () {
    test('stream id is live even while playback url is delayed', () {
      expect(
        KuaishouSite.resolveLiveState({
          'liveStream': {'id': 'stream-id', 'playUrls': const {}},
        }),
        LiveStatusState.live,
      );
    });

    test('distinguishes explicit offline and missing evidence', () {
      expect(
        KuaishouSite.resolveLiveState({'isLiving': false}),
        LiveStatusState.offline,
      );
      expect(
        KuaishouSite.resolveLiveState({'caption': '风控或不完整响应'}),
        LiveStatusState.unknown,
      );
    });

    test('scans every playList item and live evidence wins', () {
      expect(
        KuaishouSite.resolvePlayListState([
          {'isLiving': false},
          {
            'liveStream': {'id': 'second-live-stream'},
          },
        ]),
        LiveStatusState.live,
      );
    });

    test('mixed offline and unknown remains unknown', () {
      expect(
        KuaishouSite.resolvePlayListState([
          {'isLiving': false},
          {'caption': '字段缺失'},
        ]),
        LiveStatusState.unknown,
      );
    });
  });

  test('extracts nested playable urls and rejects non-stream values', () {
    expect(
      KuaishouSite.extractPlayableUrls({
        'url': {
          'primary': 'https://example.com/live.flv',
          'backup': [
            'rtmp://example.com/live',
            'https://example.com/live.flv',
            'ftp://example.com/not-supported',
          ],
        },
        'label': '高清',
      }),
      [
        'https://example.com/live.flv',
        'rtmp://example.com/live',
      ],
    );
  });

  test('does not stringify a nested url object as a playback address',
      () async {
    final detail = LiveRoomDetail(
      roomId: 'room-id',
      title: '直播间',
      cover: '',
      userName: '主播',
      userAvatar: '',
      online: 1,
      status: true,
      url: 'https://live.kuaishou.com/u/room-id',
      data: {
        'h264': [
          {
            'name': '蓝光',
            'level': 70,
            'url': {
              'primary': 'https://example.com/live.flv',
            },
          },
        ],
      },
    );

    final qualities = await KuaishouSite().getPlayQualites(detail: detail);
    expect(qualities, hasLength(1));
    expect(qualities.single.data, ['https://example.com/live.flv']);
  });

  group('KuaishouSite.isImageUrl', () {
    test('无扩展名的 http(s) URL 视为图片（快手实时截图）', () {
      expect(
        KuaishouSite.isImageUrl(
          'https://live3.static.yximgs.com/live/game/screenshot/9tFQiiOLSg8~1785822457911~1',
        ),
        isTrue,
      );
    });

    test('常规图片扩展名视为图片', () {
      expect(KuaishouSite.isImageUrl('https://x.com/a.png'), isTrue);
      expect(KuaishouSite.isImageUrl('https://x.com/a.jpg'), isTrue);
      expect(KuaishouSite.isImageUrl('https://x.com/a.jpg?v=1'), isTrue);
    });

    test('非图片扩展名与空串不是图片', () {
      expect(KuaishouSite.isImageUrl('https://x.com/a.html'), isFalse);
      expect(KuaishouSite.isImageUrl('https://x.com/a.js'), isFalse);
      expect(KuaishouSite.isImageUrl(''), isFalse);
    });
  });
}
