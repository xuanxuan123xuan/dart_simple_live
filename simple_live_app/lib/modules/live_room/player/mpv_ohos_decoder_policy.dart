/// Pure decision logic for the OHOS libmpv hardware-decoder session.
///
/// The policy deliberately does not create a [Timer] or call mpv. The owner
/// applies [MpvOhosDecoderAction] values and calls [onConfirmationTimeout]
/// when its timer fires. Keeping the clock and platform boundary outside this
/// class makes the fallback sequence deterministic in tests.

/// Decoder names understood by the OHOS libmpv build.
enum MpvOhosHwdecMode {
  direct('ohcodec'),
  copy('ohcodec-copy'),
  software('no');

  const MpvOhosHwdecMode(this.mpvValue);

  final String mpvValue;

  static MpvOhosHwdecMode? fromCurrentValue(String value) {
    if (value.contains('ohcodec-copy')) {
      return MpvOhosHwdecMode.copy;
    }
    if (value.contains('ohcodec')) {
      return MpvOhosHwdecMode.direct;
    }
    if (value == 'no') {
      return MpvOhosHwdecMode.software;
    }
    return null;
  }
}

/// The only stream hint consumed by the reference decoder policy.
///
/// The reference player reads `streamHint.highBitDepth` when it resolves the
/// OHCodec mode, but the value only appears in its diagnostic log; it does not
/// select a different mode. Keeping the hint in the snapshot prevents a
/// caller from accidentally turning an unconfirmed HDR/SDR assumption into a
/// decoder switch.
class MpvOhosStreamHint {
  const MpvOhosStreamHint({this.highBitDepth});

  final bool? highBitDepth;
}

/// A command for the mpv/controller integration layer.
enum MpvOhosDecoderActionType {
  setHwdec,
  armConfirmation,
  cancelConfirmation,
  hardwareActive,
  softwareResolved,
}

class MpvOhosDecoderAction {
  const MpvOhosDecoderAction({
    required this.type,
    this.mode,
    this.reason,
    this.delay,
  });

  const MpvOhosDecoderAction.setHwdec(
    MpvOhosHwdecMode mode, {
    String? reason,
  }) : this(
          type: MpvOhosDecoderActionType.setHwdec,
          mode: mode,
          reason: reason,
        );

  const MpvOhosDecoderAction.armConfirmation(Duration delay)
      : this(
          type: MpvOhosDecoderActionType.armConfirmation,
          delay: delay,
        );

  const MpvOhosDecoderAction.cancelConfirmation({String? reason})
      : this(
          type: MpvOhosDecoderActionType.cancelConfirmation,
          reason: reason,
        );

  const MpvOhosDecoderAction.hardwareActive(
    MpvOhosHwdecMode mode, {
    String? reason,
  }) : this(
          type: MpvOhosDecoderActionType.hardwareActive,
          mode: mode,
          reason: reason,
        );

  const MpvOhosDecoderAction.softwareResolved({String? reason})
      : this(
          type: MpvOhosDecoderActionType.softwareResolved,
          mode: MpvOhosHwdecMode.software,
          reason: reason,
        );

  final MpvOhosDecoderActionType type;
  final MpvOhosHwdecMode? mode;
  final String? reason;
  final Duration? delay;

  /// Value to pass to mpv's `hwdec` property for [setHwdec] actions.
  String? get mpvValue => mode?.mpvValue;

  @override
  String toString() {
    return 'MpvOhosDecoderAction(type: $type, mode: $mode, '
        'reason: $reason, delay: $delay)';
  }
}

/// Immutable view of one decoder session.
class MpvOhosDecoderSnapshot {
  const MpvOhosDecoderSnapshot({
    required this.preferredHwdec,
    required this.candidateMode,
    required this.activeMode,
    required this.resolved,
    required this.activationPending,
    required this.upgradeAttempted,
    required this.copyFallbackTried,
    required this.fallenBackToSoftware,
    required this.interopErrors,
    required this.confirmationArmed,
    required this.highBitDepth,
  });

  final bool preferredHwdec;

  /// The cached mode selected for this stream (`ohcodec` or `ohcodec-copy`).
  /// It remains cached after a copy fallback, matching the reference player.
  final MpvOhosHwdecMode? candidateMode;

  /// The latest confirmed `hwdec-current` mode, when mpv has reported one.
  final MpvOhosHwdecMode? activeMode;

  final bool resolved;
  final bool activationPending;
  final bool upgradeAttempted;
  final bool copyFallbackTried;
  final bool fallenBackToSoftware;
  final int interopErrors;
  final bool confirmationArmed;

  /// A hint only; it does not imply HDR support or choose a decoder mode.
  final bool? highBitDepth;

  bool get hardwareActive =>
      activeMode == MpvOhosHwdecMode.direct ||
      activeMode == MpvOhosHwdecMode.copy;

  bool get softwareDecoding => !hardwareActive;

  bool get isHdrHint => highBitDepth == true;

  bool get isSdrHint => highBitDepth == false;

  @override
  String toString() {
    return 'MpvOhosDecoderSnapshot(preferredHwdec: $preferredHwdec, '
        'candidateMode: $candidateMode, activeMode: $activeMode, '
        'resolved: $resolved, activationPending: $activationPending, '
        'upgradeAttempted: $upgradeAttempted, '
        'copyFallbackTried: $copyFallbackTried, '
        'fallenBackToSoftware: $fallenBackToSoftware, '
        'interopErrors: $interopErrors, '
        'confirmationArmed: $confirmationArmed, '
        'highBitDepth: $highBitDepth)';
  }
}

/// Reconstructs the reference MpvPlayer's OHCodec selection and fallback
/// state transitions without depending on Flutter or the native channel.
class MpvOhosDecoderPolicy {
  MpvOhosDecoderPolicy({
    bool preferredHwdec = true,
    this.initialMode = MpvOhosHwdecMode.direct,
    this.confirmationTimeout = const Duration(seconds: 8),
    this.interopErrorLimit = 3,
  }) : _preferredHwdec = preferredHwdec {
    if (initialMode == MpvOhosHwdecMode.software) {
      throw ArgumentError.value(
        initialMode,
        'initialMode',
        'must be direct or copy; use preferredHwdec=false for software',
      );
    }
    if (confirmationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        confirmationTimeout,
        'confirmationTimeout',
        'must be positive',
      );
    }
    if (interopErrorLimit <= 0) {
      throw ArgumentError.value(
        interopErrorLimit,
        'interopErrorLimit',
        'must be positive',
      );
    }
  }

  static const String directInteropFailureText =
      'OHCodec Surface interop failed';
  static const String renderedSurfaceTimeoutText =
      'Timed out waiting for rendered OHCodec Surface buffer';

  final Duration confirmationTimeout;
  final int interopErrorLimit;
  final MpvOhosHwdecMode initialMode;

  bool _preferredHwdec;
  bool _streamStarted = false;
  MpvOhosHwdecMode? _candidateMode;
  MpvOhosHwdecMode? _activeMode;
  bool _resolved = false;
  bool _activationPending = false;
  bool _upgradeAttempted = false;
  bool _copyFallbackTried = false;
  bool _fallenBackToSoftware = false;
  bool _confirmationArmed = false;
  int _interopErrors = 0;
  bool? _highBitDepth;

  bool get preferredHwdec => _preferredHwdec;

  MpvOhosDecoderSnapshot get snapshot => MpvOhosDecoderSnapshot(
        preferredHwdec: _preferredHwdec,
        candidateMode: _candidateMode,
        activeMode: _activeMode,
        resolved: _resolved,
        activationPending: _activationPending,
        upgradeAttempted: _upgradeAttempted,
        copyFallbackTried: _copyFallbackTried,
        fallenBackToSoftware: _fallenBackToSoftware,
        interopErrors: _interopErrors,
        confirmationArmed: _confirmationArmed,
        highBitDepth: _highBitDepth,
      );

  /// Alias useful to integrations that treat the policy as a state machine.
  MpvOhosDecoderSnapshot get state => snapshot;

  /// Starts a new loadfile session and returns the initial `hwdec` command.
  ///
  /// The reference player starts every session with direct `ohcodec` when
  /// hardware decoding is preferred. It does not use [highBitDepth] to choose
  /// `ohcodec-copy`, so both HDR and SDR hints follow the same path here.
  List<MpvOhosDecoderAction> beginStream({
    MpvOhosStreamHint? hint,
    bool? highBitDepth,
    MpvOhosHwdecMode? mode,
  }) {
    _resetSession();
    _streamStarted = true;
    _highBitDepth = highBitDepth ?? hint?.highBitDepth;

    if (!_preferredHwdec) {
      _candidateMode = MpvOhosHwdecMode.software;
      _activeMode = MpvOhosHwdecMode.software;
      _resolved = true;
      return <MpvOhosDecoderAction>[
        const MpvOhosDecoderAction.setHwdec(MpvOhosHwdecMode.software),
        const MpvOhosDecoderAction.softwareResolved(
          reason: 'user-disabled',
        ),
      ];
    }

    _candidateMode = mode ?? initialMode;
    // An explicit `auto-copy` request starts at copy mode. It is already the
    // one allowed copy attempt, so a failed confirmation must go to software
    // instead of trying copy a second time.
    _copyFallbackTried = _candidateMode == MpvOhosHwdecMode.copy;
    _activationPending = true;
    return <MpvOhosDecoderAction>[
      MpvOhosDecoderAction.setHwdec(_candidateMode!),
    ];
  }

  /// Updates the user's preference. During unresolved activation the
  /// reference player defers the property write until the play sequence
  /// confirms or falls back, so this method emits no immediate command then.
  List<MpvOhosDecoderAction> setPreferredHwdec(bool enabled) {
    _preferredHwdec = enabled;
    if (!_streamStarted || _activationPending || !_resolved) {
      return const <MpvOhosDecoderAction>[];
    }

    final mode = enabled ? _resolveCandidateMode() : MpvOhosHwdecMode.software;
    if (enabled) {
      _candidateMode = mode;
      _activeMode = null;
      _fallenBackToSoftware = false;
    } else {
      _activeMode = MpvOhosHwdecMode.software;
    }
    return <MpvOhosDecoderAction>[
      MpvOhosDecoderAction.setHwdec(
        mode,
        reason: enabled ? 'user-enabled' : 'user-disabled',
      ),
    ];
  }

  /// Handles MpvPlayer's FILE_LOADED event, where the direct decoder
  /// confirmation window begins.
  List<MpvOhosDecoderAction> onFileLoaded() {
    if (!_streamStarted || !_activationPending) {
      return const <MpvOhosDecoderAction>[];
    }

    _activationPending = false;
    if (!_preferredHwdec) {
      _candidateMode = MpvOhosHwdecMode.software;
      _activeMode = MpvOhosHwdecMode.software;
      _resolved = true;
      return <MpvOhosDecoderAction>[
        const MpvOhosDecoderAction.setHwdec(MpvOhosHwdecMode.software,
            reason: 'user-disabled-before-confirmation'),
        const MpvOhosDecoderAction.softwareResolved(
          reason: 'user-disabled-before-confirmation',
        ),
      ];
    }

    _upgradeAttempted = true;
    _resolved = false;
    _activeMode = null;
    _confirmationArmed = true;
    return <MpvOhosDecoderAction>[
      MpvOhosDecoderAction.armConfirmation(confirmationTimeout),
    ];
  }

  /// Handles the observed `hwdec-current` property.
  ///
  /// The reference checks for the substring `ohcodec`, so values such as
  /// `ohcodec-copy` are hardware confirmations too. Only the exact `no`
  /// value enters the software/fallback branch.
  List<MpvOhosDecoderAction> onHwdecCurrent(String value) {
    if (!_streamStarted) {
      return const <MpvOhosDecoderAction>[];
    }

    final observed = MpvOhosHwdecMode.fromCurrentValue(value);
    if (observed == null) {
      return const <MpvOhosDecoderAction>[];
    }

    if (observed == MpvOhosHwdecMode.direct ||
        observed == MpvOhosHwdecMode.copy) {
      _activeMode = observed;
      _resolved = true;
      _activationPending = false;
      _fallenBackToSoftware = false;
      final actions = <MpvOhosDecoderAction>[];
      if (_confirmationArmed) {
        _confirmationArmed = false;
        actions.add(const MpvOhosDecoderAction.cancelConfirmation(
            reason: 'hwdec-current'));
      }
      actions.add(MpvOhosDecoderAction.hardwareActive(
        observed,
        reason: 'hwdec-current',
      ));
      return actions;
    }

    _activeMode = MpvOhosHwdecMode.software;
    // A transient `no` before FILE_LOADED is the initial mpv state. The
    // reference intentionally waits for confirmation rather than falling
    // back immediately in that window.
    if (_activationPending && !_upgradeAttempted) {
      return const <MpvOhosDecoderAction>[];
    }

    if (!_preferredHwdec) {
      _resolved = true;
      _fallenBackToSoftware = false;
      _activationPending = false;
      return <MpvOhosDecoderAction>[
        const MpvOhosDecoderAction.softwareResolved(
          reason: 'hwdec-current=no',
        ),
      ];
    }

    // The reference only treats this as a direct failure while its
    // confirmation timer is still live. A stale property event after the
    // timer was cleared must not restart the fallback sequence.
    if (_upgradeAttempted && !_fallenBackToSoftware && _confirmationArmed) {
      if (_copyFallbackTried) {
        return _lockSoftware('copy-fallback-current=no');
      }
      return _tryCopyFallback('hwdec-current=no');
    }
    return const <MpvOhosDecoderAction>[];
  }

  /// Counts only the two exact OHCodec/Surface interop messages observed in
  /// the reference log watcher. The third matching message starts copy mode.
  List<MpvOhosDecoderAction> onMpvLog(String text) {
    if (!_streamStarted ||
        _candidateMode != MpvOhosHwdecMode.direct ||
        _copyFallbackTried) {
      return const <MpvOhosDecoderAction>[];
    }
    if (!text.contains(directInteropFailureText) &&
        !text.contains(renderedSurfaceTimeoutText)) {
      return const <MpvOhosDecoderAction>[];
    }

    _interopErrors += 1;
    if (_interopErrors < interopErrorLimit) {
      return const <MpvOhosDecoderAction>[];
    }
    return _tryCopyFallback('vo-interop-error');
  }

  /// Called by the owner when the current confirmation timer expires.
  List<MpvOhosDecoderAction> onConfirmationTimeout() {
    if (!_streamStarted || !_confirmationArmed) {
      return const <MpvOhosDecoderAction>[];
    }
    _confirmationArmed = false;
    if (_resolved) {
      return const <MpvOhosDecoderAction>[];
    }
    if (!_preferredHwdec) {
      _candidateMode = MpvOhosHwdecMode.software;
      _activeMode = MpvOhosHwdecMode.software;
      _resolved = true;
      _fallenBackToSoftware = false;
      return <MpvOhosDecoderAction>[
        const MpvOhosDecoderAction.setHwdec(MpvOhosHwdecMode.software,
            reason: 'pref-switched-soft'),
        const MpvOhosDecoderAction.softwareResolved(
          reason: 'pref-switched-soft',
        ),
      ];
    }

    if (!_copyFallbackTried) {
      return _tryCopyFallback('upgrade-timeout');
    }
    return _lockSoftware('copy-fallback-timeout-after-upgrade-timeout');
  }

  /// Clears the current stream state. The next [beginStream] starts direct
  /// mode again when hardware decoding is preferred.
  List<MpvOhosDecoderAction> reset() {
    _resetSession();
    _streamStarted = false;
    return const <MpvOhosDecoderAction>[];
  }

  MpvOhosHwdecMode _resolveCandidateMode() {
    return _candidateMode == MpvOhosHwdecMode.copy
        ? MpvOhosHwdecMode.copy
        : MpvOhosHwdecMode.direct;
  }

  List<MpvOhosDecoderAction> _tryCopyFallback(String reason) {
    if (_copyFallbackTried || _candidateMode != MpvOhosHwdecMode.direct) {
      return const <MpvOhosDecoderAction>[];
    }

    _copyFallbackTried = true;
    _candidateMode = MpvOhosHwdecMode.copy;
    _upgradeAttempted = true;
    _resolved = false;
    _activeMode = null;
    _fallenBackToSoftware = false;

    final actions = <MpvOhosDecoderAction>[];
    if (_confirmationArmed) {
      _confirmationArmed = false;
      actions.add(MpvOhosDecoderAction.cancelConfirmation(reason: reason));
    }
    actions.add(MpvOhosDecoderAction.setHwdec(
      MpvOhosHwdecMode.copy,
      reason: reason,
    ));
    _confirmationArmed = true;
    actions.add(MpvOhosDecoderAction.armConfirmation(confirmationTimeout));
    return actions;
  }

  List<MpvOhosDecoderAction> _lockSoftware(String reason) {
    _confirmationArmed = false;
    _activationPending = false;
    _fallenBackToSoftware = true;
    _resolved = true;
    _activeMode = MpvOhosHwdecMode.software;
    return <MpvOhosDecoderAction>[
      MpvOhosDecoderAction.setHwdec(
        MpvOhosHwdecMode.software,
        reason: reason,
      ),
      MpvOhosDecoderAction.softwareResolved(reason: reason),
    ];
  }

  void _resetSession() {
    _candidateMode = null;
    _activeMode = null;
    _resolved = false;
    _activationPending = false;
    _upgradeAttempted = false;
    _copyFallbackTried = false;
    _fallenBackToSoftware = false;
    _confirmationArmed = false;
    _interopErrors = 0;
    _highBitDepth = null;
  }
}
