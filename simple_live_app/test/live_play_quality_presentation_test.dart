import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/live_play_quality_presentation.dart';
import 'package:simple_live_core/simple_live_core.dart';

LivePlayQuality quality(String name) => LivePlayQuality(
      quality: name,
      data: null,
    );

void main() {
  group('live play quality presentation', () {
    test('same request can announce a second actual-quality change', () {
      final tracker = LivePlayQualityMismatchTracker();
      LivePlayQualityPresentation report(String actual) =>
          LivePlayQualityPresentation(
            requestedQuality: '原画',
            actualQuality: quality(actual),
          );
      expect(tracker.update(report('蓝光4M')), contains('蓝光4M'));
      expect(tracker.update(report('蓝光4M')), isNull);
      expect(tracker.update(report('超清2M')), contains('超清2M'));
    });
    test('shows the reported quality without changing the requested quality',
        () {
      final presentation = LivePlayQualityPresentation(
        requestedQuality: '原画',
        actualQuality: quality('蓝光4M'),
      );

      expect(presentation.displayQuality, '蓝光4M');
      expect(presentation.requestedQuality, '原画');
      expect(presentation.actualQualityName, '蓝光4M');
      expect(presentation.comparisonLabel, '请求：原画 · 实际：蓝光4M');
      expect(presentation.mismatchNotice, '请求原画，实际为蓝光4M');
    });

    test('labels an unconfirmed report and asks once for the same state', () {
      final tracker = LivePlayQualityMismatchTracker();
      final presentation = LivePlayQualityPresentation(
        requestedQuality: '原画',
        actualQuality: quality('清晰度未确认'),
      );

      expect(presentation.displayQuality, '清晰度未确认');
      expect(presentation.comparisonLabel, '请求：原画 · 实际：清晰度未确认');
      expect(tracker.update(presentation), '请求原画，实际清晰度未确认');
      expect(tracker.update(presentation), isNull);
    });

    test('recovers to requested quality and clears the prior warning', () {
      final tracker = LivePlayQualityMismatchTracker();
      final degraded = LivePlayQualityPresentation(
        requestedQuality: '原画',
        actualQuality: quality('蓝光4M'),
      );
      final restored = LivePlayQualityPresentation(
        requestedQuality: '原画',
        actualQuality: quality('原画'),
      );

      expect(tracker.update(degraded), isNotNull);
      expect(tracker.update(restored), isNull);
      expect(tracker.update(degraded), isNotNull);
    });

    test('platforms without actual quality keep requested-quality behavior',
        () {
      final tracker = LivePlayQualityMismatchTracker();
      final presentation = LivePlayQualityPresentation(
        requestedQuality: '超清',
        actualQuality: null,
      );

      expect(presentation.displayQuality, '超清');
      expect(presentation.actualQualityName, isNull);
      expect(presentation.comparisonLabel, isNull);
      expect(tracker.update(presentation), isNull);
    });

    test('reset clears warning state when a room session changes', () {
      final tracker = LivePlayQualityMismatchTracker();
      final presentation = LivePlayQualityPresentation(
        requestedQuality: '原画',
        actualQuality: quality('蓝光4M'),
      );

      expect(tracker.update(presentation), isNotNull);
      tracker.reset();
      expect(tracker.update(presentation), isNotNull);
    });
  });

  test('multi-room actual-quality results require the current operation', () {
    expect(
      isCurrentMultiRoomQualityOperation(
        operationRevision: 4,
        currentOperationRevision: 5,
        operationCancelled: false,
      ),
      isFalse,
    );
    expect(
      isCurrentMultiRoomQualityOperation(
        operationRevision: 5,
        currentOperationRevision: 5,
        operationCancelled: true,
      ),
      isFalse,
    );
    expect(
      isCurrentMultiRoomQualityOperation(
        operationRevision: 5,
        currentOperationRevision: 5,
        operationCancelled: false,
      ),
      isTrue,
    );
  });

  test('queued multi-room selection follows refreshed quality snapshots', () {
    final beforeRefresh = [
      quality('原画'),
      quality('蓝光4M'),
      quality('流畅'),
    ];
    final selected = beforeRefresh[2];

    expect(
      resolveMultiRoomQualityIndex(
        requestedQuality: selected,
        requestedIndex: 2,
        availableQualities: [quality('流畅'), quality('原画')],
      ),
      0,
      reason: 'A reordered quality keeps the user-selected name',
    );
    expect(
      resolveMultiRoomQualityIndex(
        requestedQuality: selected,
        requestedIndex: 2,
        availableQualities: [quality('原画'), quality('蓝光4M')],
      ),
      1,
      reason: 'A removed quality falls back within the new list',
    );
    expect(
      resolveMultiRoomQualityIndex(
        requestedQuality: selected,
        requestedIndex: 2,
        availableQualities: [],
      ),
      isNull,
    );
  });
}
