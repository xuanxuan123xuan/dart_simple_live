import 'dart:convert';

import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';

enum KuaishouAccountSlot { primary, secondary }

enum KuaishouCredentialState { unknown, valid, invalid }

enum KuaishouAccountPoolMode { primary, secondary, anonymous }

class KuaishouAccountSession {
  KuaishouAccountSession(this.slot);

  final KuaishouAccountSlot slot;
  String cookie = '';
  String kww = '';
  DateTime? cookieExpiresAt;
  DateTime? loggedInAt;
  DateTime? lastValidatedAt;
  KuaishouCredentialState credentialState = KuaishouCredentialState.unknown;
  DateTime? cooldownUntil;
  DateTime? suspendedUntil;
  String? suspendedReason;

  bool get isConfigured => cookie.trim().isNotEmpty;

  bool isAvailable(DateTime now) {
    if (!isConfigured || credentialState == KuaishouCredentialState.invalid) {
      return false;
    }
    if (suspendedUntil?.isAfter(now) == true ||
        cooldownUntil?.isAfter(now) == true) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toStateJson() => {
    'credentialState': credentialState.name,
    'loggedInAt': loggedInAt?.millisecondsSinceEpoch,
    'lastValidatedAt': lastValidatedAt?.millisecondsSinceEpoch,
    'cooldownUntil': cooldownUntil?.millisecondsSinceEpoch,
    'suspendedUntil': suspendedUntil?.millisecondsSinceEpoch,
    'suspendedReason': suspendedReason,
  };

  Map<String, dynamic> toBackupJson() => {
    'cookie': cookie,
    'kww': kww,
    'cookieExpiresAt': cookieExpiresAt?.millisecondsSinceEpoch ?? 0,
    'state': toStateJson(),
  };

  void restoreState(dynamic raw) {
    if (raw is! Map) return;

    DateTime? readDate(String key) {
      final value = raw[key];
      final millis = value is num ? value.toInt() : int.tryParse('$value');
      return millis == null || millis <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    }

    credentialState = KuaishouCredentialState.values.firstWhere(
      (value) => value.name == raw['credentialState'],
      orElse: () => KuaishouCredentialState.unknown,
    );
    loggedInAt = readDate('loggedInAt');
    lastValidatedAt = readDate('lastValidatedAt');
    cooldownUntil = readDate('cooldownUntil');
    suspendedUntil = readDate('suspendedUntil');
    suspendedReason = raw['suspendedReason']?.toString();
  }

  void replaceCredential({
    required String cookie,
    required String kww,
    DateTime? expiresAt,
    DateTime? now,
  }) {
    this.cookie = cookie;
    this.kww = kww;
    cookieExpiresAt = expiresAt;
    loggedInAt = cookie.isEmpty ? null : (now ?? DateTime.now());
    lastValidatedAt = null;
    credentialState = KuaishouCredentialState.unknown;
    cooldownUntil = null;
    suspendedUntil = null;
    suspendedReason = null;
  }

  void restoreBackup(dynamic raw) {
    if (raw is! Map) {
      replaceCredential(cookie: '', kww: '');
      return;
    }
    final expiryValue = raw['cookieExpiresAt'];
    final expiryMs = expiryValue is num
        ? expiryValue.toInt()
        : int.tryParse(expiryValue?.toString() ?? '') ?? 0;
    cookie = raw['cookie']?.toString() ?? '';
    kww = raw['kww']?.toString() ?? '';
    cookieExpiresAt = expiryMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(expiryMs)
        : resolveKuaishouEmbeddedTokenExpiry(cookie);
    credentialState = KuaishouCredentialState.unknown;
    loggedInAt = null;
    lastValidatedAt = null;
    cooldownUntil = null;
    suspendedUntil = null;
    suspendedReason = null;
    restoreState(raw['state']);
  }
}

class KuaishouAccountService extends GetxService {
  static KuaishouAccountService get instance =>
      Get.find<KuaishouAccountService>();

  static const Duration followRateLimitCooldown = Duration(minutes: 5);
  static const Duration followChallengeCooldown = Duration(minutes: 2);

  final primary = KuaishouAccountSession(KuaishouAccountSlot.primary);
  final secondary = KuaishouAccountSession(KuaishouAccountSlot.secondary);
  final mode = KuaishouAccountPoolMode.primary.obs;
  final revision = 0.obs;

  KuaishouAccountSession? get activeSession => switch (mode.value) {
    KuaishouAccountPoolMode.primary => primary,
    KuaishouAccountPoolMode.secondary => secondary,
    KuaishouAccountPoolMode.anonymous => null,
  };

  @override
  void onInit() {
    final storage = LocalStorageService.instance;
    primary.cookie = storage.getValue(LocalStorageService.kKuaishouCookie, '');
    primary.kww = storage.getValue(LocalStorageService.kKuaishouKww, '');
    final primaryExpiry = storage.getValue(
      LocalStorageService.kKuaishouCookieExpiresAt,
      0,
    );
    primary.cookieExpiresAt = primaryExpiry > 0
        ? DateTime.fromMillisecondsSinceEpoch(primaryExpiry)
        : resolveKuaishouEmbeddedTokenExpiry(primary.cookie);

    secondary.cookie = storage.getValue(
      LocalStorageService.kKuaishouSecondaryCookie,
      '',
    );
    secondary.kww = storage.getValue(
      LocalStorageService.kKuaishouSecondaryKww,
      '',
    );
    final secondaryExpiry = storage.getValue(
      LocalStorageService.kKuaishouSecondaryCookieExpiresAt,
      0,
    );
    secondary.cookieExpiresAt = secondaryExpiry > 0
        ? DateTime.fromMillisecondsSinceEpoch(secondaryExpiry)
        : resolveKuaishouEmbeddedTokenExpiry(secondary.cookie);

    final state = storage.getValue<dynamic>(
      LocalStorageService.kKuaishouAccountPoolState,
      const <String, dynamic>{},
    );
    if (state is Map) {
      primary.restoreState(state['primary']);
      secondary.restoreState(state['secondary']);
      mode.value = KuaishouAccountPoolMode.values.firstWhere(
        (value) => value.name == state['mode'],
        orElse: () => KuaishouAccountPoolMode.primary,
      );
    }
    refreshAvailability();
    setSite();
    _notifyChanged();
    super.onInit();
  }

  void setSite() {
    refreshAvailability();
    final liveSite = Sites.allSites[Constant.kKuaishou]?.liveSite;
    if (liveSite is! KuaishouSite) return;

    liveSite.onAccountHealthEvent = null;
    liveSite.onAccountSessionHealthEvent = _handleSiteHealthEvent;
    liveSite.accountFallbackProvider = _provideFallbackSession;
    final active = activeSession;
    if (active == null) {
      liveSite.activateAnonymousMode();
    } else {
      liveSite.activateAccountSession(
        sessionKey: active.slot.name,
        cookie: active.cookie,
        kww: active.kww,
      );
    }
  }

  KuaishouAccountFallbackSession? _provideFallbackSession(
    String attemptedSessionKey,
  ) {
    refreshAvailability();
    final attempted = KuaishouAccountSlot.values.firstWhereOrNull(
      (slot) => slot.name == attemptedSessionKey,
    );
    final candidates = attempted == KuaishouAccountSlot.primary
        ? [secondary]
        : attempted == KuaishouAccountSlot.secondary
        ? [primary]
        : [primary, secondary];
    final now = DateTime.now();
    for (final candidate in candidates) {
      if (!candidate.isAvailable(now)) continue;
      return KuaishouAccountFallbackSession(
        sessionKey: candidate.slot.name,
        cookie: candidate.cookie,
        kww: candidate.kww,
      );
    }
    return null;
  }

  KuaishouAccountSession sessionFor(KuaishouAccountSlot slot) =>
      slot == KuaishouAccountSlot.primary ? primary : secondary;

  bool setCookieForSlot(
    KuaishouAccountSlot slot,
    String cookie, {
    String? kww,
    DateTime? expiresAt,
  }) {
    final target = sessionFor(slot);
    final other = sessionFor(
      slot == KuaishouAccountSlot.primary
          ? KuaishouAccountSlot.secondary
          : KuaishouAccountSlot.primary,
    );
    if (cookie.trim().isNotEmpty && other.isConfigured) {
      if (normalizeKuaishouCookie(cookie) ==
          normalizeKuaishouCookie(other.cookie)) {
        return false;
      }
      final uid = extractKuaishouAccountUid(cookie);
      final otherUid = extractKuaishouAccountUid(other.cookie);
      if (uid != null && otherUid != null && uid == otherUid) {
        return false;
      }
    }
    target.replaceCredential(
      cookie: cookie.trim(),
      kww: kww ?? target.kww,
      expiresAt: expiresAt ?? resolveKuaishouEmbeddedTokenExpiry(cookie),
    );
    _selectBestAvailable();
    _persistAndApply();
    return true;
  }

  void clearCookieForSlot(KuaishouAccountSlot slot) {
    sessionFor(slot).replaceCredential(cookie: '', kww: '');
    _selectBestAvailable();
    _persistAndApply();
  }

  Map<String, dynamic> exportBackupMap() => {
    'version': 1,
    'mode': mode.value.name,
    'slots': {
      'primary': primary.toBackupJson(),
      'secondary': secondary.toBackupJson(),
    },
  };

  void importBackupMap(dynamic raw, {dynamic legacySettings}) {
    final backup = migrateKuaishouAccountBackup(
      raw,
      legacySettings: legacySettings,
    );
    final slots = backup['slots'];
    if (slots is Map) {
      primary.restoreBackup(slots['primary']);
      secondary.restoreBackup(slots['secondary']);
    }
    if (_isSameAccount(primary, secondary)) {
      secondary.replaceCredential(cookie: '', kww: '');
    }
    final restoredMode = KuaishouAccountPoolMode.values.firstWhere(
      (value) => value.name == backup['mode'],
      orElse: () => KuaishouAccountPoolMode.primary,
    );
    final now = DateTime.now();
    mode.value = switch (restoredMode) {
      KuaishouAccountPoolMode.primary when primary.isAvailable(now) =>
        KuaishouAccountPoolMode.primary,
      KuaishouAccountPoolMode.secondary when secondary.isAvailable(now) =>
        KuaishouAccountPoolMode.secondary,
      KuaishouAccountPoolMode.anonymous => KuaishouAccountPoolMode.anonymous,
      _ when primary.isAvailable(now) => KuaishouAccountPoolMode.primary,
      _ when secondary.isAvailable(now) => KuaishouAccountPoolMode.secondary,
      _ => KuaishouAccountPoolMode.anonymous,
    };
    _persistAndApply();
  }

  bool failoverFollowBatch({
    required String attemptedSessionKey,
    required int statusCode,
    DateTime? now,
  }) {
    final slot = KuaishouAccountSlot.values.firstWhereOrNull(
      (value) => value.name == attemptedSessionKey,
    );
    if (slot == null) return false;

    final current = now ?? DateTime.now();
    final session = sessionFor(slot);
    if (statusCode == 401 || statusCode == 403) {
      session.credentialState = KuaishouCredentialState.invalid;
      session.suspendedReason = 'credentialInvalid';
    } else {
      final duration = statusCode == 429
          ? followRateLimitCooldown
          : followChallengeCooldown;
      final nextCooldown = current.add(duration);
      if (session.cooldownUntil?.isAfter(nextCooldown) != true) {
        session.cooldownUntil = nextCooldown;
      }
      session.suspendedReason = statusCode == 429
          ? 'rateLimited'
          : 'securityChallenge';
    }
    _selectBestAvailable(current);
    _persistAndApply();

    final fallback = activeSession;
    return fallback != null &&
        fallback.slot != slot &&
        fallback.isAvailable(current);
  }

  void refreshAvailability([DateTime? now]) {
    final current = now ?? DateTime.now();
    var recovered = false;
    for (final session in [primary, secondary]) {
      if (session.suspendedUntil?.isAfter(current) == false) {
        recovered = recovered || session.suspendedUntil != null;
        session.suspendedUntil = null;
        session.suspendedReason = null;
      }
      if (session.cooldownUntil?.isAfter(current) == false) {
        recovered = recovered || session.cooldownUntil != null;
        session.cooldownUntil = null;
      }
    }
    final previousMode = mode.value;
    if (activeSession?.isAvailable(current) != true || recovered) {
      _selectBestAvailable(current);
    }
    if (recovered || previousMode != mode.value) {
      _persist();
      _notifyChanged();
    }
  }

  void _handleSiteHealthEvent(
    String sessionKey,
    KuaishouAccountHealthEvent event,
  ) {
    final slot = KuaishouAccountSlot.values.firstWhereOrNull(
      (value) => value.name == sessionKey,
    );
    if (slot == null) return;
    final session = sessionFor(slot);
    switch (event) {
      case KuaishouAccountHealthEvent.rateLimited:
      case KuaishouAccountHealthEvent.securityChallenge:
        session.suspendedUntil = nextShanghaiMidnight(DateTime.now());
        session.suspendedReason = event.name;
        break;
      case KuaishouAccountHealthEvent.credentialInvalid:
        session.credentialState = KuaishouCredentialState.invalid;
        session.suspendedReason = event.name;
        break;
    }
    _selectBestAvailable();
    _persistAndApply();
  }

  void _selectBestAvailable([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (primary.isAvailable(current)) {
      mode.value = KuaishouAccountPoolMode.primary;
    } else if (secondary.isAvailable(current)) {
      mode.value = KuaishouAccountPoolMode.secondary;
    } else {
      mode.value = KuaishouAccountPoolMode.anonymous;
    }
  }

  void _persistAndApply() {
    _persist();
    _notifyChanged();
    setSite();
  }

  void _notifyChanged() => revision.value++;

  void _persist() {
    final storage = LocalStorageService.instance;
    storage.setValue(LocalStorageService.kKuaishouCookie, primary.cookie);
    storage.setValue(LocalStorageService.kKuaishouKww, primary.kww);
    storage.setValue(
      LocalStorageService.kKuaishouCookieExpiresAt,
      primary.cookieExpiresAt?.millisecondsSinceEpoch ?? 0,
    );
    storage.setValue(
      LocalStorageService.kKuaishouSecondaryCookie,
      secondary.cookie,
    );
    storage.setValue(LocalStorageService.kKuaishouSecondaryKww, secondary.kww);
    storage.setValue(
      LocalStorageService.kKuaishouSecondaryCookieExpiresAt,
      secondary.cookieExpiresAt?.millisecondsSinceEpoch ?? 0,
    );
    storage.setValue(LocalStorageService.kKuaishouAccountPoolState, {
      'mode': mode.value.name,
      'primary': primary.toStateJson(),
      'secondary': secondary.toStateJson(),
    });
  }
}

bool _isSameAccount(
  KuaishouAccountSession primary,
  KuaishouAccountSession secondary,
) {
  if (!primary.isConfigured || !secondary.isConfigured) return false;
  if (normalizeKuaishouCookie(primary.cookie) ==
      normalizeKuaishouCookie(secondary.cookie)) {
    return true;
  }
  final primaryUid = extractKuaishouAccountUid(primary.cookie);
  final secondaryUid = extractKuaishouAccountUid(secondary.cookie);
  return primaryUid != null &&
      secondaryUid != null &&
      primaryUid == secondaryUid;
}

DateTime nextShanghaiMidnight(DateTime now) {
  final shanghai = now.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(
    shanghai.year,
    shanghai.month,
    shanghai.day + 1,
  ).subtract(const Duration(hours: 8)).toLocal();
}

String normalizeKuaishouCookie(String cookie) {
  final parts =
      cookie
          .split(';')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList()
        ..sort();
  return parts.join(';');
}

String? extractKuaishouAccountUid(String cookie) {
  final values = <String, String>{};
  for (final part in cookie.split(';')) {
    final item = part.trim();
    final index = item.indexOf('=');
    if (index <= 0) continue;
    values[item.substring(0, index).trim().toLowerCase()] = item
        .substring(index + 1)
        .trim();
  }
  for (final name in const ['userId', 'user_id', 'uid', 'kuaishou.user.id']) {
    final value = values[name.toLowerCase()];
    if (value != null && RegExp(r'^[A-Za-z0-9_-]{4,64}$').hasMatch(value)) {
      return value;
    }
  }
  return null;
}

Map<String, dynamic> migrateKuaishouAccountBackup(
  dynamic raw, {
  dynamic legacySettings,
}) {
  final source = raw is Map ? raw : const <String, dynamic>{};
  final explicitSlots = source['slots'];
  if (explicitSlots is Map) {
    return {
      'version': 1,
      'mode': source['mode']?.toString() ?? 'primary',
      'slots': {
        'primary': _copyKuaishouSlotBackup(explicitSlots['primary']),
        'secondary': _copyKuaishouSlotBackup(explicitSlots['secondary']),
      },
    };
  }

  final settings = legacySettings is Map
      ? legacySettings
      : const <String, dynamic>{};
  final poolState = settings[LocalStorageService.kKuaishouAccountPoolState];
  final state = poolState is Map ? poolState : const <String, dynamic>{};
  return {
    'version': 1,
    'mode': state['mode']?.toString() ?? 'primary',
    'slots': {
      'primary': {
        'cookie': source['cookie']?.toString() ?? '',
        'kww': source['kww']?.toString() ?? '',
        'cookieExpiresAt': source['cookieExpiresAt'] ?? 0,
        'state': state['primary'],
      },
      'secondary': {
        'cookie':
            settings[LocalStorageService.kKuaishouSecondaryCookie]
                ?.toString() ??
            '',
        'kww':
            settings[LocalStorageService.kKuaishouSecondaryKww]?.toString() ??
            '',
        'cookieExpiresAt':
            settings[LocalStorageService.kKuaishouSecondaryCookieExpiresAt] ??
            0,
        'state': state['secondary'],
      },
    },
  };
}

Map<String, dynamic> _copyKuaishouSlotBackup(dynamic raw) {
  if (raw is! Map) {
    return const {'cookie': '', 'kww': '', 'cookieExpiresAt': 0, 'state': null};
  }
  return {
    'cookie': raw['cookie']?.toString() ?? '',
    'kww': raw['kww']?.toString() ?? '',
    'cookieExpiresAt': raw['cookieExpiresAt'] ?? 0,
    'state': raw['state'],
  };
}

DateTime? resolveKuaishouEmbeddedTokenExpiry(String cookie) {
  final values = <String, String>{};
  for (final part in cookie.split(';')) {
    final item = part.trim();
    final index = item.indexOf('=');
    if (index <= 0) continue;
    values[item.substring(0, index).trim()] = item.substring(index + 1).trim();
  }
  for (final name in const [
    'kuaishou.live.web_st',
    'kuaishou.server.web_st',
    'kuaishou.live.web_at',
    'passToken',
  ]) {
    final expiry = _decodeTokenExpiry(values[name] ?? '');
    if (expiry != null) return expiry;
  }
  return null;
}

DateTime? _decodeTokenExpiry(String rawToken) {
  if (rawToken.isEmpty) return null;
  String token;
  try {
    token = Uri.decodeComponent(rawToken);
  } catch (_) {
    token = rawToken;
  }
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    final rawExpiry =
        payload['exp'] ??
        payload['expiresAt'] ??
        payload['expireAt'] ??
        payload['expiration'];
    final numericExpiry = rawExpiry is num
        ? rawExpiry.toInt()
        : int.tryParse(rawExpiry?.toString() ?? '');
    if (numericExpiry == null || numericExpiry <= 0) return null;
    final milliseconds = numericExpiry < 100000000000
        ? numericExpiry * 1000
        : numericExpiry;
    final expiry = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return expiry.year < 2020 || expiry.year > 2200 ? null : expiry;
  } catch (_) {
    return null;
  }
}
