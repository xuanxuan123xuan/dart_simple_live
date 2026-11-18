import 'package:simple_live_core/simple_live_core.dart';
import 'site_registry.dart';

/// Native AVPlayer is only guaranteed to support HLS. We do not label FLV
/// links as playable even when they carry authentication query parameters.
bool isHlsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    return false;
  }
  return classifyLiveStreamProtocol(value) == LiveStreamProtocol.hls;
}

List<String> hlsOnly(LivePlayUrl source) =>
    source.urls.where(isHlsUrl).toSet().toList(growable: false);

class ResolvedRoom {
  const ResolvedRoom({
    required this.reference,
    required this.site,
    required this.detail,
    required this.qualities,
  });
  final RoomRef reference;
  final LiveSite site;
  final LiveRoomDetail detail;
  final List<LivePlayQuality> qualities;
}

Future<ResolvedRoom> resolveRoom(RoomRef ref) async {
  final site = SiteRegistry.instance.get(ref.provider);
  final detail = await site.getRoomDetail(roomId: ref.roomId.trim());
  if (detail.resolvedLiveStatus == LiveStatusState.offline) {
    throw StateError('直播间已下播：${ref.title}');
  }
  final qualities = await site.getPlayQualites(detail: detail);
  if (qualities.isEmpty) throw StateError('直播间没有返回任何清晰度');
  return ResolvedRoom(
    reference: RoomRef.fromDetail(ref.provider, detail),
    site: site,
    detail: detail,
    qualities: qualities,
  );
}

String playbackFailureHint(List<String> urls) {
  if (urls.isEmpty) return '平台没有返回播放地址';
  final protocols = urls.map(classifyLiveStreamProtocol).toSet();
  if (protocols.contains(LiveStreamProtocol.flv)) {
    return '平台仅返回 FLV，当前 tvOS 原生 AVPlayer 不支持 HTTP-FLV。'
        '请等待接入 FLV 播放后端，或使用 HLS 线路。';
  }
  return '没有可供 AVPlayer 播放的 HLS 线路，返回协议：'
      '${protocols.map((e) => e.label).join(', ')}';
}
