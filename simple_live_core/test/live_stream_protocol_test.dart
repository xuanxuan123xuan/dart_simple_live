import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  group('classifyLiveStreamProtocol', () {
    test('recognizes RTMP schemes before path and query hints', () {
      expect(
        classifyLiveStreamProtocol(
          'RTMPS://stream.example/live.m3u8?format=flv',
        ),
        LiveStreamProtocol.rtmp,
      );
      expect(
        classifyLiveStreamProtocol('rtmp://stream.example/live'),
        LiveStreamProtocol.rtmp,
      );
    });

    test('recognizes case-insensitive path extensions with query strings', () {
      expect(
        classifyLiveStreamProtocol('https://stream.example/live.FLV?token=abc'),
        LiveStreamProtocol.flv,
      );
      expect(
        classifyLiveStreamProtocol(
            'https://stream.example/live.M3U8?token=abc'),
        LiveStreamProtocol.hls,
      );
      expect(
        classifyLiveStreamProtocol('https://stream.example/live.MP4?token=abc'),
        LiveStreamProtocol.fmp4,
      );
    });

    test('recognizes only explicit format and type query values', () {
      expect(
        classifyLiveStreamProtocol('https://stream.example/live?FORMAT=HLS'),
        LiveStreamProtocol.hls,
      );
      expect(
        classifyLiveStreamProtocol('https://stream.example/live?type=FMP4'),
        LiveStreamProtocol.fmp4,
      );
      expect(
        classifyLiveStreamProtocol('https://stream.example/live?type=flv'),
        LiveStreamProtocol.flv,
      );
      expect(
        classifyLiveStreamProtocol(
            'https://stream.example/live?description=flv'),
        LiveStreamProtocol.unknown,
      );
    });

    test('returns unknown for invalid URLs and unsupported schemes', () {
      expect(classifyLiveStreamProtocol(null), LiveStreamProtocol.unknown);
      expect(
          classifyLiveStreamProtocol('not a URL'), LiveStreamProtocol.unknown);
      expect(
        classifyLiveStreamProtocol('https:///live.m3u8'),
        LiveStreamProtocol.unknown,
      );
      expect(
        classifyLiveStreamProtocol('rtsp://stream.example/live.flv'),
        LiveStreamProtocol.unknown,
      );
      expect(
        classifyLiveStreamProtocol('https://stream.example/live.flv.backup'),
        LiveStreamProtocol.unknown,
      );
    });
  });

  test('labels are stable for logs', () {
    expect(LiveStreamProtocol.flv.label, 'flv');
    expect(LiveStreamProtocol.hls.label, 'hls');
    expect(LiveStreamProtocol.fmp4.label, 'fmp4');
    expect(LiveStreamProtocol.rtmp.label, 'rtmp');
    expect(LiveStreamProtocol.unknown.label, 'unknown');
  });

  test('sorts by latency tier without dropping or reordering CDNs', () {
    final urls = [
      'https://hls-a.example/live.m3u8',
      'https://fmp4-a.example/live.mp4',
      'https://flv-a.example/live.flv',
      'https://unknown.example/live',
      'rtmp://rtmp-a.example/live',
      'https://flv-b.example/live.flv',
      'https://hls-b.example/live.m3u8',
    ];

    expect(sortLiveStreamUrlsByLatency(urls), [
      'https://flv-a.example/live.flv',
      'rtmp://rtmp-a.example/live',
      'https://flv-b.example/live.flv',
      'https://fmp4-a.example/live.mp4',
      'https://unknown.example/live',
      'https://hls-a.example/live.m3u8',
      'https://hls-b.example/live.m3u8',
    ]);
  });

  test('finds only the best protocol tier for line selection', () {
    expect(
      lowestLatencyLineIndices([
        'https://hls.example/live.m3u8',
        'https://flv-a.example/live.flv',
        'https://flv-b.example/live.flv',
      ]),
      [1, 2],
    );
  });
}
