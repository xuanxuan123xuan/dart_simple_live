import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  test('unknown follow refresh preserves the previous status', () {
    expect(followStatusForLiveState(LiveStatusState.live), 2);
    expect(followStatusForLiveState(LiveStatusState.offline), 1);
    expect(followStatusForLiveState(LiveStatusState.unknown), isNull);
  });
}
