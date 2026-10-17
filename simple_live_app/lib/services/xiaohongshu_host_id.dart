/// Normalizes a Xiaohongshu live anchor ID accepted by the host-room API.
String? normalizeXiaohongshuHostId(Object? value) {
  final hostId = value?.toString().trim().toLowerCase() ?? '';
  return RegExp(r'^[0-9a-f]{24}$').hasMatch(hostId) ? hostId : null;
}
