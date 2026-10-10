import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android SurfaceProducer accepts texture id zero', () {
    final source = File(
      '../third_party/media_kit_video/android/src/main/java/'
      'com/alexmercerind/media_kit_video/VideoOutput.java',
    ).readAsStringSync();

    expect(source, contains('final long surfaceId = surfaceProducer.id();'));
    expect(source, isNot(contains('if (surfaceId == 0)')));
    expect(
      source,
      contains(
        'final long surfaceWid = '
        'newGlobalObjectRef(surfaceProducer.getSurface());',
      ),
    );
    expect(source, contains('if (surfaceWid == 0)'));
    expect(source, contains('setSurfaceSize(1, 1, true);'));
    expect(source, contains('textureUpdateCallback.onTextureUpdate('));
  });
}
