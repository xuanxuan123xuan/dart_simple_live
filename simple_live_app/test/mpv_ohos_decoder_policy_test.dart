import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/mpv_ohos_decoder_policy.dart';

void main() {
  group('MpvOhosDecoderPolicy', () {
    test('starts HDR and SDR hints with direct OHCodec', () {
      final hdr = MpvOhosDecoderPolicy();
      final sdr = MpvOhosDecoderPolicy();

      final hdrActions = hdr.beginStream(
        hint: const MpvOhosStreamHint(highBitDepth: true),
      );
      final sdrActions = sdr.beginStream(highBitDepth: false);

      expect(hdrActions.single.type, MpvOhosDecoderActionType.setHwdec);
      expect(hdrActions.single.mpvValue, 'ohcodec');
      expect(hdr.snapshot.candidateMode, MpvOhosHwdecMode.direct);
      expect(hdr.snapshot.isHdrHint, isTrue);
      expect(sdrActions.single.mpvValue, 'ohcodec');
      expect(sdr.snapshot.isSdrHint, isTrue);
    });

    test('confirms observed OHCodec and cancels the timer', () {
      final policy = MpvOhosDecoderPolicy();
      policy.beginStream();

      final loaded = policy.onFileLoaded();
      expect(loaded.single.type, MpvOhosDecoderActionType.armConfirmation);
      expect(loaded.single.delay, const Duration(seconds: 8));
      expect(policy.snapshot.confirmationArmed, isTrue);

      final confirmed = policy.onHwdecCurrent('ohcodec');
      expect(
        confirmed.map((action) => action.type),
        containsAll(<MpvOhosDecoderActionType>[
          MpvOhosDecoderActionType.cancelConfirmation,
          MpvOhosDecoderActionType.hardwareActive,
        ]),
      );
      expect(policy.snapshot.hardwareActive, isTrue);
      expect(policy.snapshot.activeMode, MpvOhosHwdecMode.direct);
      expect(policy.snapshot.resolved, isTrue);
      expect(policy.snapshot.confirmationArmed, isFalse);
    });

    test('disabling hardware before FILE_LOADED is deferred', () {
      final policy = MpvOhosDecoderPolicy();
      policy.beginStream();

      expect(policy.setPreferredHwdec(false), isEmpty);
      final actions = policy.onFileLoaded();

      expect(
        actions.first.mpvValue,
        MpvOhosHwdecMode.software.mpvValue,
      );
      expect(policy.snapshot.preferredHwdec, isFalse);
      expect(policy.snapshot.resolved, isTrue);
      expect(policy.snapshot.softwareDecoding, isTrue);
    });

    test('direct timeout switches once to copy, then locks software', () {
      final policy = MpvOhosDecoderPolicy();
      policy.beginStream();
      policy.onFileLoaded();

      final copy = policy.onConfirmationTimeout();
      expect(
        copy.map((action) => action.type),
        containsAll(<MpvOhosDecoderActionType>[
          MpvOhosDecoderActionType.setHwdec,
          MpvOhosDecoderActionType.armConfirmation,
        ]),
      );
      expect(
        copy.where((action) => action.type == MpvOhosDecoderActionType.setHwdec)
            .single
            .mpvValue,
        'ohcodec-copy',
      );
      expect(policy.snapshot.copyFallbackTried, isTrue);
      expect(policy.snapshot.candidateMode, MpvOhosHwdecMode.copy);

      final software = policy.onConfirmationTimeout();
      expect(
        software.where((action) =>
            action.type == MpvOhosDecoderActionType.setHwdec).single.mpvValue,
        'no',
      );
      expect(policy.snapshot.fallenBackToSoftware, isTrue);
      expect(policy.snapshot.softwareDecoding, isTrue);
    });

    test('explicit copy starts at copy and has no second copy attempt', () {
      final policy = MpvOhosDecoderPolicy(
        initialMode: MpvOhosHwdecMode.copy,
      );
      final initial = policy.beginStream();
      expect(initial.single.mpvValue, 'ohcodec-copy');
      expect(policy.snapshot.copyFallbackTried, isTrue);

      policy.onFileLoaded();
      final software = policy.onConfirmationTimeout();
      expect(
        software.where((action) =>
            action.type == MpvOhosDecoderActionType.setHwdec).single.mpvValue,
        'no',
      );
      expect(policy.snapshot.fallenBackToSoftware, isTrue);
    });

    test('third matching interop log switches direct to copy', () {
      final policy = MpvOhosDecoderPolicy();
      policy.beginStream();

      expect(
        policy.onMpvLog('OHCodec Surface interop failed once'),
        isEmpty,
      );
      expect(
        policy.onMpvLog('Timed out waiting for rendered OHCodec Surface buffer'),
        isEmpty,
      );
      final actions = policy.onMpvLog('OHCodec Surface interop failed again');

      expect(policy.snapshot.interopErrors, 3);
      expect(policy.snapshot.copyFallbackTried, isTrue);
      expect(
        actions.where((action) =>
            action.type == MpvOhosDecoderActionType.setHwdec).single.mpvValue,
        'ohcodec-copy',
      );
    });

    test('copy is a hardware confirmation and stops direct log counting', () {
      final policy = MpvOhosDecoderPolicy();
      policy.beginStream();
      policy.onFileLoaded();
      policy.onConfirmationTimeout();

      final confirmed = policy.onHwdecCurrent('ohcodec-copy');
      expect(
        confirmed.where((action) =>
            action.type == MpvOhosDecoderActionType.hardwareActive).single.mode,
        MpvOhosHwdecMode.copy,
      );
      expect(policy.snapshot.hardwareActive, isTrue);
      expect(policy.onMpvLog(directInteropFailureText), isEmpty);
      expect(policy.snapshot.interopErrors, 0);
    });

    test('an early software report does not trigger direct fallback', () {
      final policy = MpvOhosDecoderPolicy();
      policy.beginStream();

      expect(policy.onHwdecCurrent('no'), isEmpty);
      expect(policy.snapshot.copyFallbackTried, isFalse);
      expect(policy.snapshot.activationPending, isTrue);
    });

    test('unknown current values are ignored', () {
      final policy = MpvOhosDecoderPolicy();
      policy.beginStream();

      expect(policy.onHwdecCurrent('auto'), isEmpty);
      expect(policy.snapshot.resolved, isFalse);
      expect(MpvOhosHwdecMode.fromCurrentValue('ohcodec-copy'),
          MpvOhosHwdecMode.copy);
      expect(MpvOhosHwdecMode.fromCurrentValue('software'), isNull);
    });
  });
}

const String directInteropFailureText =
    'OHCodec Surface interop failed';
