enum TvPlaybackSuspension { background, focus, resources }

/// Playback permission belongs to the user and the owning session, rather than
/// the native player's last event. Recovery must recheck this after every await.
class TvPlaybackIntent {
  bool userPaused = false;
  bool _closed = false;
  final Set<TvPlaybackSuspension> _suspensions = {};

  bool get shouldPlay => !userPaused && !_closed && _suspensions.isEmpty;
  bool get isClosed => _closed;

  void suspend(TvPlaybackSuspension reason) => _suspensions.add(reason);
  void resume(TvPlaybackSuspension reason) => _suspensions.remove(reason);
  void close() => _closed = true;
}
