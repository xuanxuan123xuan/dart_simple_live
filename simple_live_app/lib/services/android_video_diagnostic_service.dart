import 'dart:async';
import 'dart:convert';

typedef AndroidVideoDiagnosticLocalReader = Map<String, Object?> Function();
typedef AndroidVideoDiagnosticPropertyReader = Future<Object?> Function(
    String property);
typedef AndroidVideoDiagnosticWriter = void Function(String line);
typedef AndroidVideoDiagnosticFlusher = Future<void> Function();
typedef AndroidVideoDiagnosticTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer timer) callback,
);

class _AndroidNativePropertyRead {
  const _AndroidNativePropertyRead(
    this.generation,
    this.runRevision,
    this.future,
  );

  final int generation;
  final int runRevision;
  final Future<Object?> future;
}

/// Samples application and mpv state for an Android video output.
///
/// Each native property has at most one unresolved read. A timed-out read stays
/// registered until the platform future settles, so a broken native channel
/// cannot accumulate another request every five seconds.
class AndroidVideoDiagnosticService {
  AndroidVideoDiagnosticService({
    required AndroidVideoDiagnosticLocalReader readLocalSnapshot,
    required AndroidVideoDiagnosticPropertyReader readNativeProperty,
    required AndroidVideoDiagnosticWriter write,
    required AndroidVideoDiagnosticFlusher flush,
    required int Function() readGeneration,
    required bool Function() isLogEnabled,
    AndroidVideoDiagnosticTimerFactory? createTimer,
    this.interval = const Duration(seconds: 5),
    this.nativePropertyTimeout = const Duration(milliseconds: 600),
  })  : _readLocalSnapshot = readLocalSnapshot,
        _readNativeProperty = readNativeProperty,
        _write = write,
        _flush = flush,
        _readGeneration = readGeneration,
        _isLogEnabled = isLogEnabled,
        _createTimer = createTimer ?? Timer.periodic;

  static const Set<String> nativeProperties = {
    'current-vo',
    'wid',
    'hwdec-current',
    'video-codec',
    'estimated-vf-fps',
  };

  static const Set<String> localSnapshotFields = {
    'playing',
    'buffering',
    'videoTrackCount',
    'audioTrackCount',
    'sourceWidth',
    'sourceHeight',
    'outputWidth',
    'outputHeight',
    'textureId',
    'wid',
    'videoParamsAvailable',
    'handle',
  };

  static const Set<String> eventNames = {
    'init',
    'video_params',
    'texture_update',
    'bind_start',
    'bind_complete',
    'bind_error',
    'load',
    'unload',
    'dispose',
    'surface_create',
    'surface_size_requested',
    'surface_publish',
    'surface_cleanup',
    'surface_error',
  };

  static const Set<String> eventFields = {
    'handle',
    'textureId',
    'surfaceIdentity',
    'bindRevision',
    'oldWid',
    'wid',
    'width',
    'height',
    'valid',
    'reason',
    'level',
    'error',
    'vo',
    'hwdec',
    'stage',
    'bindResult',
    'bindingResult',
    'bound',
    'renderConfirmed',
  };

  final AndroidVideoDiagnosticLocalReader _readLocalSnapshot;
  final AndroidVideoDiagnosticPropertyReader _readNativeProperty;
  final AndroidVideoDiagnosticWriter _write;
  final AndroidVideoDiagnosticFlusher _flush;
  final int Function() _readGeneration;
  final bool Function() _isLogEnabled;
  final AndroidVideoDiagnosticTimerFactory _createTimer;
  final Duration interval;
  final Duration nativePropertyTimeout;

  final Map<String, Object?> _nativeValues = {};
  final Map<String, _AndroidNativePropertyRead> _nativeReadsInFlight = {};
  final Map<String, Object?> _lastNativeSurfaceFields = {};

  Timer? _timer;
  Future<void>? _sampleInFlight;
  int? _generation;
  String _bindState = 'unknown';
  bool _videoParamsAvailable = false;
  bool _running = false;
  bool _sampling = true;
  bool _closed = false;
  bool _resampleAfterCurrent = false;
  int _runRevision = 0;

  bool get isRunning => _running;

  int? get generation => _generation;

  void setEnabled(bool enabled) {
    if (_closed) return;
    if (!enabled) {
      stop();
      return;
    }
    if (_running) return;

    _running = true;
    _runRevision += 1;
    _generation = _readGeneration();
    _resetGenerationState();
    _timer = _createTimer(interval, (_) => unawaited(sampleNow()));
    _requestImmediateSample();
  }

  void updateGeneration(int generation) {
    if (!_running || _closed || _generation == generation) return;
    _generation = generation;
    // Player teardown advances its playback generation before native unload
    // and dispose. Keep those events associated with the current generation
    // without restarting native reads or the periodic sampler.
    if (!_sampling) return;
    _sampleInFlight = null;
    _resampleAfterCurrent = false;
    _resetGenerationState();
    _requestImmediateSample();
  }

  void onAppResumed() {
    if (!_running || !_sampling || _closed) return;
    final generation = _readGeneration();
    if (_generation != generation) {
      updateGeneration(generation);
      return;
    }
    _requestImmediateSample();
  }

  void recordNativeEvent(
    String event,
    Map<String, Object?> fields, {
    required int generation,
  }) {
    if (!_canWrite || generation != _generation) return;

    final safeEvent = eventNames.contains(event) ? event : 'unknown';
    final safeFields = <String, Object?>{
      for (final entry in fields.entries)
        if (eventFields.contains(entry.key))
          entry.key: _sanitizeEventValue(entry.key, entry.value),
    };

    _lastNativeSurfaceFields.addAll(safeFields);
    if (safeEvent == 'video_params') _videoParamsAvailable = true;
    if (safeEvent == 'bind_start') _bindState = 'binding';
    if (safeEvent == 'bind_complete') {
      final wid = _safeInteger(safeFields['wid']);
      _bindState = wid == null ? 'unknown' : (wid > 0 ? 'bound' : 'unbound');
    }
    if (safeEvent == 'bind_error') _bindState = 'error';
    if (safeEvent == 'unload' || safeEvent == 'dispose') {
      _bindState = 'unbound';
    }

    unawaited(_writeAndFlush(<String, Object?>{
      'event': safeEvent,
      'generation': generation,
      ...safeFields,
    }));
  }

  Future<void> sampleNow() {
    if (!_canSample) return Future<void>.value();
    final activeSample = _sampleInFlight;
    if (activeSample != null) return activeSample;

    final generation = _generation ?? _readGeneration();
    final runRevision = _runRevision;
    final sample = _sample(generation, runRevision);
    _sampleInFlight = sample;
    sample.then<void>(
      (_) => _clearSample(sample),
      onError: (Object _, StackTrace __) => _clearSample(sample),
    );
    return sample;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    _sampling = true;
    _runRevision += 1;
    _resampleAfterCurrent = false;
    // A previous run may still be waiting for its timeout or file flush.
    // It cannot hold up the immediate sample when logging is enabled again.
    _sampleInFlight = null;
    _generation = null;
    _resetGenerationState();
  }

  void dispose() {
    if (_closed) return;
    stop();
    _closed = true;
  }

  /// Stops reads before player teardown, while allowing unload and dispose
  /// callbacks from the native output to reach the log.
  void stopSamplingForClose() {
    _timer?.cancel();
    _timer = null;
    _sampling = false;
    _runRevision += 1;
    _sampleInFlight = null;
    _resampleAfterCurrent = false;
  }

  bool get _canWrite {
    if (!_running || _closed || _generation == null) return false;
    try {
      return _isLogEnabled();
    } catch (_) {
      return false;
    }
  }

  bool get _canSample => _sampling && _canWrite;

  Future<void> _sample(int generation, int runRevision) async {
    final local = _readLocalSafely();
    final nativeReads = <Future<Object?>>[];
    for (final property in nativeProperties) {
      final pending = _nativeReadsInFlight[property];
      if (pending != null) {
        // An old request still blocks another native call for this property,
        // but must not delay the first snapshot for the new generation.
        if (pending.generation == generation &&
            pending.runRevision == runRevision) {
          nativeReads.add(pending.future);
        }
      } else {
        nativeReads.add(
          _startNativeRead(
            property,
            generation: generation,
            runRevision: runRevision,
          ),
        );
      }
    }

    if (nativeReads.isNotEmpty) {
      try {
        await Future.wait(nativeReads).timeout(nativePropertyTimeout);
      } on TimeoutException {
        // The outstanding futures remain registered, preventing duplicate
        // native requests while still allowing this local snapshot to finish.
      } catch (_) {
        // Each property stores unknown independently; diagnostics must not
        // affect playback if a native getter fails.
      }
    }

    if (!_canSample ||
        runRevision != _runRevision ||
        generation != _generation ||
        generation != _readGeneration()) {
      return;
    }

    final fields = <String, Object?>{
      'event': 'snapshot',
      'generation': generation,
      'handle':
          _firstKnown(_lastNativeSurfaceFields['handle'], local['handle']),
      for (final field in localSnapshotFields)
        if (field != 'handle') field: _safeSnapshotValue(field, local[field]),
      'videoParamsAvailable':
          _videoParamsAvailable || local['videoParamsAvailable'] == true,
      'bindState': _bindState,
      // video_params and bind completion do not prove that a user-visible
      // frame reached the display. The current backend has no render signal.
      'renderConfirmed': 'unknown',
      'lastNativeSurfaceIdentity':
          _lastNativeSurfaceFields['surfaceIdentity'] ?? 'unknown',
      'lastNativeBindRevision':
          _lastNativeSurfaceFields['bindRevision'] ?? 'unknown',
      'lastNativeStage': _lastNativeSurfaceFields['stage'] ?? 'unknown',
      'lastNativeBindResult': _lastNativeSurfaceFields['bindResult'] ??
          _lastNativeSurfaceFields['bindingResult'] ??
          'unknown',
      'lastNativeBound': _lastNativeSurfaceFields['bound'] ?? 'unknown',
      'lastNativeRenderConfirmed':
          _lastNativeSurfaceFields['renderConfirmed'] ?? 'unknown',
      'configuredVo': _lastNativeSurfaceFields['vo'] ?? 'unknown',
      'configuredHwdec': _lastNativeSurfaceFields['hwdec'] ?? 'unknown',
      for (final entry in const <String, String>{
        'textureId': 'lastNativeTextureId',
        'oldWid': 'lastNativeOldWid',
        'wid': 'lastNativeWid',
        'width': 'lastNativeWidth',
        'height': 'lastNativeHeight',
        'valid': 'lastNativeValid',
        'reason': 'lastNativeReason',
        'level': 'lastNativeLevel',
        'error': 'lastNativeError',
        'vo': 'configuredVo',
        'hwdec': 'configuredHwdec',
      }.entries)
        if (_lastNativeSurfaceFields.containsKey(entry.key))
          entry.value: _lastNativeSurfaceFields[entry.key],
      for (final property in nativeProperties)
        property: _nativeValues[property] ?? 'unknown',
    };

    await _writeAndFlush(fields);
  }

  Future<Object?> _startNativeRead(
    String property, {
    required int generation,
    required int runRevision,
  }) {
    _nativeValues[property] = 'unknown';
    late final Future<Object?> read;
    read = Future<Object?>.sync(() => _readNativeProperty(property));
    final request = _AndroidNativePropertyRead(
      generation,
      runRevision,
      read,
    );
    _nativeReadsInFlight[property] = request;
    read.then<void>(
      (value) {
        if (!identical(_nativeReadsInFlight[property], request)) return;
        _nativeReadsInFlight.remove(property);
        if (_closed) return;
        if (request.generation != _generation ||
            request.runRevision != _runRevision) {
          return;
        }
        _nativeValues[property] = _sanitizePropertyValue(property, value);
      },
      onError: (Object _, StackTrace __) {
        if (!identical(_nativeReadsInFlight[property], request)) return;
        _nativeReadsInFlight.remove(property);
        if (_closed) return;
        if (request.generation != _generation ||
            request.runRevision != _runRevision) {
          return;
        }
        _nativeValues[property] = 'unknown';
      },
    );
    return read;
  }

  Map<String, Object?> _readLocalSafely() {
    try {
      final source = _readLocalSnapshot();
      return <String, Object?>{
        for (final field in localSnapshotFields)
          if (source.containsKey(field)) field: source[field],
      };
    } catch (_) {
      return <String, Object?>{
        for (final field in localSnapshotFields) field: 'unknown',
      };
    }
  }

  void _requestImmediateSample() {
    final activeSample = _sampleInFlight;
    if (activeSample == null) {
      unawaited(sampleNow());
      return;
    }
    _resampleAfterCurrent = true;
    final requestedGeneration = _generation;
    activeSample.then<void>(
      (_) => _runDeferredSample(requestedGeneration),
      onError: (Object _, StackTrace __) =>
          _runDeferredSample(requestedGeneration),
    );
  }

  void _runDeferredSample(int? requestedGeneration) {
    if (!_resampleAfterCurrent ||
        requestedGeneration == null ||
        requestedGeneration != _generation ||
        !_canWrite) {
      return;
    }
    _resampleAfterCurrent = false;
    unawaited(sampleNow());
  }

  void _clearSample(Future<void> sample) {
    if (identical(_sampleInFlight, sample)) {
      _sampleInFlight = null;
    }
  }

  Future<void> _writeAndFlush(Map<String, Object?> fields) async {
    try {
      _write('[android-video] ${jsonEncode(fields)}');
      await _flush();
    } catch (_) {
      // File logger failures are diagnostic-only and must not affect playback.
    }
  }

  Object? _sanitizeEventValue(String key, Object? value) {
    if (key == 'renderConfirmed') return 'unknown';
    if (const {
      'handle',
      'textureId',
      'surfaceIdentity',
      'bindRevision',
      'oldWid',
      'wid',
      'width',
      'height'
    }.contains(key)) {
      return _safeInteger(value) ?? 'unknown';
    }
    if (const {'valid', 'bound'}.contains(key)) {
      return value is bool ? value : 'unknown';
    }
    if (key == 'error') return _safeErrorType(value);
    if (const {
      'reason',
      'level',
      'vo',
      'hwdec',
      'stage',
      'bindResult',
      'bindingResult',
    }.contains(key)) {
      return _safeToken(value);
    }
    return 'unknown';
  }

  Object _safeSnapshotValue(String key, Object? value) {
    if (key == 'handle' ||
        key == 'textureId' ||
        key == 'wid' ||
        key.endsWith('Width') ||
        key.endsWith('Height') ||
        key == 'videoTrackCount' ||
        key == 'audioTrackCount') {
      return _safeInteger(value) ?? 'unknown';
    }
    if (key == 'playing' ||
        key == 'buffering' ||
        key == 'videoParamsAvailable') {
      return value is bool ? value : 'unknown';
    }
    return 'unknown';
  }

  Object _sanitizePropertyValue(String property, Object? value) {
    if (property == 'wid' || property == 'estimated-vf-fps') {
      if (value is num && value.isFinite) return value;
      final parsed = num.tryParse(value?.toString().trim() ?? '');
      return parsed != null && parsed.isFinite ? parsed : 'unknown';
    }
    return _safeToken(value);
  }

  int? _safeInteger(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String && RegExp(r'^-?\d{1,20}$').hasMatch(value.trim())) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Object _safeToken(Object? value) {
    final token = value?.toString().trim() ?? '';
    if (token.isEmpty ||
        token.length > 64 ||
        !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(token) ||
        token.toLowerCase().contains('http') ||
        token.toLowerCase().contains('cookie') ||
        token.toLowerCase().contains('token') ||
        token.toLowerCase().contains('authorization')) {
      return 'unknown';
    }
    return token;
  }

  Object _safeErrorType(Object? value) {
    final type = value?.toString().trim() ?? '';
    if (type.isEmpty ||
        type.length > 128 ||
        !RegExp(r'^[A-Za-z_$][A-Za-z0-9_$.]*$').hasMatch(type)) {
      return 'unknown';
    }
    return type;
  }

  Object _firstKnown(Object? primary, Object? secondary) {
    final first = _safeInteger(primary);
    if (first != null) return first;
    return _safeInteger(secondary) ?? 'unknown';
  }

  void _resetGenerationState() {
    _nativeValues.clear();
    _lastNativeSurfaceFields.clear();
    _bindState = 'unknown';
    _videoParamsAvailable = false;
  }
}
