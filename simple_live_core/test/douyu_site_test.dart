import 'dart:async';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

class _StubDouyuSite extends DouyuSite {
  final Map<String, Future<String> Function()> responses;
  int inFlight = 0;
  int maxInFlight = 0;

  _StubDouyuSite(this.responses);

  @override
  Future<String> getPlayUrl(
    String roomId,
    String args,
    int rate,
    String cdn,
  ) async {
    inFlight += 1;
    maxInFlight = maxInFlight < inFlight ? inFlight : maxInFlight;
    try {
      return await responses[cdn]!();
    } finally {
      inFlight -= 1;
    }
  }
}

LiveRoomDetail _detail() => LiveRoomDetail(
      roomId: '1',
      title: '',
      cover: '',
      userName: '',
      userAvatar: '',
      online: 0,
      status: true,
      url: '',
    );

void main() {
  test('concurrently fetches CDN URLs, preserving order and tolerating errors',
      () async {
    final site = _StubDouyuSite({
      'first': () async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return 'first-url';
      },
      'failed': () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        throw StateError('unavailable');
      },
      'third': () async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'third-url';
      },
    });
    final quality = LivePlayQuality(
      quality: 'test',
      data: DouyuPlayData(0, ['first', 'failed', 'third']),
    );

    final result = await site.getPlayUrls(detail: _detail(), quality: quality);

    expect(site.maxInFlight, greaterThan(1));
    expect(result.urls, ['first-url', 'third-url']);
  });

  test('rethrows the first error when every CDN request fails', () async {
    final site = _StubDouyuSite({
      'first': () async => throw StateError('first failure'),
      'second': () async => throw ArgumentError('second failure'),
    });
    final quality = LivePlayQuality(
      quality: 'test',
      data: DouyuPlayData(0, ['first', 'second']),
    );

    await expectLater(
      site.getPlayUrls(detail: _detail(), quality: quality),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'first failure',
        ),
      ),
    );
  });
}
