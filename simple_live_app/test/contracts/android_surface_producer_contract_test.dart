import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android SurfaceProducer validates the published Surface state', () {
    final source = File(
      '../third_party/media_kit_video/android/src/main/java/'
      'com/alexmercerind/media_kit_video/VideoOutput.java',
    ).readAsStringSync();

    expect(source, contains('surfaceId = surfaceProducer.id();'));
    expect(source, isNot(contains('if (surfaceId == 0)')));
    expect(
      source,
      contains('currentSurface = surfaceProducer.getSurface();'),
    );
    expect(source, contains('publishedSurface == currentSurface'));
    expect(source, contains('publishedWidth == width'));
    expect(source, contains('publishedHeight == height'));
    expect(
      source,
      contains('final long surfaceWid = newGlobalObjectRef(currentSurface);'),
    );
    expect(source, contains('if (surfaceWid == 0)'));
    expect(source, contains('disconnectSurface(surfaceId, width, height);'));
    expect(source, contains('setSurfaceSize(1, 1, true);'));
    expect(source, contains('SURFACE_RELEASE_DELAY_MS = 5000'));
    expect(source, contains('if (closed)'));
    expect(source, isNot(contains('surfaceProducer.getSurface().release()')));
  });
}
