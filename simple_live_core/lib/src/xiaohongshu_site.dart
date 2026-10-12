import 'dart:convert';

import 'package:simple_live_core/src/common/core_cancellation.dart';
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';
import 'package:simple_live_core/src/model/live_contribution_rank.dart';
import 'package:simple_live_core/src/model/live_message.dart';
import 'xiaohongshu_danmaku.dart';

abstract interface class XiaohongshuRequestBridge {
  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    dynamic body,
  });
}

class XiaohongshuStreamVariant {
  XiaohongshuStreamVariant({
    required this.url,
    this.flvUrl,
    this.quality = '',
    this.codec = '',
    this.width,
    this.height,
    this.cdn = '',
  });

  final String url;
  final String? flvUrl;
  final String quality;
  final String codec;
  final int? width;
  final int? height;
  final String cdn;
}

class XiaohongshuRoomSnapshot {
  XiaohongshuRoomSnapshot({
    required this.roomId,
    required this.title,
    required this.cover,
    required this.userName,
    required this.userAvatar,
    required this.online,
    required this.live,
    required this.liveStatus,
    required this.roomStatus,
    required this.streams,
    required this.url,
  });

  final String roomId;
  final String title;
  final String cover;
  final String userName;
  final String userAvatar;
  final int online;
  final bool live;
  final String liveStatus;
  final int roomStatus;
  final List<XiaohongshuStreamVariant> streams;
  final String url;

  LiveStatusState get liveStatusState {
    if (live) return LiveStatusState.live;
    if (liveStatus == 'end' || roomStatus == 0) return LiveStatusState.offline;
    return LiveStatusState.unknown;
  }
}

class XiaohongshuSite implements LiveSite {
  XiaohongshuSite({this.requestBridge});

  static const String webBaseUrl = 'https://www.xiaohongshu.com';
  static const String liveRoomBaseUrl = 'https://live-room.xiaohongshu.com';
  static const String defaultUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  static const String defaultReferer = '$webBaseUrl/';
  static const String interactionPath =
      '/api/sns/red/live/h5/v1/interaction/get_simple_interaction';
  static const String roomInfoPath =
      '/api/sns/red/live/h5/v1/room/current_room_info';
  static const String statusPath =
      '/api/sns/red/live/h5/v1/core/current_live_status';

  XiaohongshuRequestBridge? requestBridge;
  String cookie = '';

  @override
  String id = 'xiaohongshu';

  @override
  String name = '小红书直播';

  @override
  LiveDanmaku getDanmaku() => XiaohongshuDanmaku();

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    final normalized = normalizeRoomId(roomId);
    if (normalized == null) {
      throw CoreError('小红书直播间号无效', kind: CoreErrorKind.response);
    }
    try {
      final html = await HttpClient.instance.getText(
        '$webBaseUrl/livestream/$normalized',
        header: _headers(),
      );
      return _toDetail(parseRoomSnapshot(html, roomId: normalized));
    } catch (error) {
      if (requestBridge == null) rethrow;
      final response = await requestBridge!.request(
        method: 'GET',
        path: roomInfoPath,
        query: {'roomId': normalized},
      );
      return _toDetail(parseRoomSnapshotFromMap(response, roomId: normalized));
    }
  }

  @override
  Future<LiveStatusState> getLiveStatusState({required String roomId}) async {
    try {
      return (await getRoomDetail(roomId: roomId)).resolvedLiveStatus;
    } catch (_) {
      return LiveStatusState.unknown;
    }
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getLiveStatusState(roomId: roomId)) == LiveStatusState.live;

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    final snapshot = detail.data as XiaohongshuRoomSnapshot;
    final grouped = <String, List<XiaohongshuStreamVariant>>{};
    for (final stream in snapshot.streams) {
      final quality = stream.quality.isEmpty ? '原画' : stream.quality;
      grouped.putIfAbsent(quality, () => []).add(stream);
    }
    final names = grouped.keys.toList()
      ..sort((a, b) => _qualityRank(a).compareTo(_qualityRank(b)));
    return [
      for (var index = 0; index < names.length; index++)
        LivePlayQuality(
            quality: names[index], data: grouped[names[index]], sort: index),
    ];
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final variants = quality.data is List
        ? quality.data.whereType<XiaohongshuStreamVariant>().toList()
        : <XiaohongshuStreamVariant>[];
    final urls = <String>[];
    for (final variant in variants) {
      if (variant.url.isNotEmpty) urls.add(variant.url);
      if (variant.flvUrl?.isNotEmpty ?? false) urls.add(variant.flvUrl!);
    }
    return LivePlayUrl(urls: urls, headers: _headers());
  }

  @override
  Future<List<LiveCategory>> getCategores() async => const [];

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async =>
      LiveCategoryResult(hasMore: false, items: []);

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async =>
      LiveCategoryResult(hasMore: false, items: []);

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async =>
      LiveSearchRoomResult(
        items: [],
        metadata: const LiveSearchMetadata(
          continuation: SearchContinuation.unknown,
          origin: SearchOrigin.fallback,
        ),
      );

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async =>
      LiveSearchAnchorResult(
        items: [],
        metadata: const LiveSearchMetadata(
          continuation: SearchContinuation.unknown,
          origin: SearchOrigin.fallback,
        ),
      );

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
    LiveRoomDetail? detail,
  }) async =>
      [];

  @override
  Future<List<LiveContributionRankItem>> getContributionRank({
    required String roomId,
    LiveRoomDetail? detail,
  }) async =>
      [];

  Future<XiaohongshuInteractionPage> getInteractionPage(
    String roomId,
    int startTimestamp,
  ) async {
    final bridge = requestBridge;
    if (bridge == null) {
      throw CoreError(
        '小红书评论需要网页签名会话',
        statusCode: 406,
        kind: CoreErrorKind.http,
      );
    }
    final response = await bridge.request(
      method: 'GET',
      path: interactionPath,
      query: {
        'roomId': roomId,
        'startTimestamp': startTimestamp,
        'size': 10,
        'needPraise': true,
        'needViewer': true,
      },
    );
    return XiaohongshuInteractionPage.fromResponse(response);
  }

  Map<String, String> _headers() => {
        'Referer': defaultReferer,
        'User-Agent': defaultUserAgent,
        if (cookie.trim().isNotEmpty) 'Cookie': normalizeCookie(cookie),
      };

  LiveRoomDetail _toDetail(XiaohongshuRoomSnapshot snapshot) => LiveRoomDetail(
        roomId: snapshot.roomId,
        title: snapshot.title,
        cover: snapshot.cover,
        userName: snapshot.userName,
        userAvatar: snapshot.userAvatar,
        online: snapshot.online,
        status: snapshot.live,
        liveStatusState: snapshot.liveStatusState,
        data: snapshot,
        danmakuData: XiaohongshuDanmakuArgs(
          roomId: snapshot.roomId,
          fetchPage: (cursor) => getInteractionPage(snapshot.roomId, cursor),
        ),
        url: snapshot.url,
      );

  static String normalizeCookie(String input) => input
      .split(';')
      .map((item) => item.trim())
      .where((item) => item.contains('=') && item.split('=').first.isNotEmpty)
      .join('; ');

  static String? normalizeRoomId(String value) {
    final id = value.trim();
    return RegExp(r'^\d{8,32}$').hasMatch(id) ? id : null;
  }

  static XiaohongshuRoomSnapshot parseRoomSnapshot(
    String html, {
    required String roomId,
  }) {
    final state = _extractInitialState(html);
    if (state == null) {
      throw CoreError('小红书直播页缺少房间数据', kind: CoreErrorKind.response);
    }
    return parseRoomSnapshotFromMap(state, roomId: roomId);
  }

  static XiaohongshuRoomSnapshot parseRoomSnapshotFromMap(
    dynamic source, {
    required String roomId,
  }) {
    final root = source is Map ? source : const <dynamic, dynamic>{};
    final liveStream = _findMap(root, 'liveStream') ?? root;
    final roomData = _asMap(liveStream['roomData']) ?? liveStream;
    final roomInfo = _asMap(roomData['roomInfo']) ??
        _asMap(_findMap(root, 'roomInfo')) ??
        const <dynamic, dynamic>{};
    final host = _asMap(roomData['hostInfo']) ??
        _asMap(roomInfo['hostInfo']) ??
        _asMap(_findMap(root, 'hostInfo')) ??
        const <dynamic, dynamic>{};
    final statusText = (roomData['liveStatus'] ??
                roomInfo['liveStatus'] ??
                _findValue(root, 'liveStatus'))
            ?.toString()
            .toLowerCase() ??
        '';
    final roomStatus = _int(roomInfo['status'] ?? roomData['status']);
    final streams = _parseStreams(roomData['pullConfig'] ??
        roomInfo['pullConfig'] ??
        _findValue(root, 'pullConfig'));
    return XiaohongshuRoomSnapshot(
      roomId: roomId,
      title: _text(
          roomInfo['title'] ?? roomData['title'] ?? _findValue(root, 'title')),
      cover: _text(roomInfo['cover'] ?? roomInfo['roomCover'] ?? host['cover']),
      userName: _text(host['nickname'] ?? host['nickName'] ?? host['name']),
      userAvatar: _text(host['avatar'] ?? host['avatarUrl'] ?? host['image']),
      online: _int(roomInfo['displayViewerCount'] ??
          roomData['displayViewerCount'] ??
          _findValue(root, 'displayViewerCount')),
      live: statusText == 'success' && roomStatus == 2,
      liveStatus: statusText,
      roomStatus: roomStatus,
      streams: streams,
      url: '$webBaseUrl/livestream/$roomId',
    );
  }

  static List<XiaohongshuStreamVariant> _parseStreams(dynamic value) {
    final result = <XiaohongshuStreamVariant>[];
    void visit(dynamic node, {String quality = '', String codec = ''}) {
      if (node is List) {
        for (final item in node) {
          visit(item, quality: quality, codec: codec);
        }
        return;
      }
      if (node is! Map) return;
      final rawQuality =
          _text(node['quality'] ?? node['qualityName'] ?? node['name']);
      final rawCodec = _text(node['codec'] ?? node['videoCodec']);
      final nextQuality = rawQuality.isEmpty ? quality : rawQuality;
      final nextCodec = rawCodec.isEmpty ? codec : rawCodec;
      final hls = _text(node['hlsUrl'] ?? node['hls'] ?? node['url']);
      final flv = _text(node['flvUrl'] ?? node['flv']);
      if (hls.isNotEmpty || flv.isNotEmpty) {
        final url = hls.isNotEmpty ? hls : flv;
        final lower = '$nextCodec $url'.toLowerCase();
        if (!lower.contains('265') && !lower.contains('hevc')) {
          result.add(XiaohongshuStreamVariant(
            url: url,
            flvUrl: flv.isEmpty ? null : flv,
            quality: _qualityName(nextQuality),
            codec: nextCodec,
            width: _nullableInt(node['width']),
            height: _nullableInt(node['height']),
            cdn: _text(node['cdn'] ?? node['cdnName']),
          ));
        }
      }
      for (final entry in node.entries) {
        if (entry.value is Map || entry.value is List) {
          visit(entry.value, quality: nextQuality, codec: nextCodec);
        }
      }
    }

    visit(value);
    final unique = <String, XiaohongshuStreamVariant>{};
    for (final item in result) {
      unique['${item.url}|${item.flvUrl}'] = item;
    }
    return unique.values.toList();
  }

  static String _qualityName(String value) {
    final text = value.trim().toUpperCase();
    if (text.contains('HD') || text.contains('高清')) return 'HD';
    if (text.contains('SD') || text.contains('标清')) return 'SD';
    if (text.contains('LD') || text.contains('流畅')) return 'LD';
    if (text.contains('ORIGINAL') || text.contains('原画')) return '原画';
    return value.trim();
  }

  static int _qualityRank(String value) {
    switch (value.toUpperCase()) {
      case '原画':
        return 0;
      case 'HD':
        return 1;
      case 'SD':
        return 2;
      case 'LD':
        return 3;
      default:
        return 4;
    }
  }

  static Map<dynamic, dynamic>? _extractInitialState(String html) {
    const marker = 'window.__INITIAL_STATE__=';
    final start = html.indexOf(marker);
    if (start < 0) return null;
    final jsonStart = html.indexOf('{', start + marker.length);
    if (jsonStart < 0) return null;
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var i = jsonStart; i < html.length; i++) {
      final char = html[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
        continue;
      }
      if (char == '"') {
        quoted = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}' && --depth == 0) {
        try {
          final decoded = json.decode(html.substring(jsonStart, i + 1));
          return decoded is Map ? decoded : null;
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  static Map<dynamic, dynamic>? _asMap(dynamic value) =>
      value is Map ? value : null;

  static Map<dynamic, dynamic>? _findMap(dynamic value, String key) {
    if (value is Map) {
      final direct = value[key];
      if (direct is Map) return direct;
      for (final child in value.values) {
        final found = _findMap(child, key);
        if (found != null) return found;
      }
    } else if (value is Iterable) {
      for (final child in value) {
        final found = _findMap(child, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  static dynamic _findValue(dynamic value, String key) {
    if (value is Map) {
      if (value.containsKey(key)) return value[key];
      for (final child in value.values) {
        final found = _findValue(child, key);
        if (found != null) return found;
      }
    } else if (value is Iterable) {
      for (final child in value) {
        final found = _findValue(child, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    final text = _text(value).replaceAll(',', '');
    final direct = int.tryParse(text);
    if (direct != null) return direct;
    final match = RegExp(r'^(\d+(?:\.\d+)?)(万|w)?$', caseSensitive: false)
        .firstMatch(text);
    if (match == null) return 0;
    final number = double.tryParse(match.group(1)!);
    if (number == null) return 0;
    return (number * (match.group(2) == null ? 1 : 10000)).round();
  }

  static int? _nullableInt(dynamic value) {
    final result = _int(value);
    return result == 0 && _text(value) != '0' ? null : result;
  }
}
