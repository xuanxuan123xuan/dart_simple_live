import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_tv_app/services/db_service.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';
import 'package:simple_live_tv_app/services/live_room_link_parser.dart';
import 'package:simple_live_tv_app/widgets/tv_open_live_link_dialog.dart';
import 'package:simple_live_tv_app/widgets/tv_playback_dialog_theme.dart';

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
  Map<String, int> _searchResultStatuses = const <String, int>{};
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
    _searchResultStatuses = const <String, int>{};
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
      _searchResultStatuses = const <String, int>{};
    });
    try {
      if (requestAnchor) {
        final result = await requestSite.liveSite.searchAnchors(query, page: 1);
        if (!mounted || generation != _searchGeneration) return;
        final results = result.items
            .map((item) => MultiRoomItem(
                  site: requestSite,
                  roomId: item.roomId,
                  userName: item.userName,
                  face: item.avatar,
                ))
            .toList(growable: false);
        final statuses = <String, int>{
          for (final item in result.items)
            '${requestSite.id}_${item.roomId}': item.liveStatus ? 2 : 1,
        };
        setState(() {
          _searchResults = results;
          _searchResultStatuses = statuses;
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
          _searchResultStatuses = const <String, int>{};
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

  List<_RoomPickerEntry> _visibleEntries() {
    final follows = FollowUserService.instance.allList.toList(growable: false);
    final followStatuses = <String, int>{
      for (final item in follows)
        '${item.siteId}_${item.roomId}': item.liveStatus.value,
    };

    if (_section == '关注') {
      return _liveFirst(follows.map((item) => _RoomPickerEntry(
            item: MultiRoomItem.fromFollow(item),
            liveStatus: followStatuses['${item.siteId}_${item.roomId}'] ?? 0,
          )));
    }
    if (_section == '历史') {
      final entries = DBService.instance
          .getHistores()
          .where((item) => Sites.allSites.containsKey(item.siteId))
          .map((item) {
        final room = MultiRoomItem.fromHistory(item);
        return _RoomPickerEntry(
          item: room,
          liveStatus: followStatuses[room.key] ?? 0,
        );
      });
      return _liveFirst(entries);
    }
    if (_section == '搜索') {
      return _liveFirst(_searchResults.map((item) => _RoomPickerEntry(
            item: item,
            liveStatus: _searchResultStatuses[item.key] ??
                followStatuses[item.key] ??
                0,
          )));
    }
    return const <_RoomPickerEntry>[];
  }

  List<_RoomPickerEntry> _liveFirst(Iterable<_RoomPickerEntry> entries) {
    final live = <_RoomPickerEntry>[];
    final other = <_RoomPickerEntry>[];
    for (final entry in entries) {
      (entry.liveStatus == 2 ? live : other).add(entry);
    }
    return [...live, ...other];
  }

  Key _rowKey(MultiRoomItem item) =>
      ValueKey<String>('tv-room-picker-row-${item.key}');

  Widget _buildRoomList(BuildContext context) {
    final entries = _visibleEntries();
    if (entries.isEmpty) {
      return Center(
        child: Text(
          _section == '搜索' ? '输入关键词后搜索单个平台' : '这里还没有直播间',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xbfffffff),
              ),
        ),
      );
    }

    final itemIndexByKey = <Key, int>{};
    for (var index = 0; index < entries.length; index++) {
      itemIndexByKey[_rowKey(entries[index].item)] = index;
    }

    return ListView.separated(
      itemCount: entries.length,
      padding: const EdgeInsets.symmetric(vertical: 2),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      findItemIndexCallback: (key) => itemIndexByKey[key],
      itemBuilder: (context, index) {
        final entry = entries[index];
        final item = entry.item;
        final isSelected = _selected.containsKey(item.key);
        final isExisting = _isExisting(item.key);
        final isAtLimit = !isSelected && _selected.length >= widget.maxRooms;
        final disabled = isExisting || isAtLimit;
        final name = item.userName.isEmpty ? item.roomId : item.userName;

        return TvDialogFocusableSurface(
          key: _rowKey(item),
          minHeight: 72,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          selected: isSelected,
          disabled: disabled,
          onTap: () => _toggle(item),
          child: Row(
            children: [
              _RoomAvatar(item: item),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RoomStatusBadge(status: entry.liveStatus),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.site.name} · ${item.roomId}${isExisting ? ' · 正在播放' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xbfffffff),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (isExisting) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.lock_outline,
                  color: Color(0xbfffffff),
                  size: 20,
                ),
              ],
              const SizedBox(width: 8),
              IgnorePointer(
                child: Checkbox(
                  value: isSelected,
                  onChanged: null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return TvPlaybackDialogSurface(
      key: const Key('tv-room-picker'),
      maxWidth: 1200,
      maxHeight: 760,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvPlaybackDialogHeader(
                icon: Icons.video_library_outlined,
                framedIcon: false,
                title: '选择同播直播间',
                subtitle: '添加要一起播放的直播间',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(24),
                        border:
                            Border.all(color: accent.withValues(alpha: .38)),
                      ),
                      child: Text(
                        '${_selected.length} / ${widget.maxRooms}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      autofocus: true,
                      onPressed: _openLinkDialog,
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('输入直播链接'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final section in const ['关注', '历史', '搜索'])
                    TvDialogFocusableSurface(
                      key: Key('tv-room-picker-tab-$section'),
                      selected: _section == section,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      onTap: () => setState(() => _section = section),
                      child: Text(
                        section,
                        style: TextStyle(
                          color: _section == section
                              ? Colors.white
                              : const Color(0xddffffff),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (_section == '搜索') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<Site>(
                        initialValue: _searchSite,
                        decoration: const InputDecoration(labelText: '平台'),
                        items: [
                          for (final site in Sites.supportSites)
                            DropdownMenuItem(
                              value: site,
                              child: Text(site.name),
                            ),
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
                    const SizedBox(width: 10),
                    TvDialogFocusableSurface(
                      selected: _searchAnchor,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      onTap: () => setState(() {
                        _searchAnchor = !_searchAnchor;
                        _invalidateSearch();
                      }),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _searchAnchor ? Icons.person : Icons.live_tv,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(_searchAnchor ? '主播' : '直播间'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        decoration: const InputDecoration(
                          labelText: '搜索关键词',
                          hintText: '输入主播名或直播间名称',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.info_outline, color: accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _searchError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: Obx(() => _buildRoomList(context)),
              ),
              const SizedBox(height: 10),
              _PickerFooter(
                onCancel: Get.back<void>,
                onConfirm: _selected.isEmpty
                    ? null
                    : () => Get.back<List<MultiRoomItem>>(
                          result: _selected.values.toList(growable: false),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomPickerEntry {
  const _RoomPickerEntry({required this.item, required this.liveStatus});

  final MultiRoomItem item;
  final int liveStatus;
}

class _RoomStatusBadge extends StatelessWidget {
  const _RoomStatusBadge({required this.status});

  final int status;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isLive = status == 2;
    final isOffline = status == 1;
    final label = isLive
        ? '直播中'
        : isOffline
            ? '未开播'
            : '状态未知';
    final foreground = isLive
        ? accent
        : isOffline
            ? const Color(0xffaeb6c2)
            : const Color(0xffd8dce3);
    final background = isLive
        ? accent.withValues(alpha: .16)
        : isOffline
            ? const Color(0x18ffffff)
            : const Color(0x10ffffff);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({required this.item});

  final MultiRoomItem item;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final face = item.face.trim();
    final fallback = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: .16),
        border: Border.all(color: accent.withValues(alpha: .34)),
      ),
      child: Icon(Icons.live_tv_rounded, color: accent, size: 23),
    );
    if (face.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        face,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _PickerFooter extends StatelessWidget {
  const _PickerFooter({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, color: Color(0x2fffffff)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onCancel, child: const Text('取消')),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.grid_view_rounded),
              label: const Text('开始多屏播放'),
            ),
          ],
        ),
      ],
    );
  }
}
