import 'package:dio/dio.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class LiveRoomLinkTarget {
  const LiveRoomLinkTarget({
    required this.site,
    required this.roomId,
  });

  final Site site;
  final String roomId;
}

/// Parses supported live-room links without depending on widgets or navigation.
class LiveRoomLinkParser {
  LiveRoomLinkParser({
    Dio? redirectClient,
    Future<String> Function(String url)? locationResolver,
  })  : _redirectClient = redirectClient ?? Dio(),
        _locationResolver = locationResolver;

  static const int _maxRedirects = 5;
  static const Set<String> _douyuHosts = {
    'douyu.com',
    'www.douyu.com',
    'm.douyu.com',
  };
  static const Set<String> _huyaHosts = {
    'huya.com',
    'www.huya.com',
    'm.huya.com',
  };
  final Dio _redirectClient;
  final Future<String> Function(String url)? _locationResolver;

  Future<LiveRoomLinkTarget?> parse(String input) async {
    final extractedUrl = extractHttpUrl(input);
    if (extractedUrl.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(extractedUrl);
    if (uri == null || !_isHttpUri(uri)) {
      return null;
    }

    final kuaishouRoomId = KuaishouLiveLink.parseHttpUrl(extractedUrl);
    if (kuaishouRoomId != null) {
      return _target(Constant.kKuaishou, kuaishouRoomId);
    }
    if (KuaishouLiveLink.isShortLink(extractedUrl)) {
      final location = _locationResolver != null
          ? await _locationResolver!(extractedUrl)
          : await _resolveLocation(
              extractedUrl,
              isAllowed: KuaishouLiveLink.isTrustedRedirectTarget,
            );
      if (!KuaishouLiveLink.isTrustedRedirectTarget(location)) {
        return null;
      }
      final roomId = KuaishouLiveLink.parseHttpUrl(location);
      return roomId == null ? null : _target(Constant.kKuaishou, roomId);
    }

    final host = uri.host.toLowerCase();
    if (host == 'live.bilibili.com') {
      return _target(Constant.kBiliBili, _firstPathSegment(uri));
    }
    if (host == 'b23.tv' || host == 'www.b23.tv') {
      final location = await _resolveLocation(extractedUrl);
      return location.isEmpty ? null : parse(location);
    }

    if (_douyuHosts.contains(host)) {
      final roomId = uri.queryParameters['rid']?.trim();
      if (uri.pathSegments.contains('topic') && roomId != null) {
        return _target(Constant.kDouyu, roomId);
      }
      return _target(Constant.kDouyu, _firstPathSegment(uri));
    }
    if (_huyaHosts.contains(host)) {
      return _target(Constant.kHuya, _firstPathSegment(uri));
    }
    if (host == 'live.douyin.com') {
      return _target(Constant.kDouyin, _firstPathSegment(uri));
    }
    if (host == 'webcast.amemv.com') {
      final reflowIndex = uri.pathSegments.indexOf('reflow');
      final roomId =
          reflowIndex >= 0 && reflowIndex + 1 < uri.pathSegments.length
              ? uri.pathSegments[reflowIndex + 1]
              : '';
      return _target(Constant.kDouyin, roomId);
    }
    if (host == 'v.douyin.com') {
      final location = await _resolveLocation(extractedUrl);
      return location.isEmpty ? null : parse(location);
    }
    return null;
  }

  LiveRoomLinkTarget? _target(String siteId, String roomId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalizedRoomId)) {
      return null;
    }
    final site = Sites.allSites[siteId];
    return site == null
        ? null
        : LiveRoomLinkTarget(site: site, roomId: normalizedRoomId);
  }

  static String _firstPathSegment(Uri uri) {
    return uri.pathSegments
        .map((segment) => segment.trim())
        .firstWhere((segment) => segment.isNotEmpty, orElse: () => '');
  }

  static bool _isHttpUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
  }

  Future<String> _resolveLocation(
    String url, {
    bool Function(String url)? isAllowed,
  }) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null || !_isHttpUri(parsed)) {
      return '';
    }
    var current = parsed;
    if (isAllowed != null && !isAllowed(current.toString())) {
      return '';
    }
    try {
      for (var redirectCount = 0;
          redirectCount < _maxRedirects;
          redirectCount++) {
        final response = await _redirectClient.getUri<dynamic>(
          current,
          options: Options(
            followRedirects: false,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
            headers: const <String, dynamic>{},
          ),
        );
        final statusCode = response.statusCode ?? 0;
        if (statusCode < 300 || statusCode >= 400) {
          return current.toString();
        }
        final location = response.headers.value('location');
        if (location == null || location.trim().isEmpty) {
          return '';
        }
        final next = current.resolve(location.trim());
        if (!_isHttpUri(next) ||
            (isAllowed != null && !isAllowed(next.toString()))) {
          return '';
        }
        current = next;
      }
    } catch (error) {
      Log.logPrint(error);
    }
    return '';
  }

  static String extractHttpUrl(String text) {
    return RegExp(
          r'https?://[^\s<>\u3000，。！？、；：]+',
          caseSensitive: false,
        ).firstMatch(text)?.group(0)?.replaceFirst(
              RegExp(r'[，。！？、；：,.;:!?]+$'),
              '',
            ) ??
        '';
  }
}
