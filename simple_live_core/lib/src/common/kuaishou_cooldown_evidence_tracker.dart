/// Tracks consecutive Kuaishou credential-rejection evidence without
/// retaining cookies or other credential material.
///
/// A rejection only becomes actionable after two consecutive observations for
/// the same endpoint and cookie-session epoch. This keeps anonymous permission
/// failures from cooling down unrelated background work.
class KuaishouCooldownEvidenceTracker {
  static const Duration cooldownDuration = Duration(minutes: 2);
  static const Duration rateLimitCooldownDuration = Duration(minutes: 5);
  static const int _cooldownThreshold = 2;

  static const Set<String> _authenticatedCookieNames = {
    'kuaishou.live.web_st',
    'kuaishou.server.web_st',
    'kuaishou.live.web_at',
    'passToken',
  };

  final Map<_EvidenceKey, int> _consecutiveRejections = {};

  /// 429 is explicit server rate limiting and always starts global cooldown.
  static Duration? immediateCooldownForStatus(int statusCode) =>
      statusCode == 429 ? rateLimitCooldownDuration : null;

  /// Matches the auth-cookie fields accepted by the Kuaishou web-login flow.
  /// Device identifiers such as `did` and session helper cookies do not count.
  static bool hasAuthenticatedSession(String cookieHeader) {
    for (final part in cookieHeader.split(';')) {
      final item = part.trim();
      final separator = item.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final name = item.substring(0, separator).trim();
      final value = item.substring(separator + 1).trim();
      if (_authenticatedCookieNames.contains(name) && value.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Records an authenticated 403 or challenge page.
  ///
  /// Returns true only when the consecutive-evidence threshold is reached.
  /// Anonymous and device-only sessions are intentionally classification-only.
  bool recordCredentialRejection({
    required String endpoint,
    required int sessionEpoch,
    required bool hasAuthenticatedSession,
  }) {
    final key = _EvidenceKey(endpoint, sessionEpoch);
    if (!hasAuthenticatedSession) {
      // A device-only response must break a streak collected while an
      // authenticated cookie was present. Otherwise the next login response
      // would be incorrectly treated as consecutive evidence.
      _consecutiveRejections.remove(key);
      return false;
    }
    final count = (_consecutiveRejections[key] ?? 0) + 1;
    _consecutiveRejections[key] = count;
    // Trigger only when the evidence crosses the threshold. Repeated errors
    // during the same incident must not continually extend global cooldown.
    return count == _cooldownThreshold;
  }

  /// A successful response for an endpoint breaks its consecutive streak.
  void recordSuccess({required String endpoint, required int sessionEpoch}) {
    _consecutiveRejections.remove(_EvidenceKey(endpoint, sessionEpoch));
  }

  /// Called when the cookie session changes.
  void reset() => _consecutiveRejections.clear();
}

class _EvidenceKey {
  const _EvidenceKey(this.endpoint, this.sessionEpoch);

  final String endpoint;
  final int sessionEpoch;

  @override
  bool operator ==(Object other) =>
      other is _EvidenceKey &&
      other.endpoint == endpoint &&
      other.sessionEpoch == sessionEpoch;

  @override
  int get hashCode => Object.hash(endpoint, sessionEpoch);
}
