import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('auto mode uses the low-latency profile for FLV', () {
    final options = MpvOptionsService.liveLatencyOptions(
      'auto',
      LiveStreamProtocol.flv,
    );

    expect(options['cache-on-disk'], 'no');
    expect(options['cache-secs'], '0.5');
    expect(options['demuxer-readahead-secs'], '0.5');
    expect(options['cache-pause'], 'no');
  });

  test('auto mode keeps segmented streams conservative', () {
    final options = MpvOptionsService.liveLatencyOptions(
      'auto',
      LiveStreamProtocol.hls,
    );

    expect(options['cache-on-disk'], 'no');
    expect(options['cache-secs'], '1');
    expect(options['demuxer-readahead-secs'], '1');
    expect(options['cache-pause'], 'no');
  });

  test('aggressive mode only tightens FLV/RTMP buffering', () {
    final flv = MpvOptionsService.liveLatencyOptions(
      'aggressive',
      LiveStreamProtocol.rtmp,
    );
    final fmp4 = MpvOptionsService.liveLatencyOptions(
      'aggressive',
      LiveStreamProtocol.fmp4,
    );

    expect(flv['cache-secs'], '0.5');
    expect(flv['demuxer-readahead-secs'], '0.5');
    expect(flv['audio-buffer'], '0');
    expect(fmp4['cache-secs'], '0.5');
    expect(fmp4['cache-pause'], 'no');
  });

  test('off mode restores the existing mpv defaults', () {
    final options = MpvOptionsService.liveLatencyOptions(
      'off',
      LiveStreamProtocol.flv,
    );

    expect(options['cache-on-disk'], 'yes');
    expect(options['cache-secs'], '10');
    expect(options['cache-pause'], 'yes');
  });
}
