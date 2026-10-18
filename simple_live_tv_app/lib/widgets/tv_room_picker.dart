import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_style.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';
import 'package:simple_live_tv_app/widgets/tv_open_live_link_dialog.dart';

Future<List<MultiRoomItem>?> showTvRoomPicker({
  required int maxRooms,
  Iterable<MultiRoomItem> selectedRooms = const <MultiRoomItem>[],
  Iterable<MultiRoomItem> existingRooms = const <MultiRoomItem>[],
}) {
  return Get.dialog<List<MultiRoomItem>>(
    TvRoomPickerDialog(
      maxRooms: maxRooms,
      selectedRooms: selectedRooms.toList(growable: false),
      existingRooms: existingRooms.toList(growable: false),
    ),
    barrierDismissible: false,
  );
}

class TvRoomPickerDialog extends StatefulWidget {
  const TvRoomPickerDialog({
    super.key,
    required this.maxRooms,
    this.selectedRooms = const <MultiRoomItem>[],
    this.existingRooms = const <MultiRoomItem>[],
  });

  final int maxRooms;
  final List<MultiRoomItem> selectedRooms;
  final List<MultiRoomItem> existingRooms;

  @override
  State<TvRoomPickerDialog> createState() => _TvRoomPickerDialogState();
}

class _TvRoomPickerDialogState extends State<TvRoomPickerDialog> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final Map<String, MultiRoomItem> _selected = <String, MultiRoomItem>{};
  String _section = '关注';
  Site _searchSite = Sites.supportSites.first;
  bool _searchAnchor = false;
  bool _searching = false;
  String? _searchError;
  List<MultiRoomItem> _searchResults = const <MultiRoomItem>[];
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    for (final room in widget.selectedRooms) {
      _selected[room.key] = room;
    }
    for (final room in widget.existingRooms) {
      _selected.putIfAbsent(room.key, () => room);
    }
  }

  @override
  void dispose() {
    _searchGeneration++;
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<MultiRoomItem> get _existing => widget.existingRooms;

  bool _isExisting(String key) => _existing.any((room) => room.key == key);

  void _toggle(MultiRoomItem item) {
    setState(() {
      if (_isExisting(item.key)) return;
      if (_selected.containsKey(item.key)) {
        _selected.remove(item.key);
        return;
      }
      if (_selected.length >= widget.maxRooms) {
        return;
      }
      _selected[item.key] = item;
    });
  }

  void _invalidateSearch() {
    ++_searchGeneration;
    _searching = false;
    _searchError = null;
    _searchResults = const <MultiRoomItem>[];
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final generation = ++_searchGeneration;
    final requestSite = _searchSite;
    final requestAnchor = _searchAnchor;
    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = const <MultiRoomItem>[];
    });
    try {
      if (requestAnchor) {
        final result = await requestSite.liveSite.searchAnchors(query, page: 1);
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _searchResults = result.items
              .map((item) => MultiRoomItem(
                    site: requestSite,
                    roomId: item.roomId,
                    userName: item.userName,
                    face: item.avatar,
                  ))
              .toList(growable: false);
        });
      } else {
        final result = await requestSite.liveSite.searchRooms(query, page: 1);
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _searchResults = result.items
              .map((item) => MultiRoomItem(
                    site: requestSite,
                    roomId: item.roomId,
                    userName: item.userName,
                    face: item.cover,
                  ))
              .toList(growable: false);
        });
      }
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _searchError = '搜索失败：$error');
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _openLinkDialog() async {
    final target = await Get.dialog<LiveRoomLinkTarget>(
      const TvOpenLiveLinkDialog(),
      barrierDismissible: false,
    );
    if (target == null || !mounted) return;
    final item = MultiRoomItem.fromLink(target);
    setState(() {
      if (_selected.containsKey(item.key)) {
        _searchError = '该直播间已经选择';
      } else if (_selected.length >= widget.maxRooms) {
        _searchError = '最多选择 ${widget.maxRooms} 路';
      } else {
        _selected[item.key] = item;
        _searchError = null;
      }
    });
  }

  List<MultiRoomItem> get _visibleItems {
    if (_section == '关注') {
      return FollowUserService.instance.allList
          .map((item) => MultiRoomItem.fromFollow(item))
          .toList(growable: false);
    }
    if (_section == '历史') {
      return DBService.instance
          .getHistores()
          .where((item) => Sites.allSites.containsKey(item.siteId))
          .map((item) => MultiRoomItem.fromHistory(item))
          .toList(growable: false);
    }
    if (_section == '搜索') return _searchResults;
    return const <MultiRoomItem>[];
  }

  @override
  Widget build(BuildContext context) {
    final currentItems = _visibleItems;
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: SizedBox(
        width: 1150,
        height: 800,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择同播直播间  ${_selected.length}/${widget.maxRooms}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  TextButton.icon(
                    autofocus: true,
                    onPressed: _openLinkDialog,
                    icon: const Icon(Icons.link),
                    label: const Text('输入直播链接'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  for (final section in const ['关注', '历史', '搜索'])
                    ChoiceChip(
                      label: Text(section),
                      selected: _section == section,
                      onSelected: (_) => setState(() => _section = section),
                    ),
                ],
              ),
              if (_section == '搜索') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<Site>(
                        initialValue: _searchSite,
                        decoration: const InputDecoration(labelText: '平台'),
                        items: [
                          for (final site in Sites.supportSites)
                            DropdownMenuItem(
                                value: site, child: Text(site.name)),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _searchSite = value;
                              _invalidateSearch();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      label: Text(_searchAnchor ? '主播' : '直播间'),
                      selected: _searchAnchor,
                      onSelected: (value) => setState(() {
                        _searchAnchor = value;
                        _invalidateSearch();
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        decoration: const InputDecoration(
                          labelText: '搜索关键词',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _searching ? null : _search,
                      icon: _searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: const Text('搜索'),
                    ),
                  ],
                ),
              ],
              if (_searchError != null) ...[
                const SizedBox(height: 12),
                Text(_searchError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: currentItems.isEmpty
                    ? Center(
                        child: Text(
                          _section == '搜索' ? '输入关键词后搜索单个平台' : '这里还没有直播间',
                          style: AppStyle.textStyleWhite,
                        ),
                      )
                    : ListView.builder(
                        itemCount: currentItems.length,
                        itemBuilder: (context, index) {
                          final item = currentItems[index];
                          final isSelected = _selected.containsKey(item.key);
                          final isExisting = _isExisting(item.key);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: isExisting ||
                                    (!isSelected &&
                                        _selected.length >= widget.maxRooms)
                                ? null
                                : (_) => _toggle(item),
                            title: Text(
                              item.userName.isEmpty
                                  ? item.roomId
                                  : item.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                                '${item.site.name} · ${item.roomId}${isExisting ? ' · 正在播放' : ''}'),
                            secondary: const Icon(Icons.live_tv),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: Get.back<void>, child: const Text('取消')),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Get.back<List<MultiRoomItem>>(
                              result: _selected.values.toList(growable: false),
                            ),
                    icon: const Icon(Icons.grid_view),
                    label: const Text('开始多屏播放'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
