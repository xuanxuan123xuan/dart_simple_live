import 'package:video_player/video_player.dart';

/// A platform-neutral boundary around the tvOS video backend.
///
/// The first tvOS implementation deliberately supports HLS through AVPlayer.
/// A future FLV backend can implement this interface without changing the
/// room, quality, or line-selection code.
abstract interface class TvosPlaybackBackend {
  Future<TvosPlaybackSession> open(
    String url, {
    Map<String, String> headers,
    Duration timeout,
  });

  Future<void> close();
}

class TvosPlaybackSession {
  TvosPlaybackSession(this.controller, {this.onDispose});

  final VideoPlayerController controller;
  final void Function()? onDispose;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    onDispose?.call();
    await controller.dispose();
  }
}

class AvPlayerHlsBackend implements TvosPlaybackBackend {
  final Set<TvosPlaybackSession> _sessions = <TvosPlaybackSession>{};

  @override
  Future<TvosPlaybackSession> open(
    String url, {
    Map<String, String> headers = const <String, String>{},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw const FormatException('播放地址必须是合法的 http(s) URL');
    }

    final controller = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: headers,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await controller.initialize().timeout(timeout);
      late final TvosPlaybackSession session;
      session = TvosPlaybackSession(
        controller,
        onDispose: () => _sessions.remove(session),
      );
      _sessions.add(session);
      return session;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    final sessions = _sessions.toList(growable: false);
    _sessions.clear();
    for (final session in sessions) {
      try {
        await session.dispose();
      } catch (_) {
        // A failed player teardown must not block the page from closing.
      }
    }
  }
}
