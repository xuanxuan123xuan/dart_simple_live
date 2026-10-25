import 'dart:convert';

import 'package:simple_live_core/src/common/core_error.dart';
import 'model/live_anchor_item.dart';
import 'model/live_category.dart';
import 'model/live_category_result.dart';
import 'model/live_room_item.dart';
import 'model/live_search_result.dart';
export 'xiaohongshu_discovery_session.dart';

/// The bridge used for the two read-only live discovery endpoints.
///
/// Discovery uses its own session so room playback/comment requests cannot
/// accidentally broaden the set of paths that the page bridge may request.
abstract interface class XiaohongshuDiscoveryRequestBridge {
  /// Returns a normalized response envelope with the API payload in `data`.
  /// Page clients that unwrap the official response must wrap successful data
  /// as `{success: true, data: payload}` and preserve business error envelopes.
  Future<dynamic> requestDiscovery({
    required String path,
    Map<String, dynamic> query = const <String, dynamic>{},
  });
}

typedef XiaohongshuDiscoveryRequest = Future<dynamic> Function(
  String path,
  Map<String, dynamic> query,
);

/// Maps the vendor's live feed/category responses to the core directory types.
/// Ordinary note/user search results are deliberately never used as live cards.
class XiaohongshuDiscoveryClient {
  XiaohongshuDiscoveryClient({
    XiaohongshuDiscoveryRequest? request,
    bool Function()? isAvailable,
  })  : _request = request,
        _isAvailable = isAvailable;

  static const String categoryPath = '/api/sns/red/live/web/feed/category';
  static const String squareFeedPath =
      '/api/sns/red/live/web/feed/v1/squarefeed';
  static const unavailableReason = '小红书直播搜索暂不可用，可粘贴直播链接进入';
  final XiaohongshuDiscoveryRequest? _request;
  final bool Function()? _isAvailable;
  bool get isAvailable => _isAvailable?.call() ?? false;

  static const unavailableMetadata = LiveSearchMetadata(
    continuation: SearchContinuation.unknown,
    origin: SearchOrigin.fallback,
  );

  final Map<String, _ChannelPagination> _channels = {};
  final Map<String, int> _generations = {};

  /// Clears cursor and de-duplication state after a discovery session changes.
  void resetPagination() {
    for (final key in _generations.keys.toList()) {
      _generations[key] = _generations[key]! + 1;
    }
    _channels.clear();
  }

  Future<List<LiveCategory>> getCategories() async {
    if (!isAvailable) return <LiveCategory>[];
    final response = await _send(categoryPath, const <String, dynamic>{});
    final data = _data(response);
    final categories = _requiredList(data, 'categories');
    final children = <LiveSubCategory>[];
    for (final value in categories) {
      final map = _asMap(value);
      if (map == null) continue;
      final id = _text(map, 'id');
      final name = _text(map, 'desc');
      if (id == null || name == null) continue;
      children.add(LiveSubCategory(
        id: id,
        name: name,
        parentId: 'xiaohongshu',
      ));
    }
    if (children.isEmpty) return <LiveCategory>[];
    return <LiveCategory>[
      LiveCategory(
        id: 'xiaohongshu',
        name: '小红书直播',
        children: children,
      ),
    ];
  }

  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) =>
      _getRooms(categoryId: '0', page: page, key: 'recommend');

  Future<LiveCategoryResult> getRooms({
    required String categoryId,
    int page = 1,
  }) =>
      _getRooms(
          categoryId: categoryId, page: page, key: 'category:$categoryId');

  Future<LiveCategoryResult> _getRooms({
    required String categoryId,
    required int page,
    required String key,
  }) async {
    if (!isAvailable || page < 1 || categoryId.trim().isEmpty) {
      return _emptyRooms();
    }

    late final _ChannelPagination channel;
    if (page == 1) {
      final generation = (_generations[key] ?? 0) + 1;
      _generations[key] = generation;
      channel = _ChannelPagination(generation);
      _channels[key] = channel;
    } else {
      channel = _channels[key] ?? _ChannelPagination(-1);
      if (_channels[key] != channel ||
          _generations[key] != channel.generation ||
          channel.stopped ||
          channel.requesting ||
          channel.nextPage != page ||
          channel.cursor == null) {
        return _emptyRooms();
      }
    }

    final cursor = page == 1 ? null : channel.cursor;
    final query = <String, dynamic>{
      'cursorScore': cursor ?? '0',
      'source': 13,
      'category': categoryId,
      'topRoomIds': <String>[],
      'preSource': '',
      'extraInfo': '',
      'size': 27,
      'extra_info': jsonEncode({
        'image_formats': ['jpg', 'webp', 'avif'],
      }),
    };
    channel.requesting = true;
    final dynamic response;
    try {
      response = await _send(squareFeedPath, query);
    } finally {
      channel.requesting = false;
    }
    if (_channels[key] != channel || _generations[key] != channel.generation) {
      return _emptyRooms();
    }

    final data = _data(response);
    final rows = _requiredList(data, 'feeds');
    final items = <LiveRoomItem>[];
    for (final value in rows) {
      final item = _parseRoom(value);
      if (item == null || !channel.roomIds.add(item.roomId)) continue;
      items.add(item);
    }

    final nextCursor =
        rows.isEmpty ? null : _text(_asMap(rows.last), 'cursorScore');
    final canContinue = items.isNotEmpty &&
        nextCursor != null &&
        nextCursor != (cursor ?? '0') &&
        !channel.seenCursors.contains(nextCursor);
    if (canContinue) {
      channel.cursor = nextCursor;
      channel.seenCursors.add(nextCursor);
      channel.nextPage = page + 1;
    } else {
      channel.cursor = null;
      channel.nextPage = page + 1;
      channel.stopped = true;
    }
    return LiveCategoryResult(hasMore: canContinue, items: items);
  }

  Future<LiveSearchRoomResult> searchRooms() async => LiveSearchRoomResult(
        items: <LiveRoomItem>[],
        metadata: unavailableMetadata,
      );
  Future<LiveSearchAnchorResult> searchAnchors() async =>
      LiveSearchAnchorResult(
        items: <LiveAnchorItem>[],
        metadata: unavailableMetadata,
      );

  Future<dynamic> _send(String path, Map<String, dynamic> query) {
    final request = _request;
    if (!isAvailable || request == null) {
      throw CoreError('小红书直播发现会话不可用', kind: CoreErrorKind.response);
    }
    if (path != categoryPath && path != squareFeedPath) {
      throw CoreError('小红书直播发现接口不受支持', kind: CoreErrorKind.response);
    }
    return request(path, Map<String, dynamic>.unmodifiable(query));
  }

  static LiveCategoryResult _emptyRooms() =>
      LiveCategoryResult(hasMore: false, items: <LiveRoomItem>[]);

  static Map<dynamic, dynamic> _data(dynamic response) {
    if (response is! Map || response['success'] == false) {
      throw CoreError('小红书直播发现响应不可用', kind: CoreErrorKind.response);
    }
    final code = response['code'];
    if (code != null && code.toString() != '0') {
      throw CoreError('小红书直播发现响应不可用', kind: CoreErrorKind.response);
    }
    final data = response['data'];
    if (data is! Map) {
      throw CoreError('小红书直播发现数据格式异常', kind: CoreErrorKind.response);
    }
    return data;
  }

  static List<dynamic> _requiredList(Map<dynamic, dynamic> data, String key) {
    final value = data[key];
    if (value is List) return value;
    throw CoreError('小红书直播发现数据格式异常', kind: CoreErrorKind.response);
  }

  static Map<dynamic, dynamic>? _asMap(dynamic value) =>
      value is Map ? value : null;

  static LiveRoomItem? _parseRoom(dynamic value) {
    final feed = _asMap(value);
    if (feed == null) return null;
    final live = _asMap(feed['live']);
    final room = _asMap(live?['tRoomInfo']);
    final rawRoomId = room?['roomIdStr'];
    if (rawRoomId is! String ||
        !RegExp(r'^\d{8,32}$').hasMatch(rawRoomId.trim())) {
      return null;
    }
    final roomId = rawRoomId.trim();
    final coverInfo = _asMap(room?['coverInfo']);
    final host = _asMap(live?['tLiveHostInfo']);
    final cover = _text(coverInfo, 'coverImage');
    final userName = _text(host, 'nickname');
    if (cover == null || userName == null) return null;
    return LiveRoomItem(
      roomId: roomId,
      title: _text(room, 'name') ?? '',
      cover: cover,
      userName: userName,
      online: int.tryParse(_text(room, 'displayCount') ?? '') ?? 0,
    );
  }

  static String? _text(Map<dynamic, dynamic>? map, String key) {
    final value = map?[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
    return null;
  }
}

class _ChannelPagination {
  _ChannelPagination(this.generation);

  final int generation;
  String? cursor;
  int nextPage = 1;
  bool stopped = false;
  bool requesting = false;
  final Set<String> seenCursors = <String>{};
  final Set<String> roomIds = <String>{};
}
