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

  factory VersionModel.fromJson(Map<String, dynamic> json) {
    final uri = Uri.tryParse(json['download_url']?.toString() ?? '');
    final parts = uri?.pathSegments ?? <String>[];
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        parts.length != 5 ||
        parts[0].isEmpty ||
        parts[1].isEmpty ||
        parts[2] != 'releases' ||
        parts[3] != 'tag' ||
        !RegExp(r'^tv_v\d+\.\d+\.\d+(?:-(?:dev|pre))?$').hasMatch(parts[4])) {
      throw const FormatException('TV 版本下载链接不是有效的 tv_v Release');
    }
    return VersionModel(
      version: json['version']?.toString() ?? '',
      versionNum: int.tryParse(json['version_num']?.toString() ?? '') ?? 0,
      versionDesc: json['version_desc']?.toString() ?? '',
      downloadUrl: json['download_url']?.toString() ?? '',
      prerelease: json['prerelease'] == true,
    );
  }

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
