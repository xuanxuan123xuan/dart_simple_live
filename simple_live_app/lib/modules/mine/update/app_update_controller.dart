import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
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

  RxBool get autoCheckEnabled => _service.autoCheckEnabled;

  int get currentBuildNumber => _service.currentBuildNumber;

  String get currentVersion => _service.currentVersion;

  bool get isDifferentChannel =>
      selectedChannel.value != _service.defaultChannel;

  bool get hasUpdate {
    final release = selectedRelease.value;
    return release != null && _service.isNewerThanCurrent(release);
  }

  String get statusText {
    final release = selectedRelease.value;
    if (release == null) {
      return '尚未检查';
    }
    if (_service.isNewerThanCurrent(release)) {
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
    _loadInitialState();
  }

  Future<void> changeChannel(AppUpdateChannel channel) async {
    if (selectedChannel.value == channel) {
      return;
    }
    selectedChannel.value = channel;
    await _service.setPreferredChannel(channel);
    await _refreshSelectedRelease();
  }

  Future<void> setAutoCheckEnabled(bool enabled) async {
    await _service.setAutoCheckEnabled(enabled);
  }

  Future<void> checkUpdates() async {
    if (loading.value) {
      return;
    }
    loading.value = true;
    errorMessage.value = null;
    try {
      final result = await _service.checkForUpdates(
        channel: selectedChannel.value,
      );
      catalog.value = result.catalog;
      checkedAt.value = _service.lastCheckedAt.value;
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

  Future<void> _loadInitialState() async {
    currentPlatform.value = await _service.detectCurrentPlatform();
    catalog.value = _service.latestCatalog.value;
    checkedAt.value = _service.lastCheckedAt.value;
    await _refreshSelectedRelease();
  }

  Future<void> _refreshSelectedRelease() async {
    final currentCatalog = catalog.value;
    final release = currentCatalog?.releaseForChannel(selectedChannel.value);
    selectedRelease.value = release;
    final lastChecked = checkedAt.value;
    if (currentCatalog != null && lastChecked != null) {
      _service.recordCheckResult(
        catalog: currentCatalog,
        release: release,
        checkedAt: lastChecked,
      );
    }
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
