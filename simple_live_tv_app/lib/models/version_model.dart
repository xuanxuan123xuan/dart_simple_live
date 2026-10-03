import 'dart:convert';

T? asT<T>(dynamic value) {
  if (value is T) {
    return value;
  }
  return null;
}

class VersionModel {
  VersionModel({
    required this.version,
    required this.versionNum,
    required this.versionDesc,
    required this.downloadUrl,
    this.prerelease = false,
  });

  factory VersionModel.fromJson(Map<String, dynamic> json) => VersionModel(
        version: json['version']?.toString() ?? '',
        versionNum: int.tryParse(json['version_num']?.toString() ?? '') ?? 0,
        versionDesc: json['version_desc']?.toString() ?? '',
        downloadUrl: json['download_url']?.toString() ?? '',
        prerelease: json['prerelease'] == true,
      );

  String version;
  int versionNum;
  String versionDesc;
  String downloadUrl;
  bool prerelease;

  @override
  String toString() {
    return jsonEncode(this);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'version_num': versionNum,
        'version_desc': versionDesc,
        'download_url': downloadUrl,
        'prerelease': prerelease,
      };
}
