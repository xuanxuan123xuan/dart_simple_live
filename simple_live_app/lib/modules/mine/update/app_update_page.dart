import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/app_update_model.dart';
import 'package:simple_live_app/modules/mine/update/app_update_controller.dart';
import 'package:simple_live_app/services/cache_service.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AppUpdatePage extends GetView<AppUpdateController> {
  const AppUpdatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('检查更新')),
      body: Obx(
        () => ListView(
          padding: AppStyle.pagePadding(),
          children: [
            _sectionTitle('自动检测'),
            SettingsCard(
              child: SwitchListTile(
                secondary: const Icon(Remix.notification_badge_line),
                title: const Text('自动检测更新'),
                subtitle: const Text('启动后静默检查，发现新版时显示提示'),
                value: controller.autoCheckEnabled.value,
                onChanged: controller.setAutoCheckEnabled,
              ),
            ),
            _sectionTitle(
              Utils.isOhos ? 'HAP Store 更新' : '更新通道',
              top: 24,
            ),
            SettingsCard(
              child: Padding(
                padding: AppStyle.edgeInsetsA16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!Utils.isOhos) ...[
                      SegmentedButton<AppUpdateChannel>(
                        segments: const [
                          ButtonSegment(
                            value: AppUpdateChannel.stable,
                            label: Text('stable'),
                            icon: Icon(Icons.verified_outlined),
                          ),
                          ButtonSegment(
                            value: AppUpdateChannel.dev,
                            label: Text('dev'),
                            icon: Icon(Icons.code),
                          ),
                        ],
                        selected: {controller.selectedChannel.value},
                        onSelectionChanged: controller.loading.value
                            ? null
                            : (value) => controller.changeChannel(value.first),
                      ),
                      AppStyle.vGap12,
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: controller.loading.value
                                ? null
                                : controller.checkUpdates,
                            icon: controller.loading.value
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Remix.refresh_line),
                            label: Text(
                              controller.loading.value ? '检查中' : '检查更新',
                            ),
                          ),
                        ),
                        AppStyle.hGap12,
                        OutlinedButton.icon(
                          onPressed: controller.openReleasePage,
                          icon: const Icon(Remix.external_link_line),
                          label: Text(Utils.isOhos ? '下载页' : 'Release'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _sectionTitle('版本状态', top: 24),
            SettingsCard(child: _buildStatus(context)),
            if (controller.selectedRelease.value != null) ...[
              _sectionTitle('推荐安装包', top: 24),
              SettingsCard(child: _buildRecommendedAsset(context)),
              _buildCurrentPlatformAssets(context),
              _buildReleaseNotes(context),
            ],
            if (controller.errorMessage.value != null) ...[
              _sectionTitle('检查失败', top: 24),
              SettingsCard(
                child: ListTile(
                  leading: const Icon(Remix.error_warning_line),
                  title: const Text('无法获取发布信息'),
                  subtitle: Text(controller.errorMessage.value!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {double top = 0}) {
    return Padding(
      padding: AppStyle.edgeInsetsA12.copyWith(top: top),
      child: Text(title, style: Get.textTheme.titleSmall),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final release = controller.selectedRelease.value;
    final checkedAt = controller.checkedAt.value;
    return Column(
      children: [
        ListTile(
          leading: Icon(
            controller.hasUpdate
                ? Icons.system_update_alt
                : Icons.check_circle_outline,
          ),
          title: Text(controller.statusText),
          subtitle: Text(
            checkedAt == null
                ? '当前版本 ${controller.currentVersion}'
                : '当前版本 ${controller.currentVersion}，${Utils.parseTime(checkedAt)} 检查',
          ),
          trailing: Utils.isOhos
              ? null
              : Text(controller.selectedChannel.value.displayName),
        ),
        if (release != null) ...[
          AppStyle.divider,
          ListTile(
            leading: const Icon(Remix.price_tag_3_line),
            title: const Text('远端版本'),
            subtitle: Text('Build ${release.buildNumber}'),
            trailing: Text(release.version),
          ),
        ],
      ],
    );
  }

  Widget _buildRecommendedAsset(BuildContext context) {
    final asset = controller.recommendedAsset.value;
    if (asset == null) {
      return ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: const Text('当前平台暂无可用安装包'),
        subtitle: const Text('可打开 Release 页面查看全部发布资产'),
        trailing: const Icon(Icons.chevron_right),
        onTap: controller.openReleasePage,
      );
    }

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(asset.displayName),
          subtitle: Text(asset.name),
          trailing: const Icon(Icons.open_in_new),
          onTap: controller.openRecommendedAsset,
        ),
        if (asset.size != null || asset.sha256 != null) ...[
          AppStyle.divider,
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: Text(asset.size == null
                ? 'SHA-256'
                : CacheService.formatBytes(asset.size!)),
            subtitle: asset.sha256 == null ? null : Text(asset.sha256!),
          ),
        ],
        AppStyle.divider,
        Padding(
          padding: AppStyle.edgeInsetsA16,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: controller.openRecommendedAsset,
                  icon: const Icon(Icons.download),
                  label: Text(controller.hasUpdate ? '下载更新' : '重新下载'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentPlatformAssets(BuildContext context) {
    final release = controller.selectedRelease.value;
    final platform = controller.currentPlatform.value;
    if (release == null || platform == null) {
      return const SizedBox.shrink();
    }
    final assets = release.assets
        .where((asset) => asset.platform == platform)
        .toList(growable: false);
    if (assets.length <= 1) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('${platform.label} 可用安装包', top: 24),
        SettingsCard(
          child: Column(
            children: [
              for (var index = 0; index < assets.length; index++) ...[
                if (index > 0) AppStyle.divider,
                _assetTile(assets[index]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _assetTile(AppUpdateAsset asset) {
    final selected = controller.recommendedAsset.value?.name == asset.name;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.circle_outlined,
      ),
      title: Text(asset.displayName),
      subtitle: Text(asset.name),
      trailing: asset.size == null
          ? null
          : Text(CacheService.formatBytes(asset.size!)),
      onTap: () => controller.selectAsset(asset),
    );
  }

  Widget _buildReleaseNotes(BuildContext context) {
    final release = controller.selectedRelease.value;
    final markdown = release == null ? '' : _normalizeMarkdown(release.body);
    if (release == null || markdown.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('发布说明', top: 24),
        SettingsCard(
          child: ExpansionTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(release.tag),
            subtitle: release.publishedAt == null
                ? null
                : Text(Utils.parseTime(release.publishedAt!.toLocal())),
            childrenPadding: AppStyle.edgeInsetsA16,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: MarkdownBody(
                  data: markdown,
                  selectable: true,
                  styleSheet: _markdownStyleSheet(context),
                  onTapLink: (_, href, __) {
                    if (href == null || href.isEmpty) {
                      return;
                    }
                    launchUrlString(href, mode: LaunchMode.externalApplication);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _normalizeMarkdown(String body) {
    var markdown = body.trim();
    if (markdown.startsWith('\uFEFF')) {
      markdown = markdown.substring(1);
    }
    if (!markdown.contains('\n') && markdown.contains(r'\n')) {
      markdown = markdown
          .replaceAll(r'\r\n', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\t', '  ');
    }
    return markdown.trim();
  }

  MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final base = MarkdownStyleSheet.fromTheme(theme);
    return base.copyWith(
      h1: theme.textTheme.titleLarge,
      h2: theme.textTheme.titleMedium,
      h3: theme.textTheme.titleSmall,
      p: theme.textTheme.bodyMedium,
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: colorScheme.primary, width: 3),
        ),
      ),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        backgroundColor:
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      ),
      tableHead: theme.textTheme.labelLarge,
      tableBody: theme.textTheme.bodySmall,
      tableBorder: TableBorder.all(color: theme.dividerColor),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
    );
  }
}
