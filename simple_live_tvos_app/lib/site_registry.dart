import 'package:simple_live_core/simple_live_core.dart';

enum LiveProvider { bilibili, huya, douyu, douyin, kuaishou, xiaohongshu }

enum TvosProviderSupport { hls, sessionRequired, unavailable }

extension ProviderLabels on LiveProvider {
  String get title => switch (this) {
        LiveProvider.bilibili => '哔哩哔哩',
        LiveProvider.huya => '虎牙',
        LiveProvider.douyu => '斗鱼',
        LiveProvider.douyin => '抖音',
        LiveProvider.kuaishou => '快手',
        LiveProvider.xiaohongshu => '小红书',
      };
  String get caveat => switch (this) {
        LiveProvider.bilibili => '优先支持 HLS',
        LiveProvider.huya => '当前通常返回 FLV，暂不能原生播放',
        LiveProvider.douyu => 'JS 签名与 FLV 尚未适配',
        LiveProvider.douyin => 'JS 签名或认证可能阻止取流',
        LiveProvider.kuaishou => '需依实际返回的流格式判断',
        LiveProvider.xiaohongshu => '部分接口需要网页登录会话',
      };

  TvosProviderSupport get tvosSupport => switch (this) {
        LiveProvider.bilibili => TvosProviderSupport.hls,
        LiveProvider.kuaishou => TvosProviderSupport.sessionRequired,
        LiveProvider.xiaohongshu => TvosProviderSupport.sessionRequired,
        LiveProvider.huya ||
        LiveProvider.douyu ||
        LiveProvider.douyin =>
          TvosProviderSupport.unavailable,
      };

  String get tvosSupportLabel => switch (tvosSupport) {
        TvosProviderSupport.hls => 'HLS 可尝试播放',
        TvosProviderSupport.sessionRequired => '可能需要会话',
        TvosProviderSupport.unavailable => '当前暂不支持播放',
      };
}

class SiteRegistry {
  SiteRegistry._();
  static final instance = SiteRegistry._();
  final Map<LiveProvider, LiveSite> _sites = {};

  LiveSite get(LiveProvider provider) => _sites.putIfAbsent(provider, () {
        return switch (provider) {
          LiveProvider.bilibili => BiliBiliSite(),
          LiveProvider.huya => HuyaSite(),
          LiveProvider.douyu => DouyuSite(),
          LiveProvider.douyin => DouyinSite(),
          LiveProvider.kuaishou => KuaishouSite(),
          LiveProvider.xiaohongshu => XiaohongshuSite(),
        };
      });

  /// Cookie stays in memory. Intentionally never saved to SharedPreferences.
  void setSessionCookie(LiveProvider provider, String cookie) {
    final site = get(provider);
    switch (provider) {
      case LiveProvider.bilibili:
        (site as BiliBiliSite).cookie = cookie;
        break;
      case LiveProvider.douyu:
        (site as DouyuSite).cookie = cookie;
        break;
      case LiveProvider.douyin:
        (site as DouyinSite).cookie = cookie;
        break;
      case LiveProvider.kuaishou:
        (site as KuaishouSite).cookie = cookie;
        break;
      case LiveProvider.huya:
        throw UnsupportedError('虎牙当前没有可配置的会话 Cookie');
      case LiveProvider.xiaohongshu:
        (site as XiaohongshuSite).cookie = cookie;
        break;
    }
  }
}

class RoomRef {
  const RoomRef({
    required this.provider,
    required this.roomId,
    required this.title,
    this.anchor = '',
    this.cover = '',
  });
  final LiveProvider provider;
  final String roomId;
  final String title;
  final String anchor;
  final String cover;
  String get key => '${provider.name}:$roomId';
  factory RoomRef.fromSearch(LiveProvider provider, LiveRoomItem item) =>
      RoomRef(
        provider: provider,
        roomId: item.roomId,
        title: item.title,
        anchor: item.userName,
        cover: item.cover,
      );
  factory RoomRef.fromDetail(LiveProvider provider, LiveRoomDetail detail) =>
      RoomRef(
        provider: provider,
        roomId: detail.roomId,
        title: detail.title,
        anchor: detail.userName,
        cover: detail.cover,
      );
  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'roomId': roomId,
        'title': title,
        'anchor': anchor,
        'cover': cover,
      };
  static RoomRef? fromJson(Object? obj) {
    if (obj is! Map) return null;
    final providerName = obj['provider']?.toString();
    final roomId = obj['roomId']?.toString() ?? '';
    if (roomId.isEmpty) return null;
    final provider = LiveProvider.values.where((p) => p.name == providerName);
    if (provider.isEmpty) return null;
    return RoomRef(
      provider: provider.first,
      roomId: roomId,
      title: obj['title']?.toString() ?? roomId,
      anchor: obj['anchor']?.toString() ?? '',
      cover: obj['cover']?.toString() ?? '',
    );
  }
}
