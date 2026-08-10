import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('unknown follow refresh has no completed live status', () {
    expect(followStatusForLiveState(LiveStatusState.live), 2);
    expect(followStatusForLiveState(LiveStatusState.offline), 1);
    expect(followStatusForLiveState(LiveStatusState.unknown), isNull);
  });

  test('Kuaishou follow refresh never schedules logged-in metadata detail', () {
    expect(shouldRefreshFollowMetadata(Constant.kKuaishou), isFalse);
    expect(shouldRefreshFollowMetadata(Constant.kDouyin), isTrue);
  });

  test('Kuaishou follow trace carries scope and force-network policy',
      () async {
    await KuaishouRequestTrace.run(
      KuaishouRequestSource.followStatus,
      () async {
        expect(
            KuaishouRequestTrace.current, KuaishouRequestSource.followStatus);
        expect(KuaishouRequestTrace.scopeId, 'kuaishou:follow-refresh');
        expect(KuaishouRequestTrace.forceNetwork, isTrue);
      },
      scopeId: 'kuaishou:follow-refresh',
      forceNetwork: true,
    );
  });
}
