import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/models/auto_switch_item.dart';
import 'package:simple_live_tv_app/services/auto_switch_list_service.dart';

void main() {
  AutoSwitchItem item(String id, int status) => AutoSwitchItem(
        id: id,
        siteId: 'site',
        roomId: id,
        userName: id,
        face: '',
        liveStatus: status,
      );

  test('playlist status cache is one minute', () {
    expect(
      AutoSwitchListService.statusCacheTtl,
      const Duration(seconds: 60),
    );
    final now = DateTime(2026, 1, 1, 12);
    expect(
      AutoSwitchListService.isStatusFresh(
        now.subtract(const Duration(seconds: 59)),
        now,
      ),
      isTrue,
    );
    expect(
      AutoSwitchListService.isStatusFresh(
        now.subtract(const Duration(seconds: 60)),
        now,
      ),
      isFalse,
    );
  });

  test(
      'ordered next follows persisted playlist order even when current is offline',
      () {
    final service = AutoSwitchListService();
    service.items.value = [
      item('one', 2),
      item('two', 1),
      item('three', 2),
      item('four', 2),
    ];

    expect(service.nextLive('one')?.id, 'three');
    expect(service.nextLive('two')?.id, 'three');
    expect(service.nextLive('four')?.id, 'one');
  });

  test('random next never returns the current room', () {
    final service = AutoSwitchListService();
    service.items.value = [item('one', 2), item('two', 2)];

    for (var i = 0; i < 20; i++) {
      expect(service.nextLive('one', random: true)?.id, 'two');
    }
    expect(service.nextLive('one')?.id, 'two');
  });

  test('status refresh is single flight and skips fresh entries', () async {
    final service = AutoSwitchListService();
    final now = DateTime(2026, 1, 1, 12);
    service.items.value = [
      item('stale', 0),
      item('fresh', 2)..statusCheckedAt = now,
    ];
    var requestCount = 0;
    final first = service.refreshStatuses(
      now: now,
      resolver: (entry) async {
        requestCount++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return entry.id == 'stale'
            ? LiveStatusState.live
            : LiveStatusState.offline;
      },
    );
    final second = service.refreshStatuses(
      now: now,
      resolver: (_) async => LiveStatusState.offline,
    );
    expect(identical(first, second), isTrue);
    await first;

    expect(requestCount, 1);
    expect(service.items.first.liveStatus, 2);
    expect(service.items[1].liveStatus, 2);
  });
}
