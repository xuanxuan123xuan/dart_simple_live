import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/profile_backup_service.dart';

/// 导入前的确认结果：勾选了哪些分类、是否覆盖本地数据。
class ProfileImportDecision {
  final Set<ProfileCategory> categories;
  final bool overwrite;

  const ProfileImportDecision({
    required this.categories,
    required this.overwrite,
  });

  ProfileImportOptions get options =>
      ProfileImportOptions.fromCategories(categories);
}

/// 读取配置包之后再让用户勾选：只列出包内真实存在的分类，带上数量提示。
class ProfileImportDialog extends StatefulWidget {
  final ProfileInspection inspection;

  /// 预勾选的分类，留空表示除账号外全选。
  /// 与包内实际内容求交集，不会出现包里没有的分类。
  final Set<ProfileCategory>? preselected;

  const ProfileImportDialog({
    required this.inspection,
    this.preselected,
    super.key,
  });

  /// 返回 null 表示用户取消导入。
  static Future<ProfileImportDecision?> show(
    ProfileInspection inspection, {
    Set<ProfileCategory>? preselected,
  }) {
    return Utils.showDialogSafe<ProfileImportDecision>(
      context: Get.context!,
      builder: (_) => ProfileImportDialog(
        inspection: inspection,
        preselected: preselected,
      ),
    );
  }

  @override
  State<ProfileImportDialog> createState() => _ProfileImportDialogState();
}

class _ProfileImportDialogState extends State<ProfileImportDialog> {
  late final List<ProfileCategory> _available;
  final Set<ProfileCategory> _selected = {};
  bool _overwrite = false;

  @override
  void initState() {
    super.initState();
    _available = widget.inspection.availableCategories;
    final preselected = widget.preselected;
    if (preselected != null) {
      _selected.addAll(_available.where(preselected.contains));
    }
    if (_selected.isEmpty) {
      // 默认全选，但账号登录信息涉及 Cookie，需要用户自己确认。
      _selected.addAll(
        _available.where((category) => category != ProfileCategory.accounts),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("导入配置包"),
      content: Container(
        width: 360,
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height * 0.5).clamp(220.0, 480.0),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: AppStyle.edgeInsetsV12,
                child: Text(
                  _headerText(),
                  style: Get.textTheme.bodySmall,
                ),
              ),
              ..._available.map(_buildCategoryTile),
              AppStyle.divider,
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("覆盖本地数据"),
                subtitle: Text(
                  _overwrite ? "先清空本机对应数据再导入" : "与本机已有数据合并，保留原有内容",
                  style: Get.textTheme.bodySmall,
                ),
                value: _overwrite,
                onChanged: (value) => setState(() => _overwrite = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: null),
          child: const Text("取消"),
        ),
        TextButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Get.back(
                    result: ProfileImportDecision(
                      categories: Set.of(_selected),
                      overwrite: _overwrite,
                    ),
                  ),
          child: const Text("确认导入"),
        ),
      ],
    );
  }

  Widget _buildCategoryTile(ProfileCategory category) {
    final info = widget.inspection.categories[category];
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(category.title),
      subtitle: Text(
        info == null ? category.subtitle : "${category.subtitle} · ${info.detail}",
        style: Get.textTheme.bodySmall,
      ),
      value: _selected.contains(category),
      onChanged: (checked) => setState(() {
        if (checked ?? false) {
          _selected.add(category);
        } else {
          _selected.remove(category);
        }
      }),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }

  String _headerText() {
    final inspection = widget.inspection;
    final parts = <String>[];
    switch (inspection.kind) {
      case ProfilePackageKind.profile:
        parts.add("Simple Live 配置包");
        break;
      case ProfilePackageKind.legacyProfile:
        parts.add("旧版配置包");
        break;
      case ProfilePackageKind.legacyDataFile:
        parts.add("旧版数据文件");
        break;
    }
    final appVersion = inspection.appVersion;
    if (appVersion != null && appVersion.isNotEmpty) {
      parts.add("v$appVersion");
    }
    final exportedAt = DateTime.tryParse(inspection.exportedAt ?? "");
    if (exportedAt != null) {
      parts.add("导出于 ${Utils.dateFormatWithYear.format(exportedAt.toLocal())}");
    }
    return "${parts.join(" · ")}\n已识别到以下内容，勾选后确认导入。";
  }
}
