import 'package:flutter/services.dart';
import 'site_registry.dart';

class TvosLoginResult {
  const TvosLoginResult({required this.provider, required this.cookie});

  final LiveProvider provider;
  final String cookie;
}

abstract interface class TvosSessionStore {
  Future<String?> readCookie(LiveProvider provider);

  Future<void> saveCookie(LiveProvider provider, String cookie);

  Future<void> clearCookie(LiveProvider provider);
}

abstract interface class TvosWebSessionBridge {
  Future<TvosLoginResult> login(LiveProvider provider);

  Future<void> close();
}

/// In-memory fallback used by Windows analysis/tests and unsupported hosts.
class MemoryTvosSessionStore implements TvosSessionStore {
  final Map<LiveProvider, String> _cookies = <LiveProvider, String>{};

  @override
  Future<String?> readCookie(LiveProvider provider) async => _cookies[provider];

  @override
  Future<void> saveCookie(LiveProvider provider, String cookie) async {
    final value = cookie.trim();
    if (value.isEmpty) {
      _cookies.remove(provider);
    } else {
      _cookies[provider] = value;
    }
  }

  @override
  Future<void> clearCookie(LiveProvider provider) async {
    _cookies.remove(provider);
  }
}

/// Method-channel boundary for the tvOS Keychain implementation.
///
/// The channel is intentionally optional. On Windows, or before the native
/// tvOS host is generated, missing-plugin errors are handled by the caller and
/// the app continues with the in-memory fallback.
class MethodChannelTvosSessionStore implements TvosSessionStore {
  MethodChannelTvosSessionStore({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('simple_live/tvos_session');

  final MethodChannel _channel;

  String _key(LiveProvider provider) => provider.name;

  @override
  Future<String?> readCookie(LiveProvider provider) async {
    final value = await _channel.invokeMethod<String>('readCookie', {
      'provider': _key(provider),
    });
    return value?.trim().isEmpty ?? true ? null : value!.trim();
  }

  @override
  Future<void> saveCookie(LiveProvider provider, String cookie) async {
    await _channel.invokeMethod<void>('saveCookie', {
      'provider': _key(provider),
      'cookie': cookie.trim(),
    });
  }

  @override
  Future<void> clearCookie(LiveProvider provider) async {
    await _channel.invokeMethod<void>('clearCookie', {
      'provider': _key(provider),
    });
  }
}

/// Optional native bridge for a provider's read-only web login flow.
class MethodChannelTvosWebSessionBridge implements TvosWebSessionBridge {
  MethodChannelTvosWebSessionBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('simple_live/tvos_web');

  final MethodChannel _channel;

  @override
  Future<TvosLoginResult> login(LiveProvider provider) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('login', {
      'provider': provider.name,
    });
    final cookie = result?['cookie']?.toString().trim() ?? '';
    if (cookie.isEmpty) {
      throw StateError('网页登录没有返回有效会话 Cookie');
    }
    return TvosLoginResult(provider: provider, cookie: cookie);
  }

  @override
  Future<void> close() => _channel.invokeMethod<void>('close');
}

Future<void> restoreTvosCookies(TvosSessionStore store) async {
  for (final provider in <LiveProvider>[
    LiveProvider.bilibili,
    LiveProvider.douyu,
    LiveProvider.douyin,
    LiveProvider.kuaishou,
    LiveProvider.xiaohongshu,
  ]) {
    try {
      final cookie = await store.readCookie(provider);
      if (cookie != null && cookie.isNotEmpty) {
        SiteRegistry.instance.setSessionCookie(provider, cookie);
      }
    } on MissingPluginException {
      return;
    } on UnsupportedError {
      // A provider without a cookie field remains anonymous.
    }
  }
}
