import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class Sites {
  static final Map<String, Site> allSites = {
    Constant.kBiliBili: Site(
      id: Constant.kBiliBili,
      logo: "assets/images/bilibili_2.png",
      name: "哔哩哔哩",
      liveSite: BiliBiliSite(),
    ),
    Constant.kDouyu: Site(
      id: Constant.kDouyu,
      logo: "assets/images/douyu.png",
      name: "斗鱼直播",
      liveSite: DouyuSite(),
    ),
    Constant.kHuya: Site(
      id: Constant.kHuya,
      logo: "assets/images/huya.png",
      name: "虎牙直播",
      liveSite: HuyaSite(),
    ),
    Constant.kDouyin: Site(
      id: Constant.kDouyin,
      logo: "assets/images/douyin.png",
      name: "抖音直播",
      liveSite: DouyinSite(),
    ),
    Constant.kKuaishou: Site(
      id: Constant.kKuaishou,
      logo: "assets/images/kuaishou.png",
      name: "快手直播",
      liveSite: KuaishouSite(
        categorySnapshotStore: _KuaishouCategorySnapshotStore(),
      ),
    ),
  };

  static List<Site> get supportSites {
    return AppSettingsController.instance.siteSort
        .map((key) => allSites[key]!)
        .toList();
  }
}

class _KuaishouCategorySnapshotStore implements KuaishouCategorySnapshotStore {
  @override
  Future<Map<String, dynamic>?> read() async {
    final value = LocalStorageService.instance.getValue<dynamic>(
      LocalStorageService.kKuaishouCategorySnapshot,
      null,
    );
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    await LocalStorageService.instance.setValue(
      LocalStorageService.kKuaishouCategorySnapshot,
      snapshot,
    );
  }
}

class Site {
  final String id;
  final String name;
  final String logo;
  final LiveSite liveSite;
  Site({
    required this.id,
    required this.liveSite,
    required this.logo,
    required this.name,
  });
}
