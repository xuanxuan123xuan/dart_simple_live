import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/recording/mpv_recording_source.dart';

RecordingFingerprint frame(int microseconds, String hash) =>
    RecordingFingerprint(Duration(microseconds: microseconds), hash);

void main() {
  group('matchRecordingTimeline', () {
    test('three independent frames establish media offset regardless of order',
        () {
      final result = matchRecordingTimeline([
        frame(121000000, 'a'),
        frame(122000000, 'b'),
        frame(123000000, 'c'),
      ], [
        frame(3000000, 'c'),
        frame(1000000, 'a'),
        frame(2000000, 'b')
      ]);
      expect(result?.confirmed, isTrue);
      expect(result?.mediaStart, const Duration(seconds: 120));
    });

    test('one or two common frames cannot confirm an origin', () {
      expect(
          matchRecordingTimeline([frame(100, 'a'), frame(200, 'b')],
              [frame(0, 'a'), frame(100, 'b')]),
          isNull);
    });

    test('a static scene with many timestamps cannot establish offset', () {
      expect(
          matchRecordingTimeline(
              List.generate(20, (i) => frame(1000000 + i * 1000, 'static')),
              List.generate(20, (i) => frame(i * 1000, 'static'))),
          isNull);
    });

    test('ambiguous source frames are excluded from independent evidence', () {
      expect(
          matchRecordingTimeline([
            frame(1000000, 'a'),
            frame(2000000, 'b'),
            frame(3000000, 'c'),
            frame(4000000, 'c'),
          ], [
            frame(0, 'a'),
            frame(1000000, 'b'),
            frame(2000000, 'c')
          ]),
          isNull);
    });

    test('ambiguous recorded frames cannot confirm a guessed origin', () {
      expect(
          matchRecordingTimeline([
            frame(1000000, 'a'),
            frame(2000000, 'b'),
            frame(3000000, 'c'),
          ], [
            frame(0, 'a'),
            frame(1000000, 'b'),
            frame(2000000, 'c'),
            frame(3000000, 'c')
          ]),
          isNull);
    });

    test('disagreeing offsets reject evidence even with three good matches',
        () {
      expect(
          matchRecordingTimeline([
            frame(1000000, 'a'),
            frame(2000000, 'b'),
            frame(3000000, 'c'),
            frame(5000000, 'd'),
          ], [
            frame(0, 'a'),
            frame(1000000, 'b'),
            frame(2000000, 'c'),
            frame(3000000, 'd')
          ]),
          isNull);
    });

    test('subframe PTS rounding uses robust median without wall time', () {
      final result = matchRecordingTimeline([
        frame(1000000, 'a'),
        frame(2010000, 'b'),
        frame(2990000, 'c'),
      ], [
        frame(0, 'a'),
        frame(1000000, 'b'),
        frame(2000000, 'c')
      ]);
      expect(result?.mediaStart, const Duration(seconds: 1));
    });

    test('no common content provides no timeline', () {
      expect(matchRecordingTimeline([frame(0, 'a')], [frame(0, 'b')]), isNull);
    });
  });

  group('parseRecordingFingerprints', () {
    final hash = List.filled(512, 'a').join();
    test('parses native decimal media PTS and complete grayscale hash', () {
      final frames = parseRecordingFingerprints(jsonEncode({
        'fp0.pts': '12.345678',
        'fp0.hex': hash,
        'fp1.pts': 13,
        'fp1.hex': hash.replaceAll('a', 'b'),
      }));
      expect(frames.length, 2);
      expect(frames.first.position.inMicroseconds, 12345678);
      expect(frames.first.fingerprint, hash);
      expect(frames.last.position, const Duration(seconds: 13));
    });

    test('ignores missing PTS, nonfinite timestamps and truncated hashes', () {
      expect(
          parseRecordingFingerprints(jsonEncode({
            'fp0.hex': hash,
            'fp1.pts': 'NaN',
            'fp1.hex': hash,
            'fp2.pts': 'Infinity',
            'fp2.hex': hash,
            'fp3.pts': '1',
            'fp3.hex': 'abcd',
            'fp4.pts': '2',
            'fp4.hex': hash,
          })).map((frame) => frame.position),
          [const Duration(seconds: 2)]);
    });

    test('malformed or unrelated metadata never invents a frame', () {
      for (final metadata in [
        '',
        'not JSON',
        '[]',
        'null',
        '{}',
        '{"fp0.pts":1}'
      ]) {
        expect(parseRecordingFingerprints(metadata), isEmpty);
      }
    });
  });
}
