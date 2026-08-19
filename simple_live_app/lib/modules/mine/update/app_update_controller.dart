import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/generated/app_version.g.dart';
import 'package:simple_live_app/models/app_update_model.dart';
import 'package:simple_live_app/services/app_update_service.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AppUpdateController extends GetxController {
  AppUpdateController({AppUpdateService? service})
      : _service = service ?? AppUpdateService.instance;

  final AppUpdateService _service;

  late final Rx<AppUpdateChannel> selectedChannel;
  final Rxn<AppUpdateCatalog> catalog = Rxn<AppUpdateCatalog>();
  final Rxn<AppUpdateRelease> selectedRelease = Rxn<AppUpdateRelease>();
  final Rxn<AppUpdateAsset> recommendedAsset = Rxn<AppUpdateAsset>();
  final Rxn<AppUpdatePlatform> currentPlatform = Rxn<AppUpdatePlatform>();
  final RxBool loading = false.obs;
  final RxnString errorMessage = RxnString();
  final Rxn<DateTime> checkedAt = Rxn<DateTime>();

  int get currentBuildNumber =>
      int.tryParse(GeneratedAppVersion.buildNumber) ??
      int.tryParse(Utils.packageInfo.buildNumber) ??
      0;

  String get currentVersion => GeneratedAppVersion.fullVersion;

  bool get isDifferentChannel => selectedChannel.value != _service.defaultChannel;

  bool get hasUpdate {
    final release = selectedRelease.value;
    return release != null && release.buildNumber > currentBuildNumber;
  }

  String get statusText {
    final release = selectedRelease.value;
    if (release == null) {
      return '尚未检查';
    }
    if (release.buildNumber > currentBuildNumber) {
      return '发现新版本';
    }
    if (release.buildNumber == currentBuildNumber) {
      if (isDifferentChannel) {
        return '同版本不同通道';
      }
      return '已是最新';
    }
    return '本地版本高于远端';
  }

  @override
  void onInit() {
    selectedChannel = _service.preferredChannel.obs;
    super.onInit();
    _loadCurrentPlatform();
  }

  Future<void> changeChannel(AppUpdateChannel channel) async {
    if (selectedChannel.value == channel) {
      return;
    }
    selectedChannel.value = channel;
    await _service.setPreferredChannel(channel);
    await _refreshSelectedRelease();
  }

  Future<void> checkUpdates() async {
    if (loading.value) {
      return;
    }
    loading.value = true;
    errorMessage.value = null;
    try {
      final nextCatalog = await _service.fetchCatalog();
      catalog.value = nextCatalog;
      checkedAt.value = DateTime.now();
      await _refreshSelectedRelease();
      if (selectedRelease.value == null) {
        SmartDialog.showToast('没有找到 ${selectedChannel.value.displayName} 发布');
      } else if (hasUpdate) {
        SmartDialog.showToast('发现 ${selectedRelease.value!.version}');
      } else {
        SmartDialog.showToast('已是最新版本');
      }
    } catch (e, stackTrace) {
      Log.logPrint('检查更新失败: $e\n$stackTrace');
      errorMessage.value = e.toString();
      SmartDialog.showToast('检查更新失败');
    } finally {
      loading.value = false;
    }
  }

  Future<void> selectAsset(AppUpdateAsset asset) async {
    recommendedAsset.value = asset;
    await _service.setPreferredSelection(
      AppUpdateSelection(
        platform: asset.platform,
        packageKind: asset.kind,
        abi: asset.abi,
      ),
    );
  }

  Future<void> openRecommendedAsset() async {
    final asset = recommendedAsset.value;
    if (asset == null) {
      await openReleasePage();
      return;
    }
    await launchUrlString(asset.url, mode: LaunchMode.externalApplication);
  }

  Future<void> openReleasePage() async {
    final url =
        selectedRelease.value?.releaseUrl ?? AppUpdateService.releasesPageUrl;
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _loadCurrentPlatform() async {
    currentPlatform.value = await _service.detectCurrentPlatform();
  }

  Future<void> _refreshSelectedRelease() async {
    final release = catalog.value?.releaseForChannel(selectedChannel.value);
    selectedRelease.value = release;
    if (release == null) {
      recommendedAsset.value = null;
      return;
    }
    recommendedAsset.value = await _service.pickRecommendedAsset(
      release,
      platform: currentPlatform.value,
    );
  }
}
