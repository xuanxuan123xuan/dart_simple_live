import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'tv_button.dart';
import 'live_page.dart';
import 'room_library.dart';
import 'site_registry.dart';
import 'tvos_session.dart';

// TV-friendly navigation: D-pad focusable buttons, no hover-only controls.
enum HomeSection { recommend, search, favorites, recent, settings }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeSection _section = HomeSection.recommend;
  LiveProvider _provider = LiveProvider.bilibili;
  final _search = TextEditingController();
  final _roomId = TextEditingController();
  final _directUrl = TextEditingController();
  final _cookie = TextEditingController();
  final TvosSessionStore _sessionStore = MethodChannelTvosSessionStore();
  final TvosWebSessionBridge _webSession = MethodChannelTvosWebSessionBridge();
  List<RoomRef> _list = [];
  bool _busy = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _ticket++;
    _search.dispose();
    _roomId.dispose();
    _directUrl.dispose();
    _cookie.dispose();
    super.dispose();
  }

  void _changeSection(HomeSection next) {
    setState(() {
      _section = next;
      _error = null;
    });
    if (next == HomeSection.recommend) _fetch();
  }

  Future<void> _fetch({bool search = false, bool reset = true}) async {
    if (!mounted) return;
    if (search && _search.text.trim().isEmpty) {
      setState(() {
        _error = '请先输入搜索关键词';
        _list = [];
      });
      return;
    }
    final ticket = ++_ticket;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _busy = reset;
      _loadingMore = !reset;
      _error = null;
      if (reset) _list = [];
    });
    try {
      final site = SiteRegistry.instance.get(_provider);
      final List<LiveRoomItem> items;
      final bool hasMore;
      if (search) {
        final result = await site.searchRooms(_search.text.trim(), page: page);
        items = result.items;
        hasMore = result.hasMore;
      } else {
        final result = await site.getRecommendRooms(page: page);
        items = result.items;
        hasMore = result.hasMore;
      }
      if (!mounted || ticket != _ticket) return;
      final rooms =
          items.map((item) => RoomRef.fromSearch(_provider, item)).toList();
      setState(() {
        _list = reset ? rooms : [..._list, ...rooms];
        _page = page;
        _hasMore = hasMore;
      });
    } catch (e) {
      if (mounted && ticket == _ticket) {
        setState(
          () => _error = '获取${search ? '搜索' : '推荐'}结果失败：${e.runtimeType}。'
              '部分平台需要登录或可能触发风控。',
        );
      }
    } finally {
      if (mounted && ticket == _ticket) {
        setState(() {
          _busy = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _loadMore() {
    if (_busy || _loadingMore || !_hasMore) return;
    unawaited(_fetch(search: _section == HomeSection.search, reset: false));
  }

  Future<void> _open(RoomRef room) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => LivePage(reference: room)));
    if (mounted) setState(() {});
  }

  void _openManual() {
    final id = _roomId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '请填写房间号');
      return;
    }
    unawaited(_open(RoomRef(provider: _provider, roomId: id, title: '房间 $id')));
  }

  void _openDirect() {
    final url = _directUrl.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(() => _error = '请输入合法的 http(s) 网络播放地址');
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => LivePage.direct(url)));
  }

  Future<void> _saveCookie() async {
    final cookie = _cookie.text.trim();
    try {
      SiteRegistry.instance.setSessionCookie(_provider, cookie);
      await _sessionStore.saveCookie(_provider, cookie);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('会话 Cookie 已设置并保存到 tvOS Keychain')),
      );
    } on MissingPluginException {
      // Windows analysis and unsupported hosts continue with the in-memory
      // value; the native tvOS host supplies the persistent implementation.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前环境没有 tvOS Keychain，已仅在本次运行中使用')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      _cookie.clear();
    }
  }

  Future<void> _webLogin() async {
    if (_provider != LiveProvider.xiaohongshu) {
      setState(() => _error = '当前首版网页登录仅支持小红书');
      return;
    }
    try {
      final result = await _webSession.login(_provider);
      SiteRegistry.instance.setSessionCookie(result.provider, result.cookie);
      await _sessionStore.saveCookie(result.provider, result.cookie);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网页会话已登录并保存到 tvOS Keychain')),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _error = '当前环境没有 tvOS 网页会话桥接，请使用手动 Cookie');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '网页登录失败：$e');
    }
  }

  Widget _siteSelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final provider in LiveProvider.values) ...[
              TvButton(
                label: provider.title,
                selected: _provider == provider,
                onPressed: () {
                  setState(() {
                    _provider = provider;
                    _error = null;
                    _list = [];
                    _page = 1;
                    _hasMore = false;
                  });
                  if (_section == HomeSection.recommend) _fetch();
                },
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
      );

  Widget _listView(List<RoomRef> rooms, {bool showMore = false}) =>
      rooms.isEmpty
          ? const Center(child: Text('暂时没有房间', style: TextStyle(fontSize: 24)))
          : GridView.builder(
              padding: const EdgeInsets.only(top: 20, bottom: 24),
              itemCount: rooms.length + (showMore && _hasMore ? 1 : 0),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisSpacing: 18,
                crossAxisSpacing: 18,
                childAspectRatio: 1.26,
              ),
              itemBuilder: (_, index) {
                if (index == rooms.length) {
                  return Center(
                    child: TvButton(
                      label: _loadingMore ? '正在加载…' : '加载更多',
                      icon:
                          _loadingMore ? Icons.hourglass_top : Icons.more_horiz,
                      onPressed: _loadingMore ? null : _loadMore,
                    ),
                  );
                }
                final room = rooms[index];
                return _RoomCard(room: room, onOpen: () => _open(room));
              },
            );

  Widget _body() {
    switch (_section) {
      case HomeSection.recommend:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _siteSelector(),
            const SizedBox(height: 16),
            Row(
              children: [
                TvButton(
                  label: '刷新推荐',
                  icon: Icons.refresh,
                  onPressed: _busy ? null : () => _fetch(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _provider.caveat,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _listView(_list, showMore: true),
            ),
          ],
        );
      case HomeSection.search:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _siteSelector(),
            const SizedBox(height: 8),
            Text(
              _provider.tvosSupportLabel,
              style: const TextStyle(color: Colors.white60, fontSize: 17),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onSubmitted: (_) => _fetch(search: true),
                    style: const TextStyle(fontSize: 24),
                    decoration: const InputDecoration(labelText: '搜索主播或直播间'),
                  ),
                ),
                const SizedBox(width: 16),
                TvButton(
                  label: '搜索',
                  icon: Icons.search,
                  onPressed: _busy ? null : () => _fetch(search: true),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomId,
                    onSubmitted: (_) => _openManual(),
                    style: const TextStyle(fontSize: 22),
                    decoration: const InputDecoration(labelText: '直接输入房间号'),
                  ),
                ),
                const SizedBox(width: 16),
                TvButton(
                  label: '进入房间',
                  icon: Icons.open_in_new,
                  onPressed: _openManual,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _directUrl,
                    style: const TextStyle(fontSize: 20),
                    onSubmitted: (_) => _openDirect(),
                    decoration: const InputDecoration(
                      labelText: '直接播放 HLS URL',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                TvButton(
                  label: '播放链接',
                  icon: Icons.play_arrow,
                  onPressed: _openDirect,
                ),
              ],
            ),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _listView(_list, showMore: true),
            ),
          ],
        );
      case HomeSection.favorites:
        return AnimatedBuilder(
          animation: RoomLibrary.instance,
          builder: (_, __) => _listView(RoomLibrary.instance.favorites),
        );
      case HomeSection.recent:
        return AnimatedBuilder(
          animation: RoomLibrary.instance,
          builder: (_, __) => Column(
            children: [
              Row(
                children: [
                  TvButton(
                    label: '清空历史',
                    icon: Icons.delete_outline,
                    onPressed: () => RoomLibrary.instance.clearRecent(),
                  ),
                ],
              ),
              Expanded(child: _listView(RoomLibrary.instance.recent)),
            ],
          ),
        );
      case HomeSection.settings:
        return ListView(
          children: [
            const Text(
              '播放器与账号',
              style: TextStyle(fontSize: 31, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: RoomLibrary.instance,
              builder: (_, __) => SwitchListTile(
                title: const Text('开启直播弹幕', style: TextStyle(fontSize: 24)),
                subtitle: const Text('弹幕接口成功连接时才会显示；暂不支持发送弹幕'),
                value: RoomLibrary.instance.danmakuEnabled,
                onChanged: (v) => RoomLibrary.instance.setDanmaku(v),
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              '账号会话（凭据保存到 tvOS Keychain）',
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 18),
            _siteSelector(),
            const SizedBox(height: 18),
            TextField(
              controller: _cookie,
              maxLines: 2,
              style: const TextStyle(fontSize: 20),
              decoration: const InputDecoration(
                labelText: '手动 Cookie（B站、斗鱼、抖音、快手、小红书）',
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                label: '仅在本次运行中使用',
                icon: Icons.lock_outline,
                onPressed: () => unawaited(_saveCookie()),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                label: '小红书网页登录',
                icon: Icons.language,
                onPressed: () => unawaited(_webLogin()),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              '本版本使用 AVPlayer，首版只承诺 HLS。'
              'FLV/RTMP 和 QuickJS 签名暂不支持；网页登录需要 tvOS 原生桥接。',
              style: TextStyle(fontSize: 19, color: Colors.white60),
            ),
            if (RoomLibrary.instance.persistenceWarning != null)
              Text(
                RoomLibrary.instance.persistenceWarning!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 45, vertical: 30),
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Simple Live',
                        style: TextStyle(
                            fontSize: 34, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'tvOS · dev',
                        style: TextStyle(color: Colors.white54, fontSize: 19),
                      ),
                      const SizedBox(height: 40),
                      for (final entry in HomeSection.values) ...[
                        SizedBox(
                          width: 220,
                          child: TvButton(
                            autofocus: entry == HomeSection.recommend,
                            selected: _section == entry,
                            label: switch (entry) {
                              HomeSection.recommend => '推荐',
                              HomeSection.search => '搜索 / 房间号',
                              HomeSection.favorites => '收藏',
                              HomeSection.recent => '历史',
                              HomeSection.settings => '设置',
                            },
                            icon: switch (entry) {
                              HomeSection.recommend => Icons.explore_outlined,
                              HomeSection.search => Icons.search,
                              HomeSection.favorites => Icons.star_border,
                              HomeSection.recent => Icons.history,
                              HomeSection.settings => Icons.settings_outlined,
                            },
                            onPressed: () => _changeSection(entry),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                const VerticalDivider(width: 35),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      Expanded(child: _body()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RoomCard extends StatefulWidget {
  const _RoomCard({required this.room, required this.onOpen});
  final RoomRef room;
  final VoidCallback onOpen;
  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Focus(
        onFocusChange: (v) => setState(() => _focused = v),
        child: InkWell(
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: _focused ? Colors.white : Colors.white24,
                width: _focused ? 3 : 1,
              ),
              color:
                  _focused ? const Color(0xFF273858) : const Color(0xFF171D2B),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                    child: widget.room.cover.isEmpty
                        ? const Center(child: Icon(Icons.live_tv, size: 64))
                        : Image.network(
                            widget.room.cover,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.live_tv, size: 56)),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.room.provider.title} · ${widget.room.anchor}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
