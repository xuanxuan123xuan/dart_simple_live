import 'dart:convert';

T? asT<T>(dynamic value) {
  if (value is T) {
    return value;
  }
  return null;
}

class SyncClientInfoModel {
  SyncClientInfoModel({
    required this.name,
    required this.version,
    required this.address,
    required this.port,
    required this.type,
    this.supportedAccountTypes = const [],
  });

  factory SyncClientInfoModel.fromJson(Map<String, dynamic> json) =>
      SyncClientInfoModel(
        type: asT<String>(json['type'])!,
        name: asT<String>(json['name'])!,
        version: asT<String>(json['version'])!,
        address: asT<String>(json['address'])!,
        port: asT<int>(json['port'])!,
        supportedAccountTypes: json['supportedAccountTypes'] is List
            ? (json['supportedAccountTypes'] as List)
                .whereType<String>()
                .map((value) => value.trim().toLowerCase())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false)
            : const [],
      );
  String type;
  String name;
  String version;
  String address;
  int port;
  List<String> supportedAccountTypes;

  bool supportsAccountType(String accountType) =>
      supportedAccountTypes.contains(accountType.trim().toLowerCase());

  @override
  String toString() {
    return jsonEncode(this);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'version': version,
        'address': address,
        'port': port,
        'type': type,
        'supportedAccountTypes': supportedAccountTypes,
      };
}
