import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/services/live_play_quality_presentation.dart';

LivePlayQuality _quality(String name) =>
    LivePlayQuality(quality: name, data: null);

void main() {
  test('reports each changed actual quality once without losing the request',
      () {
    final tracker = LivePlayQualityMismatchTracker();
    final original = _quality('原画');
    LivePlayQualityPresentation presentation(String actual) =>
        LivePlayQualityPresentation(
          requestedQuality: original,
          actualQuality: _quality(actual),
        );

    final fourM = presentation('蓝光4M');
    expect(fourM.requested, '原画');
    expect(fourM.display, '蓝光4M');
    expect(fourM.comparison, '请求 原画 / 实际 蓝光4M');
    expect(tracker.update(fourM), isNotNull);
    expect(tracker.update(fourM), isNull);
    expect(tracker.update(presentation('超清2M')), contains('超清2M'));
    expect(tracker.update(presentation('原画')), isNull);
    expect(tracker.update(fourM), isNotNull);
  });

  test('unconfirmed quality is explicit and older sites keep their label', () {
    final requested = _quality('原画');
    final unknown = LivePlayQualityPresentation(
      requestedQuality: requested,
      actualQuality: _quality('清晰度未确认'),
    );
    expect(unknown.display, '清晰度未确认');
    final legacy = LivePlayQualityPresentation(
      requestedQuality: requested,
      actualQuality: null,
    );
    expect(legacy.display, '原画');
    expect(legacy.mismatchNotice, isNull);
  });
}
