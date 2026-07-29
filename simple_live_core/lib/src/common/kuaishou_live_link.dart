class KuaishouLiveLink {
  static final RegExp _roomIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  static const Set<String> _knownHosts = {
    'live.kuaishou.com',
    'v.kuaishou.com',
    'm.chenzhongtech.com',
  };

  static Uri publicRoomUri(String roomId) {
    final normalized = roomId.trim();
    if (!_roomIdPattern.hasMatch(normalized)) {
      throw ArgumentError.value(roomId, 'roomId', '无效的快手直播间 ID');
    }
    return Uri.https('live.kuaishou.com', '/u/$normalized');
  }

  static String publicRoomUrl(String roomId) =>
      publicRoomUri(roomId).toString();

  static String? parseHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        !_isKnownHost(uri.host)) {
      return null;
    }

    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (uri.host.toLowerCase() == 'live.kuaishou.com' &&
        segments.length == 2 &&
        segments.first == 'u') {
      return _validRoomId(segments[1]);
    }
    if (_isMobileHost(uri.host) &&
        segments.length == 3 &&
        segments[0] == 'fw' &&
        segments[1] == 'live') {
      return _validRoomId(segments[2]);
    }
    return null;
  }

  static bool isShortLink(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.userInfo.isEmpty &&
        uri.host.toLowerCase() == 'v.kuaishou.com';
  }

  static bool isTrustedRedirectTarget(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.userInfo.isEmpty &&
        _isKnownHost(uri.host);
  }

  static bool _isKnownHost(String host) {
    final normalized = host.toLowerCase();
    return _knownHosts.contains(normalized) ||
        normalized.endsWith('.m.chenzhongtech.com');
  }

  static bool _isMobileHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'm.chenzhongtech.com' ||
        normalized.endsWith('.m.chenzhongtech.com');
  }

  static String? _validRoomId(String value) {
    final roomId = Uri.decodeComponent(value).trim();
    return _roomIdPattern.hasMatch(roomId) ? roomId : null;
  }
}
