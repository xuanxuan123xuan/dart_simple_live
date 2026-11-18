import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_core/simple_live_core.dart';

import 'site_registry.dart';

const _channelName = 'simple_live/tvos_core';

/// Entry point used by the native tvOS host's headless FlutterEngine.
///
/// The native host owns UI and playback. This isolate only exposes the
/// repository's existing platform adapters through a small JSON-compatible
/// request/response protocol.
@pragma('vm:entry-point')
void tvosCoreEntrypoint() {
  WidgetsFlutterBinding.ensureInitialized();
  final channel = MethodChannel(_channelName);
  final events = BasicMessageChannel<Object?>(
    'simple_live/tvos_danmaku_events',
    StandardMessageCodec(),
  );
  final service = _TvosCoreRpcService(events);
  channel.setMethodCallHandler(service.handle);
}

class _TvosCoreRpcService {
  _TvosCoreRpcService(this._events);

  final BasicMessageChannel<Object?> _events;
  final Map<String, LiveDanmaku> _danmaku = <String, LiveDanmaku>{};

  Future<Map<String, dynamic>> handle(MethodCall call) async {
    if (call.method != 'request' || call.arguments is! Map) {
      throw PlatformException(
        code: 'unsupported',
        message: 'Unsupported tvOS core method',
      );
    }

    final request = Map<String, dynamic>.from(call.arguments as Map);
    final requestId = request['requestId']?.toString() ?? '';
    final method = request['method']?.toString() ?? '';
    final payload = request['payload'] is Map
        ? Map<String, dynamic>.from(request['payload'] as Map)
        : <String, dynamic>{};

    try {
      final data = await _dispatch(method, payload);
      return {'requestId': requestId, 'ok': true, 'data': data};
    } on CoreError catch (error) {
      return {
        'requestId': requestId,
        'ok': false,
        'error': {
          'kind': error.kind.name,
          'message': error.message,
          if (error.statusCode > 0) 'statusCode': error.statusCode,
        },
      };
    } catch (error) {
      return {
        'requestId': requestId,
        'ok': false,
        'error': {'kind': 'unknown', 'message': error.toString()},
      };
    }
  }

  Future<Object?> _dispatch(String method, Map<String, dynamic> payload) async {
    switch (method) {
      case 'site.providers':
        return [
          for (final provider in LiveProvider.values)
            {
              'id': provider.name,
              'title': provider.title,
              'support': provider.tvosSupport.name,
              'supportLabel': provider.tvosSupportLabel,
              'caveat': provider.caveat,
            },
        ];
      case 'site.recommend':
        final provider = _provider(payload);
        final page = _page(payload);
        final result = await SiteRegistry.instance
            .get(provider)
            .getRecommendRooms(page: page);
        return _roomList(result.items, hasMore: result.hasMore, page: page);
      case 'site.search':
        final provider = _provider(payload);
        final page = _page(payload);
        final result = await SiteRegistry.instance.get(provider).searchRooms(
              payload['keyword']?.toString() ?? '',
              page: page,
            );
        return _roomList(result.items, hasMore: result.hasMore, page: page);
      case 'site.categories':
        final provider = _provider(payload);
        final categories =
            await SiteRegistry.instance.get(provider).getCategores();
        return categories.map((category) => category.toJson()).toList();
      case 'site.categoryRooms':
        final provider = _provider(payload);
        final category = LiveSubCategory.fromJson({
          'id': payload['categoryId']?.toString() ?? '',
          'name': payload['categoryName']?.toString() ?? '',
          'parentId': payload['parentId']?.toString() ?? '',
          'children': const [],
        });
        final page = _page(payload);
        final result = await SiteRegistry.instance
            .get(provider)
            .getCategoryRooms(category, page: page);
        return _roomList(result.items, hasMore: result.hasMore, page: page);
      case 'room.detail':
        final provider = _provider(payload);
        final detail = await SiteRegistry.instance
            .get(provider)
            .getRoomDetail(roomId: payload['roomId']?.toString() ?? '');
        return _detail(detail);
      case 'room.qualities':
        final provider = _provider(payload);
        final detail = await SiteRegistry.instance
            .get(provider)
            .getRoomDetail(roomId: payload['roomId']?.toString() ?? '');
        final qualities = await SiteRegistry.instance
            .get(provider)
            .getPlayQualites(detail: detail);
        return qualities.map(_quality).toList();
      case 'room.playUrls':
        final provider = _provider(payload);
        final site = SiteRegistry.instance.get(provider);
        final detail = await site.getRoomDetail(
          roomId: payload['roomId']?.toString() ?? '',
        );
        final qualities = await site.getPlayQualites(detail: detail);
        if (qualities.isEmpty) {
          throw CoreError('直播间没有返回任何清晰度');
        }
        final qualityName = payload['quality']?.toString();
        final quality = qualities.firstWhere(
          (item) => item.quality == qualityName,
          orElse: () => qualities.first,
        );
        final result = await site.getPlayUrls(detail: detail, quality: quality);
        return {
          'urls': result.urls,
          'headers': result.headers ?? const <String, String>{},
          'protocols': result.urls
              .map(classifyLiveStreamProtocol)
              .map((item) => item.name)
              .toList(),
          'quality': result.actualQuality?.quality ?? quality.quality,
        };
      case 'session.setCookie':
        SiteRegistry.instance.setSessionCookie(
          _provider(payload),
          payload['cookie']?.toString() ?? '',
        );
        return const <String, dynamic>{};
      case 'session.clearCookie':
        SiteRegistry.instance.setSessionCookie(_provider(payload), '');
        return const <String, dynamic>{};
      case 'danmaku.start':
        await _startDanmaku(payload);
        return const <String, dynamic>{};
      case 'danmaku.stop':
        await _stopDanmaku(payload);
        return const <String, dynamic>{};
      default:
        throw CoreError('Unsupported tvOS core request: $method');
    }
  }

  Future<void> _startDanmaku(Map<String, dynamic> payload) async {
    final provider = _provider(payload);
    final roomId = payload['roomId']?.toString() ?? '';
    final site = SiteRegistry.instance.get(provider);
    final detail = await site.getRoomDetail(roomId: roomId);
    final args = detail.danmakuData;
    if (args == null) throw CoreError('此房间没有可用弹幕连接参数');
    await _stopDanmaku(payload);
    final danmaku = site.getDanmaku();
    final key = '${provider.name}:$roomId';
    _danmaku[key] = danmaku;
    danmaku.onReady = () => _sendEvent({'kind': 'ready', 'key': key});
    danmaku.onClose = (reason) => _sendEvent({
          'kind': 'close',
          'key': key,
          'reason': reason,
        });
    danmaku.onMessage = (message) {
      if (message.type != LiveMessageType.chat || message.message.isEmpty) {
        return;
      }
      unawaited(_sendEvent({
        'kind': 'message',
        'key': key,
        'userName': message.userName,
        'message': message.message,
        'color': {
          'r': message.color.r,
          'g': message.color.g,
          'b': message.color.b,
        },
        'imageUrls': message.imageUrls ?? const <String>[],
        'spans': [
          for (final span in message.spans ?? const <LiveMessageSpan>[])
            span.toJson(),
        ],
      }));
    };
    try {
      await danmaku.start(args);
    } catch (_) {
      _sendEvent({'kind': 'error', 'key': key, 'message': '弹幕连接失败'});
      rethrow;
    }
  }

  Future<void> _stopDanmaku(Map<String, dynamic> payload) async {
    final provider = _provider(payload);
    final roomId = payload['roomId']?.toString() ?? '';
    final key = '${provider.name}:$roomId';
    final old = _danmaku.remove(key);
    if (old == null) return;
    old.onMessage = null;
    old.onReady = null;
    old.onClose = null;
    await old.stop();
  }

  Future<void> _sendEvent(Map<String, dynamic> event) async {
    await _events.send(event);
  }

  LiveProvider _provider(Map<String, dynamic> payload) {
    final name = payload['provider']?.toString();
    return LiveProvider.values.firstWhere(
      (provider) => provider.name == name,
      orElse: () => throw CoreError('Unknown live provider: $name'),
    );
  }

  int _page(Map<String, dynamic> payload) =>
      int.tryParse('${payload['page'] ?? 1}')?.clamp(1, 999999) ?? 1;

  Map<String, dynamic> _roomList(
    List<LiveRoomItem> items, {
    required bool hasMore,
    required int page,
  }) =>
      {
        'page': page,
        'hasMore': hasMore,
        'items': items.map(_room).toList(),
      };

  Map<String, dynamic> _room(LiveRoomItem item) => {
        'roomId': item.roomId,
        'title': item.title,
        'cover': item.cover,
        'userName': item.userName,
        'online': item.online,
      };

  Map<String, dynamic> _detail(LiveRoomDetail detail) => {
        'roomId': detail.roomId,
        'title': detail.title,
        'cover': detail.cover,
        'userName': detail.userName,
        'userAvatar': detail.userAvatar,
        'online': detail.online,
        'status': detail.resolvedLiveStatus.name,
        'introduction': detail.introduction,
        'notice': detail.notice,
        'categoryId': detail.categoryId,
        'categoryName': detail.categoryName,
        'categoryParentId': detail.categoryParentId,
        'categoryParentName': detail.categoryParentName,
      };

  Map<String, dynamic> _quality(LivePlayQuality quality) => {
        'quality': quality.quality,
        'sort': quality.sort,
      };
}
