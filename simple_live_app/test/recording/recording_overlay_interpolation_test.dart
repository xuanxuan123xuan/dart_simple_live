import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/recording/recording_overlay_interpolation.dart';

void main() {
  group('interpolateRecordingOverlayFrame', () {
    test('interpolates continuous values for a 33 ms capture gap', () {
      final current =
          _frame(0, [_item(x: 0, y: 10, opacity: .2, instanceId: 'moving')]);
      final next =
          _frame(33, [_item(x: 33, y: 43, opacity: .8, instanceId: 'moving')]);

      final frame = interpolateRecordingOverlayFrame(current, next, 16.5)!;

      expect(frame['positionMs'], 16.5);
      final item = (frame['items'] as List).single as Map<String, dynamic>;
      expect(item['x'], 16.5);
      expect(item['y'], 26.5);
      expect(item['opacity'], closeTo(.5, 1e-12));
    });

    test('matches duplicate assets by explicit instance id despite reordering',
        () {
      final current = _frame(0, [
        _item(x: 0, instanceId: 'first'),
        _item(x: 100, instanceId: 'second'),
      ]);
      final next = _frame(100, [
        _item(x: 130, instanceId: 'second'),
        _item(x: 30, instanceId: 'first'),
      ]);

      final frame = interpolateRecordingOverlayFrame(current, next, 50)!;
      final items = frame['items'] as List;

      expect((items[0] as Map)['x'], 15);
      expect((items[1] as Map)['x'], 115);
      expect((items[0] as Map)['instanceId'], 'first');
      expect((items[1] as Map)['instanceId'], 'second');
    });

    test('pairs legacy duplicate assets by mutual nearest position', () {
      final current = _frame(0, [_item(x: 10), _item(x: 70)]);
      final next = _frame(100, [_item(x: 18), _item(x: 62)]);

      final frame = interpolateRecordingOverlayFrame(current, next, 50)!;
      final items = frame['items'] as List;

      expect((items[0] as Map)['x'], 14);
      expect((items[1] as Map)['x'], 66);
    });

    test('holds legacy items when nearest matches are ambiguous', () {
      final current = _frame(0, [_item(x: 50), _item(x: 50)]);
      final next = _frame(100, [_item(x: 50), _item(x: 50)]);

      expect(
          interpolateRecordingOverlayFrame(current, next, 50), same(current));
    });

    test('holds duplicate explicit instance ids in either snapshot', () {
      for (final duplicateCurrent in [false, true]) {
        final single = [_item(x: 0, instanceId: 'reused')];
        final duplicate = [
          _item(x: 2, instanceId: 'reused'),
          _item(x: 4, instanceId: 'reused'),
        ];
        final current = _frame(0, duplicateCurrent ? duplicate : single);
        final next = _frame(100, duplicateCurrent ? single : duplicate);

        expect(
            interpolateRecordingOverlayFrame(current, next, 50), same(current));
      }
    });

    test('legacy matches are one-to-one and require mutual nearest positions',
        () {
      final current = _frame(0, [_item(x: 0), _item(x: 4)]);
      final next = _frame(100, [_item(x: 1)]);

      final frame = interpolateRecordingOverlayFrame(current, next, 50)!;
      final items = frame['items'] as List;

      expect(items[0]['x'], .5);
      expect(items[1]['x'], 4);
    });

    test('holds legacy items beyond the conservative movement limit', () {
      final current = _frame(0, [_item(x: 0)]);
      final next = _frame(33, [_item(x: 33)]);

      expect(
          interpolateRecordingOverlayFrame(current, next, 16.5), same(current));
    });

    test('holds explicit instances when their asset or dimensions change', () {
      final current = _frame(0, [_item(x: 0, instanceId: 'same')]);
      final resized =
          _frame(100, [_item(x: 10, width: 21, instanceId: 'same')]);
      final replaced = _frame(100, [
        _item(x: 10, instanceId: 'same')..['spriteId'] = 'replacement',
      ]);

      expect(interpolateRecordingOverlayFrame(current, resized, 50),
          same(current));
      expect(interpolateRecordingOverlayFrame(current, replaced, 50),
          same(current));
    });

    test('does not interpolate across a gap longer than 100 ms', () {
      final current = _frame(0, [_item(x: 0, instanceId: 'sprite')]);
      final next = _frame(101, [_item(x: 100, instanceId: 'sprite')]);

      expect(
          interpolateRecordingOverlayFrame(current, next, 50), same(current));
    });

    test('holds when group opacity changes', () {
      final current = _frame(0, [_item(x: 0)], opacity: 1);
      final next = _frame(100, [_item(x: 100)], opacity: .5);

      expect(
          interpolateRecordingOverlayFrame(current, next, 50), same(current));
    });

    test('holds when viewport geometry changes', () {
      final current = _frame(0, [_item(x: 0)]);
      final next = _frame(100, [_item(x: 100)], videoLeft: 1);

      expect(
          interpolateRecordingOverlayFrame(current, next, 50), same(current));
    });

    test('keeps births and disappearances discrete at the next timestamp', () {
      final oldItem = _item(x: 0, instanceId: 'old');
      final secondItem = _item(x: 20, instanceId: 'second');
      final currentWithOne = _frame(0, [oldItem]);
      final nextWithTwo = _frame(100, [
        _item(x: 10, instanceId: 'old'),
        _item(x: 20, instanceId: 'new'),
      ]);

      final beforeBirth =
          interpolateRecordingOverlayFrame(currentWithOne, nextWithTwo, 50)!;
      expect((beforeBirth['items'] as List), hasLength(1));
      expect((beforeBirth['items'] as List).single['instanceId'], 'old');
      expect(interpolateRecordingOverlayFrame(currentWithOne, nextWithTwo, 100),
          same(nextWithTwo));

      final currentWithTwo = _frame(0, [oldItem, secondItem]);
      final nextWithOne = _frame(100, [_item(x: 10, instanceId: 'old')]);
      final beforeDisappearance =
          interpolateRecordingOverlayFrame(currentWithTwo, nextWithOne, 99)!;
      expect(beforeDisappearance['items'], hasLength(2));
      expect(interpolateRecordingOverlayFrame(currentWithTwo, nextWithOne, 100),
          same(nextWithOne));
    });

    test('interpolates all entries of a valid 4 by 4 transform', () {
      final identity = <double>[
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ];
      final translated = [...identity]..[12] = 20;
      final current = _frame(0, [_item(x: 0, transform: identity)]);
      final next = _frame(100, [_item(x: 0, transform: translated)]);

      final frame = interpolateRecordingOverlayFrame(current, next, 50)!;
      final transform =
          ((frame['items'] as List).single as Map)['transform'] as List;

      expect(transform, hasLength(16));
      expect(transform[12], 10);
      expect(transform.every((value) => (value as num).isFinite), isTrue);
    });

    test('malformed numeric values are not turned into non-finite output', () {
      final currentMatrix = List<double>.filled(16, 0)..[0] = 1;
      final invalidNextMatrix = [...currentMatrix]..[12] = double.infinity;
      final current = _frame(0, [
        _item(x: 2, y: 5, instanceId: 'sprite', transform: currentMatrix),
      ]);
      final next = _frame(100, [
        _item(
          x: double.nan,
          y: 15,
          instanceId: 'sprite',
          transform: invalidNextMatrix,
        ),
      ]);

      final frame = interpolateRecordingOverlayFrame(current, next, 50)!;
      final item = (frame['items'] as List).single as Map<String, dynamic>;

      expect(item['x'], 2);
      expect(item['y'], 10);
      expect(item['transform'], currentMatrix);
      expect((item['transform'] as List).every((v) => (v as num).isFinite),
          isTrue);
    });

    test('does not extrapolate and preserves current timestamp metadata', () {
      final current = _frame(10, [_item(x: 1, instanceId: 'sprite')]);
      final next = _frame(20, [_item(x: 11, instanceId: 'sprite')]);

      expect(interpolateRecordingOverlayFrame(current, next, 9), same(current));
      expect(
          interpolateRecordingOverlayFrame(current, next, 21), same(current));
      expect(
          interpolateRecordingOverlayFrame(current, next, 10), same(current));
      expect(interpolateRecordingOverlayFrame(null, next, 10), isNull);
    });

    test('does not mutate either source frame or nested item data', () {
      final current = _frame(0, [
        _item(x: 0, instanceId: 'sprite')
          ..['custom'] = {
            'keep': [1, 2]
          },
      ]);
      final next = _frame(100, [_item(x: 100, instanceId: 'sprite')]);
      final currentBefore = jsonDecode(jsonEncode(current));
      final nextBefore = jsonDecode(jsonEncode(next));

      final output = interpolateRecordingOverlayFrame(current, next, 50)!;

      expect(current, currentBefore);
      expect(next, nextBefore);
      expect(output, isNot(same(current)));
      expect((output['items'] as List).single,
          isNot(same((current['items'] as List).single)));
      expect(
        ((output['items'] as List).single as Map)['custom'],
        {
          'keep': [1, 2]
        },
      );
    });
  });
}

Map<String, dynamic> _frame(
  num time,
  List<Map<String, dynamic>> items, {
  double opacity = 1,
  double videoLeft = 0,
}) =>
    <String, dynamic>{
      'positionMs': time,
      'canvasWidth': 1000,
      'canvasHeight': 600,
      'videoLeft': videoLeft,
      'videoTop': 0,
      'videoWidth': 1000,
      'videoHeight': 600,
      'opacity': opacity,
      'items': items,
    };

Map<String, dynamic> _item({
  required num x,
  num y = 10,
  double width = 20,
  double height = 10,
  num opacity = 1,
  String? instanceId,
  List<num>? transform,
}) =>
    <String, dynamic>{
      if (instanceId != null) 'instanceId': instanceId,
      'spriteId': 'shared',
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'opacity': opacity,
      'transform': transform,
      'transformOriginX': 0,
      'transformOriginY': 0,
    };
