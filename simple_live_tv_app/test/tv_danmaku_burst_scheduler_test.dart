import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/live_room/player/tv_danmaku_burst_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DanmakuContentItem item(String value) => DanmakuContentItem(value);

  testWidgets('smooth mode delays startup and limits each frame',
      (tester) async {
    final batches = <List<DanmakuContentItem>>[];
    final scheduler = TvDanmakuBurstScheduler(
      onBatch: batches.add,
      realtime: false,
    )..beginGeneration(1);
    addTearDown(scheduler.dispose);

    for (var i = 0; i < 10; i++) {
      scheduler.add(item('$i'), generation: 1);
    }
    await tester.pump(const Duration(milliseconds: 99));
    expect(batches, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(batches.single, hasLength(4));
    expect(scheduler.pendingCount, 6);

    await tester.pump();
    expect(batches, hasLength(2));
    expect(batches[1], hasLength(4));
    await tester.pump();
    expect(batches, hasLength(3));
    expect(batches[2], hasLength(2));
    expect(scheduler.pendingCount, 0);
  });

  testWidgets('smooth mode keeps the newest messages within its bound',
      (tester) async {
    final batches = <List<DanmakuContentItem>>[];
    final scheduler = TvDanmakuBurstScheduler(
      onBatch: batches.add,
      realtime: false,
      maxItemsPerFrame: 120,
    )..beginGeneration(2);
    addTearDown(scheduler.dispose);

    for (var i = 0; i < 130; i++) {
      scheduler.add(item('$i'), generation: 2);
    }
    expect(scheduler.pendingCount, 120);
    await tester.pump(const Duration(milliseconds: 100));
    expect(batches.first.first.text, '10');
  });

  testWidgets('stale generations are ignored and realtime drains pending',
      (tester) async {
    final batches = <List<DanmakuContentItem>>[];
    final scheduler = TvDanmakuBurstScheduler(
      onBatch: batches.add,
      realtime: false,
    )..beginGeneration(3);
    addTearDown(scheduler.dispose);

    scheduler.add(item('stale'), generation: 2);
    expect(scheduler.pendingCount, 0);
    scheduler.add(item('queued'), generation: 3);
    scheduler.realtime = true;
    expect(scheduler.pendingCount, 0);
    expect(batches.single.map((value) => value.text), ['queued']);
    await tester.pump(const Duration(milliseconds: 100));
    expect(batches, hasLength(1));
  });
}
