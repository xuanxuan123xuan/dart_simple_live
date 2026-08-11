abstract interface class CoreCancellation {
  bool get isCancelled;

  void cancel([Object? reason]);

  void addListener(void Function() listener);

  void removeListener(void Function() listener);
}

final class CoreCancellationToken implements CoreCancellation {
  bool _isCancelled = false;
  Object? _reason;
  final Set<void Function()> _listeners = <void Function()>{};

  @override
  bool get isCancelled => _isCancelled;

  Object? get reason => _reason;

  @override
  void cancel([Object? reason]) {
    if (_isCancelled) {
      return;
    }

    _isCancelled = true;
    _reason = reason;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  @override
  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}
