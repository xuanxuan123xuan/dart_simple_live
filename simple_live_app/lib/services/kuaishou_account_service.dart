import 'dart:convert';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

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

  final primary = KuaishouAccountSession(KuaishouAccountSlot.primary);
  final secondary = KuaishouAccountSession(KuaishouAccountSlot.secondary);
  final mode = KuaishouAccountPoolMode.primary.obs;
  final hasCookie = false.obs;
  final cookieExpiresAtMs = 0.obs;
  final revision = 0.obs;

  String get cookie => primary.cookie;
  String get kww => primary.kww;
  DateTime? get cookieExpiresAt => primary.cookieExpiresAt;
  KuaishouAccountSession? get activeSession => switch (mode.value) {
        KuaishouAccountPoolMode.primary => primary,
        KuaishouAccountPoolMode.secondary => secondary,
        KuaishouAccountPoolMode.anonymous => null,
      };

  @override
  void onInit() {
    primary.cookie = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouCookie,
      '',
    );
    primary.kww = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouKww,
      '',
    );
    final primaryExpiry = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouCookieExpiresAt,
      0,
    );
    primary.cookieExpiresAt = primaryExpiry > 0
        ? DateTime.fromMillisecondsSinceEpoch(primaryExpiry)
        : null;
    secondary.cookie = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouSecondaryCookie,
      '',
    );
    secondary.kww = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouSecondaryKww,
      '',
    );
    final secondaryExpiry = LocalStorageService.instance.getValue(
      LocalStorageService.kKuaishouSecondaryCookieExpiresAt,
      0,
    );
    secondary.cookieExpiresAt = secondaryExpiry > 0
        ? DateTime.fromMillisecondsSinceEpoch(secondaryExpiry)
        : null;
    final state = LocalStorageService.instance.getValue<dynamic>(
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
    _syncLegacyObservables();
    setSite();
    super.onInit();
  }

  void setSite() {
    refreshAvailability();
    final site = Sites.allSites[Constant.kKuaishou]?.liveSite;
    if (site is KuaishouSite) {
      final active = activeSession;
      site.onAccountHealthEvent = null;
      site.onAccountSessionHealthEvent = _handleSiteHealthEvent;
      site.accountFallbackProvider = _provideFallbackSession;
      if (active == null) {
        site.activateAnonymousMode();
      } else {
        site.activateAccountSession(
          sessionKey: active.slot.name,
          cookie: active.cookie,
          kww: active.kww,
        );
      }
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

  void setCookie(String cookie, {String? kww, DateTime? expiresAt}) {
    setCookieForSlot(
      KuaishouAccountSlot.primary,
      cookie,
      kww: kww,
      expiresAt: expiresAt,
    );
  }

  bool setCookieForSlot(
    KuaishouAccountSlot slot,
    String cookie, {
    String? kww,
    DateTime? expiresAt,
  }) {
    final target = sessionFor(slot);
    final other = sessionFor(slot == KuaishouAccountSlot.primary
        ? KuaishouAccountSlot.secondary
        : KuaishouAccountSlot.primary);
    if (cookie.trim().isNotEmpty && other.isConfigured) {
      final normalizedCookie = normalizeKuaishouCookie(cookie);
      if (normalizedCookie == normalizeKuaishouCookie(other.cookie)) {
        return false;
      }
      final uid = extractKuaishouAccountUid(cookie);
      final otherUid = extractKuaishouAccountUid(other.cookie);
      if (uid != null && otherUid != null && uid == otherUid) {
        return false;
      }
    }
    target.replaceCredential(
      cookie: cookie,
      kww: kww ?? target.kww,
      expiresAt: expiresAt ?? resolveKuaishouEmbeddedTokenExpiry(cookie),
    );
    mode.value = primary.isAvailable(DateTime.now())
        ? KuaishouAccountPoolMode.primary
        : secondary.isAvailable(DateTime.now())
            ? KuaishouAccountPoolMode.secondary
            : KuaishouAccountPoolMode.anonymous;
    _persist();
    _syncLegacyObservables();
    setSite();
    return true;
  }

  void clearCookie() => clearCookieForSlot(KuaishouAccountSlot.primary);

  void clearCookieForSlot(KuaishouAccountSlot slot) {
    sessionFor(slot).replaceCredential(cookie: '', kww: '');
    if ((slot == KuaishouAccountSlot.primary &&
            mode.value == KuaishouAccountPoolMode.primary) ||
        (slot == KuaishouAccountSlot.secondary &&
            mode.value == KuaishouAccountPoolMode.secondary)) {
      _degradeFrom(slot);
    }
    _persist();
    _syncLegacyObservables();
    setSite();
  }

  KuaishouAccountSession sessionFor(KuaishouAccountSlot slot) =>
      slot == KuaishouAccountSlot.primary ? primary : secondary;

  Map<String, dynamic> exportBackupMap() => {
        'version': 1,
        'mode': mode.value.name,
        'slots': {
          'primary': primary.toBackupJson(),
          'secondary': secondary.toBackupJson(),
        },
      };

  void importBackupMap(
    dynamic raw, {
    dynamic legacySettings,
  }) {
    final backup = migrateKuaishouAccountBackup(
      raw,
      legacySettings: legacySettings,
    );
    final slots = backup['slots'];
    if (slots is Map) {
      primary.restoreBackup(slots['primary']);
      secondary.restoreBackup(slots['secondary']);
    }
    if (primary.isConfigured && secondary.isConfigured) {
      final sameCookie = normalizeKuaishouCookie(primary.cookie) ==
          normalizeKuaishouCookie(secondary.cookie);
      final primaryUid = extractKuaishouAccountUid(primary.cookie);
      final secondaryUid = extractKuaishouAccountUid(secondary.cookie);
      if (sameCookie ||
          (primaryUid != null &&
              secondaryUid != null &&
              primaryUid == secondaryUid)) {
        secondary.replaceCredential(cookie: '', kww: '');
      }
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
    _persist();
    _syncLegacyObservables();
    setSite();
  }

  void markCurrentInvalid() {
    final current = activeSession;
    if (current == null) return;
    markInvalid(current.slot);
  }

  void markInvalid(KuaishouAccountSlot slot) {
    final session = sessionFor(slot);
    session.credentialState = KuaishouCredentialState.invalid;
    if (_isSlotActive(slot)) {
      _degradeFrom(slot);
    }
    _persist();
    _syncLegacyObservables();
    setSite();
  }

  void suspendCurrentForDay({required String reason, DateTime? now}) {
    final current = activeSession;
    if (current == null) return;
    suspendForDay(current.slot, reason: reason, now: now);
  }

  void suspendForDay(
    KuaishouAccountSlot slot, {
    required String reason,
    DateTime? now,
  }) {
    final session = sessionFor(slot);
    session.suspendedUntil = nextShanghaiMidnight(now ?? DateTime.now());
    session.suspendedReason = reason;
    if (_isSlotActive(slot)) {
      _degradeFrom(slot);
    }
    _persist();
    _syncLegacyObservables();
    setSite();
  }

  void refreshAvailability([DateTime? now]) {
    final current = now ?? DateTime.now();
    final previousMode = mode.value;
    var recovered = false;
    for (final session in [primary, secondary]) {
      if (session.suspendedUntil?.isAfter(current) == false) {
        recovered = recovered || session.suspendedUntil != null;
        session.suspendedUntil = null;
        session.suspendedReason = null;
      }
      if (session.cooldownUntil?.isAfter(current) == false) {
        session.cooldownUntil = null;
      }
    }
    if (recovered) {
      mode.value = primary.isAvailable(current)
          ? KuaishouAccountPoolMode.primary
          : secondary.isAvailable(current)
              ? KuaishouAccountPoolMode.secondary
              : KuaishouAccountPoolMode.anonymous;
      _persist();
    } else if (activeSession?.isAvailable(current) != true) {
      if (mode.value == KuaishouAccountPoolMode.primary) {
        _degradeFrom(KuaishouAccountSlot.primary);
      } else if (mode.value == KuaishouAccountPoolMode.secondary) {
        _degradeFrom(KuaishouAccountSlot.secondary);
      } else if (primary.isAvailable(current)) {
        mode.value = KuaishouAccountPoolMode.primary;
      } else if (secondary.isAvailable(current)) {
        mode.value = KuaishouAccountPoolMode.secondary;
      }
    }
    if (!recovered && mode.value != previousMode) {
      _persist();
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
    switch (event) {
      case KuaishouAccountHealthEvent.rateLimited:
      case KuaishouAccountHealthEvent.securityChallenge:
        suspendForDay(slot, reason: event.name);
        return;
      case KuaishouAccountHealthEvent.credentialInvalid:
        markInvalid(slot);
        return;
    }
  }

  bool _isSlotActive(KuaishouAccountSlot slot) =>
      (slot == KuaishouAccountSlot.primary &&
          mode.value == KuaishouAccountPoolMode.primary) ||
      (slot == KuaishouAccountSlot.secondary &&
          mode.value == KuaishouAccountPoolMode.secondary);

  void _degradeFrom(KuaishouAccountSlot slot) {
    mode.value = degradeKuaishouMode(
      current: slot == KuaishouAccountSlot.primary
          ? KuaishouAccountPoolMode.primary
          : KuaishouAccountPoolMode.secondary,
      secondaryAvailable: secondary.isAvailable(DateTime.now()),
    );
  }

  void _syncLegacyObservables() {
    hasCookie.value = primary.isConfigured;
    cookieExpiresAtMs.value =
        primary.cookieExpiresAt?.millisecondsSinceEpoch ?? 0;
    revision.value++;
  }

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

DateTime nextShanghaiMidnight(DateTime now) {
  final utc = now.toUtc();
  final shanghai = utc.add(const Duration(hours: 8));
  return DateTime.utc(shanghai.year, shanghai.month, shanghai.day + 1)
      .subtract(const Duration(hours: 8))
      .toLocal();
}

String normalizeKuaishouCookie(String cookie) {
  final parts = cookie
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
    if (index <= 0) {
      continue;
    }
    values[item.substring(0, index).trim().toLowerCase()] =
        item.substring(index + 1).trim();
  }
  for (final name in const [
    'userId',
    'user_id',
    'uid',
    'kuaishou.user.id',
  ]) {
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

  final settings =
      legacySettings is Map ? legacySettings : const <String, dynamic>{};
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
        'cookie': settings[LocalStorageService.kKuaishouSecondaryCookie]
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
    return const {
      'cookie': '',
      'kww': '',
      'cookieExpiresAt': 0,
      'state': null,
    };
  }
  return {
    'cookie': raw['cookie']?.toString() ?? '',
    'kww': raw['kww']?.toString() ?? '',
    'cookieExpiresAt': raw['cookieExpiresAt'] ?? 0,
    'state': raw['state'],
  };
}

KuaishouAccountPoolMode degradeKuaishouMode({
  required KuaishouAccountPoolMode current,
  required bool secondaryAvailable,
}) {
  if (current == KuaishouAccountPoolMode.primary && secondaryAvailable) {
    return KuaishouAccountPoolMode.secondary;
  }
  return KuaishouAccountPoolMode.anonymous;
}

/// Returns an exact expiry only when an authentication cookie embeds a
/// standard JWT-style `exp` value. Opaque Kuaishou tokens deliberately return
/// null rather than inventing a lifetime that the server did not expose.
DateTime? resolveKuaishouEmbeddedTokenExpiry(String cookie) {
  final values = <String, String>{};
  for (final part in cookie.split(';')) {
    final item = part.trim();
    final index = item.indexOf('=');
    if (index <= 0) {
      continue;
    }
    values[item.substring(0, index).trim()] = item.substring(index + 1).trim();
  }
  for (final name in const [
    'kuaishou.live.web_st',
    'kuaishou.server.web_st',
    'kuaishou.live.web_at',
    'passToken',
  ]) {
    final expiry = _decodeTokenExpiry(values[name] ?? '');
    if (expiry != null) {
      return expiry;
    }
  }
  return null;
}

DateTime? _decodeTokenExpiry(String rawToken) {
  if (rawToken.isEmpty) {
    return null;
  }
  String token;
  try {
    token = Uri.decodeComponent(rawToken);
  } catch (_) {
    token = rawToken;
  }
  final parts = token.split('.');
  if (parts.length < 2) {
    return null;
  }
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (payload is! Map) {
      return null;
    }
    final rawExpiry = payload['exp'] ??
        payload['expiresAt'] ??
        payload['expireAt'] ??
        payload['expiration'];
    final numericExpiry = rawExpiry is num
        ? rawExpiry.toInt()
        : int.tryParse(rawExpiry?.toString() ?? '');
    if (numericExpiry == null || numericExpiry <= 0) {
      return null;
    }
    final milliseconds =
        numericExpiry < 100000000000 ? numericExpiry * 1000 : numericExpiry;
    final expiry = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    // Reject nonsensical payload values instead of surfacing a bogus date.
    if (expiry.year < 2020 || expiry.year > 2200) {
      return null;
    }
    return expiry;
  } catch (_) {
    return null;
  }
}
