import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/services/tv_app_update_service.dart';

class TvUpdateDialog extends StatelessWidget {
  const TvUpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TvAppUpdateService.instance;
    return AlertDialog(
      title: const Text('发现新版本'),
      content: SizedBox(
        width: 720.w,
        child: Obx(() {
          final version = service.latestVersion.value;
          final path = service.downloadedFilePath.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '当前版本 ${service.currentVersion}，最新版本 ${version?.version ?? '-'}',
                style: AppStyle.textStyleWhite,
              ),
              if (version?.versionDesc.trim().isNotEmpty == true) ...[
                AppStyle.vGap16,
                Text(version!.versionDesc, style: AppStyle.textStyleWhite),
              ],
              if (service.downloading.value) ...[
                AppStyle.vGap24,
                LinearProgressIndicator(
                  value: service.downloadProgress.value > 0
                      ? service.downloadProgress.value
                      : null,
                ),
                AppStyle.vGap8,
                Text(
                  '${(service.downloadProgress.value * 100).toStringAsFixed(0)}%',
                  style: AppStyle.subTextStyleWhite,
                ),
              ],
              if (path != null && !service.downloading.value) ...[
                AppStyle.vGap16,
                Text('已下载：$path', style: AppStyle.subTextStyleWhite),
              ],
              if (service.errorMessage.value != null) ...[
                AppStyle.vGap16,
                Text(
                  service.errorMessage.value!,
                  style: TextStyle(color: Colors.redAccent, fontSize: 20.w),
                ),
              ],
            ],
          );
        }),
      ),
      actions: [
        Obx(
          () => TextButton(
            onPressed:
                service.downloading.value ? service.cancelDownload : Get.back,
            child: Text(service.downloading.value ? '取消下载' : '稍后再说'),
          ),
        ),
        Obx(
          () => TextButton(
            onPressed: service.downloading.value
                ? null
                : service.downloadedFilePath.value != null
                    ? service.openDownloadedFile
                    : () async {
                        try {
                          await service.downloadLatest();
                          SmartDialog.showToast('安装包下载完成');
                        } catch (_) {
                          SmartDialog.showToast('安装包下载失败');
                        }
                      },
            child: Text(
              service.downloadedFilePath.value != null ? '打开安装包' : '下载更新',
            ),
          ),
        ),
        TextButton(
          onPressed: service.openReleasePage,
          child: const Text('打开 Release 页面'),
        ),
      ],
    );
  }
}
