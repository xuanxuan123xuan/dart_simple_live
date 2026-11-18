import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/models/auto_switch_item.dart';
import 'package:simple_live_tv_app/services/auto_switch_list_service.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/widgets/app_scaffold.dart';
import 'package:simple_live_tv_app/widgets/button/highlight_button.dart';

class AutoSwitchListPage extends StatelessWidget {
  const AutoSwitchListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AutoSwitchListService.instance;
    return AppScaffold(
      child: Column(
        children: [
          AppStyle.vGap32,
          Row(
            children: [
              AppStyle.hGap48,
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.arrow_back,
                text: '返回',
                onTap: Get.back,
              ),
              AppStyle.hGap32,
              Text('轮播列表',
                  style: AppStyle.titleStyleWhite.copyWith(fontSize: 36.w)),
              const Spacer(),
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.playlist_add,
                text: '选择关注',
                onTap: () => _selectFollows(context, service),
              ),
              AppStyle.hGap16,
              HighlightButton(
                focusNode: AppFocusNode(),
                iconData: Icons.refresh,
                text: '刷新状态',
                onTap: service.refreshStatuses,
              ),
              AppStyle.hGap48,
            ],
          ),
          AppStyle.vGap32,
          Expanded(
            child: Obx(
              () => service.items.isEmpty
                  ? const Center(child: Text('轮播列表为空，请先加入关注主播'))
                  : ListView.builder(
                      padding: AppStyle.edgeInsetsH48,
                      itemCount: service.items.length,
                      itemBuilder: (context, index) {
                        final item = service.items[index];
                        return _AutoSwitchItemTile(
                          key: ValueKey(item.id),
                          item: item,
                          canMoveUp: index > 0,
                          canMoveDown: index < service.items.length - 1,
                          onMoveUp: () => service.move(index, index - 1),
                          onMoveDown: () => service.move(index, index + 2),
                          onRemove: () => service.remove(item.id),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _selectFollows(
  BuildContext context,
  AutoSwitchListService service,
) async {
  final follows = DBService.instance.getFollowList();
  if (follows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('关注列表为空')),
    );
    return;
  }
  final selected = service.items.map((item) => item.id).toSet();
  final result = await showDialog<Set<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('选择要加入轮播列表的关注'),
        content: SizedBox(
          width: 720,
          height: 520,
          child: ListView.builder(
            itemCount: follows.length,
            itemBuilder: (context, index) {
              final follow = follows[index];
              return CheckboxListTile(
                autofocus: index == 0,
                value: selected.contains(follow.id),
                title: Text(
                  follow.userName.isEmpty ? follow.roomId : follow.userName,
                ),
                subtitle: Text('${follow.siteId} · ${follow.roomId}'),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      selected.add(follow.id);
                    } else {
                      selected.remove(follow.id);
                    }
                  });
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              selected
                ..clear()
                ..addAll(follows.map((follow) => follow.id));
            }),
            child: const Text('全选'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(selected),
            child: const Text('加入'),
          ),
        ],
      ),
    ),
  );
  if (result == null) return;
  await service.addFollows(
    follows.where((follow) => result.contains(follow.id)),
  );
}

class _AutoSwitchItemTile extends StatelessWidget {
  const _AutoSwitchItemTile({
    required this.item,
    required this.onRemove,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    super.key,
  });

  final AutoSwitchItem item;
  final VoidCallback onRemove;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: item.face.isEmpty
            ? const Icon(Icons.person)
            : CircleAvatar(backgroundImage: NetworkImage(item.face)),
        title: Text(item.userName.isEmpty ? item.roomId : item.userName),
        subtitle: Text('${item.siteId} · ${_statusLabel(item.liveStatus)}'),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: '上移',
              icon: const Icon(Icons.arrow_upward),
              onPressed: canMoveUp ? onMoveUp : null,
            ),
            IconButton(
              tooltip: '下移',
              icon: const Icon(Icons.arrow_downward),
              onPressed: canMoveDown ? onMoveDown : null,
            ),
            IconButton(
              tooltip: '移除',
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(int status) {
    return switch (status) {
      2 => '直播中',
      1 => '未开播',
      _ => '未确认',
    };
  }
}
