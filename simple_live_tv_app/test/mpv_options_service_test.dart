import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/services/mpv_options_service.dart';

void main() {
  group('MpvOptionsService', () {
    test('performance profile is labelled as smooth, not compatibility mode',
        () {
      expect(MpvOptionsService.profileLabels['performance'], '流畅');
      expect(MpvOptionsService.profileLabels.values, isNot(contains('兼容')));
    });

    test('safe defaults retain balanced gpu hardware decoding', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'balanced',
        customOutput: false,
        videoOutput: 'mediacodec_embed',
        hardwareDecoder: 'mediacodec',
        audioOutput: 'aaudio',
        advancedOptions: '',
        hardwareDecodeEnabled: true,
      );

      expect(effective.options['vo'], 'gpu');
      expect(effective.options['hwdec'], 'auto-safe');
      expect(effective.options.containsKey('ao'), isFalse);
      expect(effective.source['vo'], 'profile:balanced');
    });

    test('custom output overrides profile and raw options override custom', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'balanced',
        customOutput: true,
        videoOutput: 'mediacodec_embed',
        hardwareDecoder: 'mediacodec',
        audioOutput: 'aaudio',
        advancedOptions: '--vo=gpu-next\nao=opensles\ncache=yes',
        hardwareDecodeEnabled: true,
      );

      expect(effective.options['vo'], 'gpu-next');
      expect(effective.options['hwdec'], 'mediacodec');
      expect(effective.options['ao'], 'opensles');
      expect(effective.options['cache'], 'yes');
      expect(effective.source['vo'], 'advanced');
    });

    test('hardware switch forces software decoding last', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'quality',
        customOutput: true,
        videoOutput: 'gpu',
        hardwareDecoder: 'mediacodec',
        audioOutput: 'audiotrack',
        advancedOptions: 'hwdec=auto',
        hardwareDecodeEnabled: false,
      );

      expect(effective.options['hwdec'], 'no');
      expect(effective.source['hwdec'], 'hardware-switch');
    });

    test('Android compatibility mode has the highest output priority', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'quality',
        customOutput: true,
        videoOutput: 'gpu-next',
        hardwareDecoder: 'no',
        audioOutput: 'audiotrack',
        advancedOptions: 'vo=libmpv\nhwdec=auto',
        hardwareDecodeEnabled: false,
        compatMode: true,
        isAndroid: true,
      );

      expect(effective.options['vo'], 'mediacodec_embed');
      expect(effective.options['hwdec'], 'mediacodec');
      expect(effective.source['vo'], 'compat-mode');
      expect(effective.source['hwdec'], 'compat-mode');
    });

    test('Android compatibility mode also overrides hardware decode switch',
        () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'performance',
        customOutput: true,
        videoOutput: 'gpu-next',
        hardwareDecoder: 'no',
        audioOutput: 'audiotrack',
        advancedOptions: 'vo=libmpv\nhwdec=no',
        hardwareDecodeEnabled: false,
        compatMode: true,
        isAndroid: true,
      );

      expect(effective.options['vo'], 'mediacodec_embed');
      expect(effective.options['hwdec'], 'mediacodec');
      expect(effective.source['vo'], 'compat-mode');
      expect(effective.source['hwdec'], 'compat-mode');
    });

    test('parser accepts mpv syntax and ignores comments or invalid lines', () {
      expect(
        MpvOptionsService.parseOptions(
          '# comment\n--cache=yes\ndemuxer-readahead-secs=2 # note\ninvalid',
        ),
        {
          'cache': 'yes',
          'demuxer-readahead-secs': '2',
        },
      );
    });

    test('render fallback stage 0 keeps user configuration untouched', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'balanced',
        customOutput: false,
        videoOutput: 'gpu',
        hardwareDecoder: 'auto-safe',
        audioOutput: 'audiotrack',
        advancedOptions: '',
        hardwareDecodeEnabled: true,
        isAndroid: true,
        renderFallbackStage: MpvOptionsService.renderStageDefault,
      );

      expect(effective.options['vo'], 'gpu');
      expect(effective.options['hwdec'], 'auto-safe');
      expect(
        effective.options.values,
        everyElement(isNot(MpvOptionsService.kRenderFallbackSource)),
      );
      expect(
        effective.source.values,
        isNot(contains(MpvOptionsService.kRenderFallbackSource)),
      );
    });

    test('render fallback stage 1 switches to mediacodec direct surface', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'balanced',
        customOutput: false,
        videoOutput: 'gpu',
        hardwareDecoder: 'auto-safe',
        audioOutput: 'audiotrack',
        advancedOptions: '',
        hardwareDecodeEnabled: true,
        isAndroid: true,
        renderFallbackStage: MpvOptionsService.renderStageMediacodecEmbed,
      );

      expect(effective.options['vo'], 'mediacodec_embed');
      expect(effective.options['hwdec'], 'mediacodec');
      expect(effective.source['vo'], MpvOptionsService.kRenderFallbackSource);
      expect(
        effective.source['hwdec'],
        MpvOptionsService.kRenderFallbackSource,
      );
    });

    test('render fallback stage 2 falls back to software decoding', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'balanced',
        customOutput: false,
        videoOutput: 'gpu',
        hardwareDecoder: 'auto-safe',
        audioOutput: 'audiotrack',
        advancedOptions: '',
        hardwareDecodeEnabled: true,
        isAndroid: true,
        renderFallbackStage: MpvOptionsService.renderStageSoftwareDecode,
      );

      expect(effective.options['vo'], 'gpu');
      expect(effective.options['hwdec'], 'no');
      expect(effective.source['hwdec'], MpvOptionsService.kRenderFallbackSource);
    });

    test('render fallback stage overrides win over compat mode', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'balanced',
        customOutput: false,
        videoOutput: 'gpu',
        hardwareDecoder: 'auto-safe',
        audioOutput: 'audiotrack',
        advancedOptions: '',
        hardwareDecodeEnabled: true,
        compatMode: true,
        isAndroid: true,
        renderFallbackStage: MpvOptionsService.renderStageSoftwareDecode,
      );

      expect(effective.options['vo'], 'gpu');
      expect(effective.options['hwdec'], 'no');
    });

    test('render fallback stage is ignored on non-Android platforms', () {
      final effective = MpvOptionsService.mergeOptions(
        profile: 'balanced',
        customOutput: false,
        videoOutput: 'gpu',
        hardwareDecoder: 'auto-safe',
        audioOutput: 'audiotrack',
        advancedOptions: '',
        hardwareDecodeEnabled: true,
        isAndroid: false,
        renderFallbackStage: MpvOptionsService.renderStageMediacodecEmbed,
      );

      expect(effective.options['vo'], 'gpu');
      expect(effective.options['hwdec'], 'auto-safe');
    });

    test('render fallback stage chain advances then exhausts', () {
      expect(
        MpvOptionsService.nextRenderFallbackStage(
          MpvOptionsService.renderStageDefault,
        ),
        MpvOptionsService.renderStageMediacodecEmbed,
      );
      expect(
        MpvOptionsService.nextRenderFallbackStage(
          MpvOptionsService.renderStageMediacodecEmbed,
        ),
        MpvOptionsService.renderStageSoftwareDecode,
      );
      expect(
        MpvOptionsService.nextRenderFallbackStage(
          MpvOptionsService.renderStageSoftwareDecode,
        ),
        -1,
      );
    });
  });
}
