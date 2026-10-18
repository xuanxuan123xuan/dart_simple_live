/// Account types carried over the existing remote sync account envelope.
///
/// Older clients omitted the type and only supported Bilibili. That one
/// missing-field case remains compatible; any non-empty unknown type is
/// rejected so it cannot fall through to the Bilibili account handler.
abstract final class SyncAccountType {
  static const bilibili = "bilibili";
  static const douyin = "douyin";
  static const douyu = "douyu";
  static const kuaishou = "kuaishou";
  static const xiaohongshu = "xiaohongshu";

  static const Set<String> values = {
    bilibili,
    douyin,
    douyu,
    kuaishou,
    xiaohongshu,
  };

  static String? resolve(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? "";
    if (value.isEmpty) {
      return bilibili;
    }
    return values.contains(value) ? value : null;
  }

  /// Builds the credential shape used by new providers over the legacy
  /// Bilibili SignalR action. Keeping the Cookie nested prevents old clients
  /// that default an unknown account type to Bilibili from importing it.
  static Map<String, Object?> credentialsEnvelope({
    required String accountType,
    required String cookie,
  }) {
    final resolved = resolve(accountType);
    if (resolved == null || resolved == bilibili) {
      throw ArgumentError.value(accountType, 'accountType');
    }
    return {
      'accountType': resolved,
      'credentials': {'cookie': cookie},
    };
  }

  static String? readCredentialCookie(
    Object? envelope, {
    required String accountType,
  }) {
    if (envelope is! Map || resolve(envelope['accountType']) != accountType) {
      return null;
    }
    final credentials = envelope['credentials'];
    if (credentials is! Map) {
      return null;
    }
    final cookie = credentials['cookie'];
    return cookie is String && cookie.trim().isNotEmpty ? cookie : null;
  }
}
