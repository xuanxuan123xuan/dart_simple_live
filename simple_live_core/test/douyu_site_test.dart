import 'dart:async';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

const _roomId = '123456';
const _aliasRoomId = '654321';

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

Map<String, dynamic> _room({dynamic showStatus, dynamic videoLoop}) => {
      'room_id': int.parse(_roomId),
      'room_pic': 'https://example.com/cover.jpg',
      'room_biz_all': {'hot': '100'},
      'room_name': '标题',
      'owner_name': '主播',
      'owner_avatar': 'https://example.com/avatar.jpg',
      'show_details': '简介',
      if (showStatus != null) 'show_status': showStatus,
      if (videoLoop != null) 'videoLoop': videoLoop,
    };

class _DouyuRoomInterceptor extends Interceptor {
  dynamic roomResponse = {'room': _room(showStatus: 2, videoLoop: 0)};
  dynamic h5Response = {
    'data': {'show_time': '12:00'}
  };
  String signResponse = '{"data":{}}';
  bool failRoomRequest = false;
  final requestedUris = <Uri>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requestedUris.add(options.uri);
    if (options.uri.host == 'www.douyu.com' &&
        (options.uri.path == '/betard/$_roomId' ||
            options.uri.path == '/betard/$_aliasRoomId')) {
      if (failRoomRequest) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ));
      } else {
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: roomResponse,
        ));
      }
      return;
    }
    if (options.uri.host == 'www.douyu.com' &&
        options.uri.path == '/swf_api/h5room/$_roomId') {
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: h5Response,
      ));
      return;
    }
    if (options.uri.host == 'www.douyu.com' &&
        options.uri.path == '/swf_api/homeH5Enc' &&
        options.uri.queryParameters['rids'] == _roomId) {
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: signResponse,
      ));
      return;
    }
    handler.reject(DioException(
      requestOptions: options,
      type: DioExceptionType.unknown,
      error: StateError('Unexpected Douyu request: ${options.uri}'),
    ));
  }
}

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

  group('Douyu room status', () {
    late _DouyuRoomInterceptor interceptor;
    late DouyuSite site;

    setUp(() {
      interceptor = _DouyuRoomInterceptor();
      HttpClient.instance.dio.interceptors.add(interceptor);
      site = DouyuSite();
    });

    tearDown(() => HttpClient.instance.dio.interceptors.remove(interceptor));

    test('integer and numeric-string live flags share the same state parser',
        () async {
      for (final room in [
        _room(showStatus: 1, videoLoop: 0),
        _room(showStatus: '1', videoLoop: '0'),
      ]) {
        interceptor.roomResponse = {'room': room};

        expect(await site.getLiveStatusState(roomId: _roomId),
            LiveStatusState.live);
        expect(await site.getLiveStatus(roomId: _roomId), isTrue);
      }
    });

    test('detail and status agree for an explicitly offline room', () async {
      interceptor.roomResponse = {
        'room': _room(showStatus: '2', videoLoop: '0'),
      };

      final state = await site.getLiveStatusState(roomId: _roomId);
      final detail = await site.getRoomDetail(roomId: _roomId);

      expect(state, LiveStatusState.offline);
      expect(await site.getLiveStatus(roomId: _roomId), isFalse);
      expect(detail.liveStatusState, state);
      expect(detail.status, isFalse);
      expect(detail.isRecord, isFalse);
      expect(
        interceptor.requestedUris
            .any((uri) => uri.path == '/swf_api/homeH5Enc'),
        isFalse,
      );
    });

    test('recordings are playable live state but keep the legacy bool false',
        () async {
      interceptor.roomResponse = {
        'room': _room(showStatus: '2', videoLoop: '1'),
      };

      expect(
          await site.getLiveStatusState(roomId: _roomId), LiveStatusState.live);
      expect(await site.getLiveStatus(roomId: _roomId), isFalse);
    });

    test('missing or unknown flags stay unknown and bool status throws',
        () async {
      for (final room in [
        _room(),
        _room(showStatus: 2),
        _room(showStatus: 2, videoLoop: 7),
        _room(showStatus: 9, videoLoop: 0),
      ]) {
        interceptor.roomResponse = {'room': room};

        expect(await site.getLiveStatusState(roomId: _roomId),
            LiveStatusState.unknown);
        await expectLater(
          site.getLiveStatus(roomId: _roomId),
          throwsA(isA<CoreError>().having(
            (error) => error.kind,
            'kind',
            CoreErrorKind.response,
          )),
        );
      }
    });

    test('unknown state is carried by room detail rather than marked offline',
        () async {
      interceptor.roomResponse = {'room': _room(showStatus: 2)};

      final detail = await site.getRoomDetail(roomId: _roomId);

      expect(detail.liveStatusState, LiveStatusState.unknown);
      expect(detail.resolvedLiveStatus, LiveStatusState.unknown);
      expect(detail.status, isFalse);
      expect(
        interceptor.requestedUris
            .any((uri) => uri.path == '/swf_api/homeH5Enc'),
        isFalse,
      );
    });

    test('numeric alias resolves to the canonical room ID', () async {
      final state = await site.getLiveStatusState(roomId: _aliasRoomId);
      final detail = await site.getRoomDetail(roomId: _aliasRoomId);

      expect(state, LiveStatusState.offline);
      expect(detail.roomId, _roomId);
      expect(detail.danmakuData, _roomId);
      expect(detail.liveStatusState, state);
      expect(
        interceptor.requestedUris.map((uri) => uri.path),
        containsAll(['/betard/$_aliasRoomId', '/swf_api/h5room/$_roomId']),
      );
    });

    test('live alias requests the signer script with the canonical room ID',
        () async {
      interceptor.roomResponse = {
        'room': _room(showStatus: 1, videoLoop: 0),
      };

      await expectLater(
        site.getRoomDetail(roomId: _aliasRoomId),
        throwsA(isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.response,
        )),
      );
      expect(
        interceptor.requestedUris.last.path,
        '/swf_api/homeH5Enc',
      );
      expect(interceptor.requestedUris.last.queryParameters['rids'], _roomId);
    });

    test('malformed room payload and invalid IDs throw CoreError', () async {
      for (final response in <dynamic>[
        'not json',
        <String, dynamic>{},
        {'room': <dynamic>[]},
        {
          'room': _room(showStatus: 1, videoLoop: 0)..remove('room_id'),
        },
        for (final invalidId in [null, 0, '0', '', -2, 'abc'])
          {
            'room': _room(showStatus: 1, videoLoop: 0)..['room_id'] = invalidId,
          },
      ]) {
        interceptor.roomResponse = response;

        await expectLater(
          site.getLiveStatusState(roomId: _roomId),
          throwsA(isA<CoreError>().having(
            (error) => error.kind,
            'kind',
            CoreErrorKind.response,
          )),
        );
      }
    });

    test('malformed detail and signer responses stay CoreError', () async {
      interceptor.h5Response = {'data': []};
      await expectLater(
        site.getRoomDetail(roomId: _roomId),
        throwsA(isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.response,
        )),
      );

      interceptor.h5Response = {
        'data': {'show_time': '12:00'}
      };
      interceptor.roomResponse = {
        'room': _room(showStatus: 1, videoLoop: 0),
      };
      interceptor.signResponse = 'not json';
      await expectLater(
        site.getRoomDetail(roomId: _roomId),
        throwsA(isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.response,
        )),
      );
    });

    test('network failures stay CoreError instead of becoming offline',
        () async {
      interceptor.failRoomRequest = true;

      await expectLater(
        site.getLiveStatus(roomId: _roomId),
        throwsA(isA<CoreError>().having(
          (error) => error.kind,
          'kind',
          CoreErrorKind.network,
        )),
      );
    });
  });
}
