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
import 'xiaohongshu_discovery_client.dart';

abstract interface class XiaohongshuSessionLifecycle {
  Future<void> releaseRoom(String roomId);
}

abstract interface class XiaohongshuRequestBridge {
  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    dynamic body,
  });
}

abstract interface class XiaohongshuHostRequestBridge {
  Future<dynamic> requestHost({
    required String hostId,
    required String roomId,
  });
}

/// A local WebView prerequisite failure with a safe, app-authored message.
class XiaohongshuWebSessionUnavailableError extends CoreError {
  XiaohongshuWebSessionUnavailableError.linuxRuntime()
      : super(
          '未检测到可用的 Linux WebKitGTK 运行库，请安装后重试',
          kind: CoreErrorKind.response,
        );

  XiaohongshuWebSessionUnavailableError.webView2Runtime()
      : super(
          '未检测到 Microsoft Edge WebView2 Runtime，请安装后重试',
          kind: CoreErrorKind.response,
        );
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
    this.hostId,
    this.statusMessage,
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
  final String? hostId;
  final String? statusMessage;

  LiveStatusState get liveStatusState {
    if (live) return LiveStatusState.live;
    if (liveStatus == 'end' || (liveStatus == 'success' && roomStatus == 0)) {
      return LiveStatusState.offline;
    }
    return LiveStatusState.unknown;
  }
}

class XiaohongshuSite implements LiveSite {
  XiaohongshuSite({this.requestBridge});

  static const String webBaseUrl = 'https://www.xiaohongshu.com';
  static const String edithBaseUrl = 'https://edith.xiaohongshu.com';
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
  static const String hostProfilePath = '/api/sns/web/v1/user/hover_card';

  static const aggregatePath =
      '/api/sns/red/live/h5/v1/room/aggregate_business_info';
  static const stopInfoPath = '/api/sns/red/live/h5/v1/room/stop_info_2c';

  XiaohongshuRequestBridge? requestBridge;
  final discovery = XiaohongshuDiscoveryClient();
  bool _requiresSignature = false;
  String cookie = '';

  @override
  String id = 'xiaohongshu';

  @override
  String name = '小红书直播';

  @override
  LiveDanmaku getDanmaku() => XiaohongshuDanmaku();

  @override
  Future<LiveRoomDetail> getRoomDetail({
    required String roomId,
    String? hostId,
  }) async {
    final normalized = normalizeRoomId(roomId);
    if (normalized == null) {
      throw CoreError('小红书直播间号无效', kind: CoreErrorKind.response);
    }

    final suppliedHostId = _normalizeHostId(hostId);
    final hasHostHint = hostId?.trim().isNotEmpty ?? false;
    if (hasHostHint && suppliedHostId == null) {
      return _toDetail(_unknownSnapshot(
        roomId: normalized,
        statusMessage: '主播标识无效，无法确认当前直播状态',
      ));
    }

    late final XiaohongshuRoomSnapshot requestedRoom;
    try {
      requestedRoom = await _loadRoomSnapshot(normalized);
    } catch (error) {
      if (error is CoreCancelledError) rethrow;
      if (suppliedHostId == null) rethrow;
      final empty = _unknownSnapshot(
        roomId: normalized,
        hostId: suppliedHostId,
        statusMessage: '原直播间信息暂不可用，无法确认主播当前状态',
      );
      return _toDetail(await _resolveCurrentHostRoom(empty, suppliedHostId));
    }

    if (suppliedHostId != null &&
        requestedRoom.hostId != null &&
        requestedRoom.hostId != suppliedHostId) {
      return _toDetail(_unknownSnapshot(
        source: requestedRoom,
        hostId: suppliedHostId,
        statusMessage: '直播链接与主播标识不匹配，无法确认当前直播场次',
      ));
    }

    if (requestedRoom.live) {
      if (suppliedHostId == null) return _toDetail(requestedRoom);
      if (requestedRoom.hostId == suppliedHostId) {
        return _toDetail(requestedRoom);
      }
    }

    final targetHostId = suppliedHostId ?? requestedRoom.hostId;
    if (targetHostId == null) {
      return _toDetail(_unknownSnapshot(
        source: requestedRoom,
        statusMessage: '旧场次已结束，无法确认主播当前状态，请重新导入直播链接',
      ));
    }
    return _toDetail(
        await _resolveCurrentHostRoom(requestedRoom, targetHostId));
  }

  @override
  Future<LiveStatusState> getLiveStatusState({
    required String roomId,
    String? hostId,
  }) async {
    try {
      final detail = await getRoomDetail(roomId: roomId, hostId: hostId);
      return detail.resolvedLiveStatus;
    } catch (_) {
      return LiveStatusState.unknown;
    }
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getLiveStatusState(roomId: roomId)) == LiveStatusState.live;

  static double? resolveStreamAspectRatio(dynamic data) {
    if (data is! XiaohongshuRoomSnapshot) return null;
    for (final stream in data.streams) {
      final width = stream.width ?? 0;
      final height = stream.height ?? 0;
      if (width > 0 && height > 0) return width / height;
    }
    return null;
  }

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
    return LivePlayUrl(
        urls: urls.toSet().toList(),
        headers: {..._headers(), 'Referer': detail.url});
  }

  @override
  Future<List<LiveCategory>> getCategores() => discovery.getCategories();

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async =>
      discovery.getRooms();

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async =>
      discovery.getRooms();

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async =>
      discovery.searchRooms();

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
    CoreCancellation? cancellation,
  }) async =>
      discovery.searchAnchors();

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
    final response = await _requestH5(interactionPath, {
      'roomId': roomId,
      'startTimestamp': startTimestamp,
      'size': 10,
      'needPraise': true,
      'needViewer': true,
    });
    return XiaohongshuInteractionPage.fromResponse(response);
  }

  Future<dynamic> _requestH5(String path, Map<String, dynamic> query) async {
    if (!_requiresSignature) {
      try {
        final response = await HttpClient.instance.getJson(
            '$liveRoomBaseUrl$path',
            queryParameters: query,
            header: _headers(),
            redactResponse: true);
        _responseData(response);
        return response;
      } catch (error) {
        if (error is CoreCancelledError) rethrow;
        if (requestBridge == null) rethrow;
        if (error is CoreError &&
            (error.statusCode == 403 || error.statusCode == 406)) {
          _requiresSignature = true;
        }
      }
    }
    final bridge = requestBridge;
    if (bridge == null) {
      throw CoreError('小红书请求需要网页签名会话',
          statusCode: 406, kind: CoreErrorKind.http);
    }
    final response =
        await bridge.request(method: 'GET', path: path, query: query);
    _responseData(response);
    return response;
  }

  static Map<dynamic, dynamic> _responseData(dynamic response) {
    if (response is! Map || response['success'] == false) {
      throw CoreError('小红书接口响应不可用', kind: CoreErrorKind.response);
    }
    return response['data'] is Map ? response['data'] as Map : response;
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
          onStop: () async {
            final bridge = requestBridge;
            if (bridge is XiaohongshuSessionLifecycle) {
              await (bridge as XiaohongshuSessionLifecycle)
                  .releaseRoom(snapshot.roomId);
            }
          },
        ),
        url: snapshot.url,
      );

  static String normalizeCookie(String input) {
    final value = input
        .replaceFirst(RegExp(r'^\s*cookie\s*:', caseSensitive: false), '')
        .trim();
    if (value.contains('\r') || value.contains('\n')) return '';
    final values = <String, String>{};
    for (final part in value.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name)) continue;
      values[name] = part.substring(separator + 1).trim();
    }
    return values.entries.map((item) => '${item.key}=${item.value}').join('; ');
  }

  static String? normalizeRoomId(String value) {
    final id = value.trim();
    return RegExp(r'^\d{8,32}$').hasMatch(id) ? id : null;
  }

  static String? _normalizeHostId(String? value) {
    final id = value?.trim().toLowerCase() ?? '';
    return RegExp(r'^[a-f0-9]{24}$').hasMatch(id) ? id : null;
  }

  Future<XiaohongshuRoomSnapshot> _loadRoomSnapshot(String roomId) async {
    try {
      final html = await HttpClient.instance.getText(
        '$webBaseUrl/livestream/$roomId',
        header: {..._headers(), 'xy-common-params': 'platform=iOS'},
        redactResponse: true,
      );
      return parseRoomSnapshot(html, roomId: roomId);
    } catch (error) {
      if (error is CoreCancelledError) rethrow;
      if (requestBridge == null) rethrow;
      final response = await _requestH5(roomInfoPath, {'roomId': roomId});
      final data = Map<String, dynamic>.from(_responseData(response));
      try {
        final status =
            _responseData(await _requestH5(statusPath, {'roomId': roomId}));
        if (status['status'] != null) {
          final value = int.tryParse('${status['status']}');
          data['liveStatus'] = value == 2
              ? 'success'
              : (value == 0 || value == 1 || value == 3 ? 'end' : 'unknown');
        }
      } catch (error) {
        if (error is CoreCancelledError) rethrow;
        // Metadata and playback remain available when status cannot be signed.
      }
      return parseRoomSnapshotFromMap(data, roomId: roomId);
    }
  }

  Future<XiaohongshuRoomSnapshot> _resolveCurrentHostRoom(
    XiaohongshuRoomSnapshot requestedRoom,
    String targetHostId,
  ) async {
    late final dynamic profile;
    try {
      profile = await _requestHostProfile(
        hostId: targetHostId,
        roomId: requestedRoom.roomId,
      );
    } on XiaohongshuWebSessionUnavailableError catch (error) {
      return _unknownSnapshot(
        source: requestedRoom,
        hostId: targetHostId,
        statusMessage: error.message,
      );
    }
    if (profile == null) {
      return _unknownSnapshot(
        source: requestedRoom,
        hostId: targetHostId,
        statusMessage: '无法确认主播当前状态，请检查小红书登录会话或稍后重试',
      );
    }

    final profileIdentity = _profileIdentity(profile);
    if (profileIdentity != null && profileIdentity != targetHostId) {
      return _unknownSnapshot(
        source: requestedRoom,
        hostId: targetHostId,
        statusMessage: '主播信息与直播链接不匹配，无法确认当前直播场次',
      );
    }

    final live = _profileLiveStatus(profile);
    if (live == false) {
      if (requestedRoom.live) {
        return _unknownSnapshot(
          source: requestedRoom,
          hostId: targetHostId,
          statusMessage: '直播间与主播当前状态不一致，无法确认直播场次',
        );
      }
      return _offlineSnapshot(
        requestedRoom,
        hostId: targetHostId,
        statusMessage: '主播当前未开播',
      );
    }
    if (live != true) {
      return _unknownSnapshot(
        source: requestedRoom,
        hostId: targetHostId,
        statusMessage: '主播直播状态暂不可确认，请稍后重试',
      );
    }

    final currentRoomId = normalizeRoomId(_profileRoomId(profile) ?? '');
    if (currentRoomId == null) {
      return _unknownSnapshot(
        source: requestedRoom,
        hostId: targetHostId,
        statusMessage: '主播正在直播，但无法确认当前直播间',
      );
    }

    late final XiaohongshuRoomSnapshot currentRoom;
    try {
      currentRoom = await _loadRoomSnapshot(currentRoomId);
    } catch (error) {
      if (error is CoreCancelledError) rethrow;
      return _unknownSnapshot(
        source: requestedRoom,
        hostId: targetHostId,
        statusMessage: '主播当前直播间信息暂不可用，请稍后重试',
      );
    }
    if (currentRoom.hostId != targetHostId) {
      return _unknownSnapshot(
        source: requestedRoom,
        hostId: targetHostId,
        statusMessage: '当前直播间的主播标识不匹配，无法安全切换场次',
      );
    }
    if (!currentRoom.live) {
      return _unknownSnapshot(
        source: requestedRoom,
        hostId: targetHostId,
        statusMessage: '主播直播状态暂不可确认，请稍后重试',
      );
    }
    return currentRoom;
  }

  Future<dynamic> _requestHostProfile({
    required String hostId,
    required String roomId,
  }) async {
    const query = <String, dynamic>{
      'image_formats': 'jpg,webp',
      'xsec_source': 'pc_hovercard',
      'xsec_token': '',
    };
    final parameters = <String, dynamic>{
      'target_user_id': hostId,
      ...query,
    };
    try {
      final response = await HttpClient.instance.getJson(
        '$edithBaseUrl$hostProfilePath',
        queryParameters: parameters,
        header: _headers(),
        redactResponse: true,
      );
      if (response is Map && response['success'] == false) {
        // HTTP 200 with code -101 means the anonymous request lacks a session.
        // A configured signed session may still be able to read the profile.
        if ('${response['code']}' == '-101') {
          return _requestSignedHostProfile(hostId: hostId, roomId: roomId);
        }
        return null;
      }
      return _responseData(response);
    } catch (error) {
      if (error is CoreCancelledError) rethrow;
      if (error is XiaohongshuWebSessionUnavailableError) rethrow;
      if (error is! CoreError || error.statusCode != 406) return null;
      return _requestSignedHostProfile(hostId: hostId, roomId: roomId);
    }
  }

  Future<dynamic> _requestSignedHostProfile({
    required String hostId,
    required String roomId,
  }) async {
    final bridge = requestBridge;
    if (bridge is! XiaohongshuHostRequestBridge) return null;
    try {
      final response = await (bridge as XiaohongshuHostRequestBridge)
          .requestHost(hostId: hostId, roomId: roomId);
      return _responseData(response);
    } catch (error) {
      if (error is CoreCancelledError) rethrow;
      if (error is XiaohongshuWebSessionUnavailableError) rethrow;
      return null;
    }
  }

  static String? _profileIdentity(dynamic profile) {
    final data = _asMap(profile) ?? const <dynamic, dynamic>{};
    final basicInfo = _asMap(data['basic_info']) ??
        _asMap(data['basicInfo']) ??
        const <dynamic, dynamic>{};
    for (final candidate in [
      basicInfo['user_id'],
      basicInfo['userId'],
      basicInfo['target_user_id'],
      basicInfo['targetUserId'],
      data['user_id'],
      data['userId'],
      data['target_user_id'],
      data['targetUserId'],
    ]) {
      final raw = _text(candidate);
      if (raw.isNotEmpty) return _normalizeHostId(raw) ?? '';
    }
    return null;
  }

  static bool? _profileLiveStatus(dynamic profile) {
    final live = _profileLive(profile);
    final raw = live?['live_status'] ?? live?['liveStatus'];
    if (raw == null) return null;
    final value = int.tryParse(_text(raw));
    if (value == 2) return true;
    if (value == 0 || value == 1 || value == 3) return false;
    return null;
  }

  static String? _profileRoomId(dynamic profile) {
    final live = _profileLive(profile);
    if (live == null) return null;
    for (final candidate in [live['room_id'], live['roomId']]) {
      final roomId = _text(candidate);
      if (roomId.isNotEmpty) return roomId;
    }
    return null;
  }

  static Map<dynamic, dynamic>? _profileLive(dynamic profile) {
    final data = _asMap(profile);
    final basicInfo = _asMap(data?['basic_info']) ?? _asMap(data?['basicInfo']);
    return _asMap(basicInfo?['live']);
  }

  static XiaohongshuRoomSnapshot _offlineSnapshot(
    XiaohongshuRoomSnapshot source, {
    required String hostId,
    required String statusMessage,
  }) =>
      XiaohongshuRoomSnapshot(
        roomId: source.roomId,
        title: source.title,
        cover: source.cover,
        userName: source.userName,
        userAvatar: source.userAvatar,
        online: source.online,
        live: false,
        liveStatus: 'end',
        roomStatus: 0,
        streams: const [],
        url: _roomUrl(source.roomId, hostId),
        hostId: hostId,
        statusMessage: statusMessage,
      );

  static XiaohongshuRoomSnapshot _unknownSnapshot({
    XiaohongshuRoomSnapshot? source,
    String? roomId,
    String? hostId,
    required String statusMessage,
  }) =>
      XiaohongshuRoomSnapshot(
        roomId: source?.roomId ?? roomId ?? '',
        title: source?.title ?? '',
        cover: source?.cover ?? '',
        userName: source?.userName ?? '',
        userAvatar: source?.userAvatar ?? '',
        online: source?.online ?? 0,
        live: false,
        liveStatus: 'unknown',
        roomStatus: -1,
        streams: const [],
        url: _roomUrl(source?.roomId ?? roomId ?? '', hostId ?? source?.hostId),
        hostId: hostId ?? source?.hostId,
        statusMessage: statusMessage,
      );

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
    final liveStream = _asMap(root['liveStream']) ?? root;
    final roomData = _asMap(liveStream['roomData']) ??
        _asMap(root['roomData']) ??
        liveStream;
    final roomInfo = _asMap(roomData['roomInfo']) ??
        _asMap(liveStream['roomInfo']) ??
        _asMap(root['roomInfo']) ??
        const <dynamic, dynamic>{};
    if (roomInfo.isEmpty) {
      throw CoreError('小红书房间响应不完整', kind: CoreErrorKind.response);
    }
    final host = _asMap(roomData['hostInfo']) ??
        _asMap(roomInfo['hostInfo']) ??
        _asMap(liveStream['hostInfo']) ??
        _asMap(root['hostInfo']) ??
        const <dynamic, dynamic>{};
    final statusText = (roomData['liveStatus'] ??
                roomInfo['liveStatus'] ??
                liveStream['liveStatus'])
            ?.toString()
            .toLowerCase() ??
        '';
    final rawStatus = roomInfo['status'] ?? roomData['status'];
    final roomStatus = rawStatus == null ? -1 : _int(rawStatus);
    final streams =
        _parseStreams(roomData['pullConfig'] ?? roomInfo['pullConfig']);
    final deeplink = Uri.tryParse(_text(roomInfo['deeplink']));
    final deeplinkHostId = deeplink?.queryParameters['host_id'] ??
        deeplink?.queryParameters['hostId'];
    final hostId = _firstHostId([
      host['user_id'],
      host['userId'],
      host['host_id'],
      host['hostId'],
      host['id'],
      roomInfo['host_id'],
      roomInfo['hostId'],
      roomInfo['user_id'],
      roomInfo['userId'],
      deeplinkHostId,
    ]);
    return XiaohongshuRoomSnapshot(
      roomId: roomId,
      title: _text(
          roomInfo['roomTitle'] ?? roomInfo['title'] ?? roomData['title']),
      cover: _text(roomInfo['cover'] ?? roomInfo['roomCover'] ?? host['cover']),
      userName: _text(host['nickname'] ?? host['nickName'] ?? host['name']),
      userAvatar: _text(host['avatar'] ?? host['avatarUrl'] ?? host['image']),
      online: _int(
          roomInfo['displayViewerCount'] ?? roomData['displayViewerCount']),
      live: statusText == 'success' && roomStatus == 2,
      liveStatus: statusText,
      roomStatus: roomStatus,
      streams: streams,
      url: _roomUrl(roomId, hostId),
      hostId: hostId,
    );
  }

  static String _roomUrl(String roomId, String? hostId) =>
      '$webBaseUrl/livestream/$roomId${hostId == null ? '' : '?host_id=$hostId'}';

  static String? _firstHostId(Iterable<dynamic> candidates) {
    for (final candidate in candidates) {
      final hostId = _normalizeHostId(_text(candidate));
      if (hostId != null) return hostId;
    }
    return null;
  }

  static List<XiaohongshuStreamVariant> _parseStreams(dynamic value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return [];
      }
    }
    final width = value is Map ? _nullableInt(value['width']) : null;
    final height = value is Map ? _nullableInt(value['height']) : null;
    final result = <XiaohongshuStreamVariant>[];
    void visit(dynamic node, {String quality = '', String codec = ''}) {
      if (node is List) {
        for (final item in node) {
          visit(item, quality: quality, codec: codec);
        }
        return;
      }
      if (node is! Map) return;
      final rawQuality = _text(node['quality_type_name'] ??
          node['quality_type'] ??
          node['quality'] ??
          node['qualityName'] ??
          node['name']);
      final rawCodec = _text(node['codec'] ?? node['videoCodec']);
      final nextQuality = rawQuality.isEmpty ? quality : rawQuality;
      final nextCodec = rawCodec.isEmpty ? codec : rawCodec;
      final hls = _text(
          node['master_url'] ?? node['hlsUrl'] ?? node['hls'] ?? node['url']);
      final flv = _text(node['flvUrl'] ?? node['flv']);
      if (hls.isNotEmpty || flv.isNotEmpty) {
        final url = hls.isNotEmpty ? hls : flv;
        final parsedUrl = Uri.tryParse(url);
        if (parsedUrl != null &&
            (parsedUrl.scheme == 'https' || parsedUrl.scheme == 'http') &&
            parsedUrl.host.isNotEmpty) {
          result.add(XiaohongshuStreamVariant(
            url: url,
            flvUrl: flv.isEmpty ? null : flv,
            quality: _qualityName(nextQuality),
            codec: nextCodec,
            width: _nullableInt(node['width']) ?? width,
            height: _nullableInt(node['height']) ?? height,
            cdn: _text(node['cdn'] ?? node['cdnName']).isEmpty
                ? parsedUrl.host
                : _text(node['cdn'] ?? node['cdnName']),
          ));
        }
      }
      for (final entry in node.entries) {
        if (entry.value is Map || entry.value is List) {
          visit(entry.value,
              quality: nextQuality,
              codec: entry.key.toString().toLowerCase() == 'h265'
                  ? 'h265'
                  : (entry.key.toString().toLowerCase() == 'h264'
                      ? 'h264'
                      : nextCodec));
        }
      }
    }

    visit(value);
    final unique = <String, XiaohongshuStreamVariant>{};
    for (final item in result) {
      unique['${item.url}|${item.flvUrl}'] = item;
    }
    final variants = unique.values.toList();
    final h264 = variants
        .where((item) =>
            !item.codec.toLowerCase().contains('265') &&
            !item.codec.toLowerCase().contains('hevc'))
        .toList();
    return h264.isNotEmpty ? h264 : variants;
  }

  static String _qualityName(String value) {
    final text = value.trim().toUpperCase();
    if (text.contains('ORIGINAL') || text.contains('原画')) return '原画';
    if (text.contains('HD') || text.contains('高清')) return 'HD';
    if (text.contains('SD') || text.contains('标清')) return 'SD';
    if (text.contains('LD') || text.contains('流畅')) return 'LD';
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
    final marker = RegExp(r'window\.__INITIAL_STATE__\s*=\s*').firstMatch(html);
    if (marker == null) return null;
    final jsonStart = html.indexOf('{', marker.end);
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
          final decoded =
              json.decode(_normalizeSsrJson(html.substring(jsonStart, i + 1)));
          return decoded is Map ? decoded : null;
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  // Vue SSR serializes missing values as JavaScript `undefined`. Replace
  // only unquoted tokens; text supplied by the broadcaster stays unchanged.
  static String _normalizeSsrJson(String source) {
    final output = StringBuffer();
    var quoted = false;
    var escaped = false;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (!quoted && source.startsWith('undefined', index)) {
        output.write('null');
        index += 8;
        continue;
      }
      output.write(char);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
      } else if (char == '"') {
        quoted = true;
      }
    }
    return output.toString();
  }

  static Map<dynamic, dynamic>? _asMap(dynamic value) =>
      value is Map ? value : null;

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    final text = _text(value).replaceAll(',', '');
    final direct = int.tryParse(text);
    if (direct != null) return direct;
    final match = RegExp(r'^(\d+(?:\.\d+)?)(万|千|w)?\+?$', caseSensitive: false)
        .firstMatch(text);
    if (match == null) return 0;
    final number = double.tryParse(match.group(1)!);
    if (number == null) return 0;
    return (number *
            (match.group(2) == null
                ? 1
                : (match.group(2) == '千' ? 1000 : 10000)))
        .round();
  }

  static int? _nullableInt(dynamic value) {
    final result = _int(value);
    return result == 0 && _text(value) != '0' ? null : result;
  }
}
