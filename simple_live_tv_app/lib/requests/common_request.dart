import 'dart:convert';

import 'package:simple_live_tv_app/models/version_model.dart';
import 'package:simple_live_tv_app/requests/http_client.dart';

/// 通用的请求
class CommonRequest {
  static const String _repository = "xuanxuan123xuan/dart_simple_live";

  Future<VersionModel> checkUpdate() async {
    try {
      return await checkUpdateGitMirror();
    } catch (e) {
      return await checkUpdateJsDelivr();
    }
  }

  /// 检查更新
  Future<VersionModel> checkUpdateGitMirror() async {
    var result = await HttpClient.instance.getJson(
      "https://raw.githubusercontent.com/$_repository/master/assets/tv_app_version.json",
      queryParameters: {
        "ts": DateTime.now().millisecondsSinceEpoch,
      },
    );
    if (result is Map) {
      return VersionModel.fromJson(result as Map<String, dynamic>);
    }
    return VersionModel.fromJson(json.decode(result));
  }

  /// 检查更新
  Future<VersionModel> checkUpdateJsDelivr() async {
    var result = await HttpClient.instance.getJson(
      "https://cdn.jsdelivr.net/gh/$_repository@master/assets/tv_app_version.json",
      queryParameters: {
        "ts": DateTime.now().millisecondsSinceEpoch,
      },
    );
    if (result is Map) {
      return VersionModel.fromJson(result as Map<String, dynamic>);
    }
    return VersionModel.fromJson(json.decode(result));
  }
}
