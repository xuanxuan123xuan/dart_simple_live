import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_app/services/xiaohongshu_host_id.dart';

/// Keeps share-link metadata scoped to the room that supplied it.
class LiveRoomDetailLoader {
  LiveRoomDetailLoader({
    required LiveSite site,
    required String roomId,
    String? douyinSecUserId,
    String? xiaohongshuHostId,
  }) {
    final secUserId = douyinSecUserId?.trim();
    if (site is DouyinSite && secUserId != null && secUserId.isNotEmpty) {
      _douyinSite = site;
      _douyinRoomId = roomId;
      _douyinSecUserId = secUserId;
    }
    final hostId = normalizeXiaohongshuHostId(xiaohongshuHostId);
    if (site is XiaohongshuSite && hostId != null) {
      _xiaohongshuSite = site;
      _xiaohongshuRoomId = roomId;
      _xiaohongshuHostId = hostId;
    }
  }

  DouyinSite? _douyinSite;
  String? _douyinRoomId;
  String? _douyinSecUserId;
  XiaohongshuSite? _xiaohongshuSite;
  String? _xiaohongshuRoomId;
  String? _xiaohongshuHostId;

  String? xiaohongshuHostIdFor({
    required LiveSite site,
    required String roomId,
  }) =>
      identical(site, _xiaohongshuSite) && roomId == _xiaohongshuRoomId
          ? _xiaohongshuHostId
          : null;

  void clearDouyinShareContext() {
    _douyinSite = null;
    _douyinRoomId = null;
    _douyinSecUserId = null;
  }

  void clearXiaohongshuShareContext() {
    _requestSequence++;
    _xiaohongshuSite = null;
    _xiaohongshuRoomId = null;
    _xiaohongshuHostId = null;
  }

  Future<LiveRoomDetail> load({
    required LiveSite site,
    required String roomId,
    String? xiaohongshuHostId,
    KuaishouRequestSource? source,
  }) async {
    final sameXiaohongshuContext =
        identical(site, _xiaohongshuSite) && roomId == _xiaohongshuRoomId;
    if (!identical(site, _douyinSite) || roomId != _douyinRoomId) {
      clearDouyinShareContext();
    }
    if (!sameXiaohongshuContext) {
      clearXiaohongshuShareContext();
    }
    final suppliedHostId = normalizeXiaohongshuHostId(xiaohongshuHostId);
    if (site is XiaohongshuSite && suppliedHostId != null) {
      _xiaohongshuSite = site;
      _xiaohongshuRoomId = roomId;
      _xiaohongshuHostId = suppliedHostId;
    }
    final secUserId = _douyinSecUserId;
    final hostId = _xiaohongshuHostId;
    final requestSequence = ++_requestSequence;
    Future<LiveRoomDetail> fetch() => site is DouyinSite
        ? site.getRoomDetail(roomId: roomId, secUserId: secUserId)
        : site is XiaohongshuSite
            ? site.getRoomDetail(roomId: roomId, hostId: hostId)
            : site.getRoomDetail(roomId: roomId);

    final detail = await (source == null
        ? fetch()
        : KuaishouRequestTrace.run(source, fetch));
    if (detail.roomId != roomId &&
        identical(site, _douyinSite) &&
        roomId == _douyinRoomId) {
      clearDouyinShareContext();
    }
    if (requestSequence == _requestSequence &&
        site is XiaohongshuSite &&
        detail.resolvedLiveStatus != LiveStatusState.unknown) {
      final snapshot = detail.data;
      final resolvedHostId = snapshot is XiaohongshuRoomSnapshot
          ? normalizeXiaohongshuHostId(snapshot.hostId)
          : null;
      final hostMatches =
          hostId == null || resolvedHostId == null || hostId == resolvedHostId;
      final retainedHostId =
          resolvedHostId?.isNotEmpty == true ? resolvedHostId : hostId;
      if (hostMatches) {
        _xiaohongshuSite = site;
        _xiaohongshuRoomId = detail.roomId;
        _xiaohongshuHostId = retainedHostId;
      }
    }
    return detail;
  }

  int _requestSequence = 0;
}
