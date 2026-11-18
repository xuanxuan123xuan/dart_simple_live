import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:video_player/video_player.dart';
import 'danmaku_overlay.dart';
import 'tv_button.dart';
import 'playback_sources.dart';
import 'room_library.dart';
import 'site_registry.dart';
import 'tvos_playback.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.reference}) : directUrl = null;
  const LivePage.direct(String url, {super.key})
      : directUrl = url,
        reference = null;
  final RoomRef? reference;
  final String? directUrl;
  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  ResolvedRoom? _room;
  VideoPlayerController? _controller;
  final TvosPlaybackBackend _playback = AvPlayerHlsBackend();
  TvosPlaybackSession? _session;
  LiveDanmaku? _danmaku;
  Timer? _cleanup;
  final List<DanmakuEvent> _events = [];
  final Map<int, DateTime> _arrival = {};
  int _commentId = 0;
  int _token = 0;
  LivePlayQuality? _quality;
  List<String> _lines = [];
  Map<String, String> _headers = {};
  int _line = 0;
  bool _loading = false;
  bool _playing = false;
  bool _muted = false;
  bool _showControls = true;
  String? _error;
  String? _danmakuStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.directUrl != null) {
        unawaited(_loadDirect(widget.directUrl!));
      } else {
        unawaited(_loadRoom());
      }
    });
  }

  Future<void> _loadRoom() async {
    final ref = widget.reference;
    if (ref == null) return;
    final current = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resolved = await resolveRoom(ref);
      if (!mounted || current != _token) return;
      setState(() => _room = resolved);
      unawaited(RoomLibrary.instance.visited(resolved.reference));
      unawaited(_startDanmaku(resolved));
      await _selectQuality(resolved.qualities.first);
    } catch (e) {
      if (mounted && current == _token) {
        setState(() {
          _loading = false;
          _error = '直播间加载失败：${e.runtimeType}。'
              '请检查房间号、网络、登录要求和开播状态。';
        });
      }
    }
  }

  Future<void> _loadDirect(String url) async {
    final current = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    final success = await _tryStream(url, const {}, current);
    if (mounted && current == _token) {
      setState(() {
        _loading = false;
        if (!success) _error = '播放失败。请检查是否为有效的 HLS 视频流。';
      });
    }
  }

  Future<void> _selectQuality(LivePlayQuality quality) async {
    final room = _room;
    if (room == null) return;
    final current = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _quality = quality;
    });
    try {
      final result = await room.site.getPlayUrls(
        detail: room.detail,
        quality: quality,
      );
      if (!mounted || current != _token) return;
      final candidates = hlsOnly(result);
      if (candidates.isEmpty) {
        setState(() {
          _loading = false;
          _lines = [];
          _error = playbackFailureHint(result.urls);
        });
        return;
      }
      setState(() {
        _lines = candidates;
        _headers = result.headers ?? const {};
        _line = 0;
      });
      await _tryLines(candidates, _headers, current, preferred: 0);
    } catch (e) {
      if (mounted && current == _token) {
        setState(() {
          _loading = false;
          _error = '获取视频地址失败：${e.runtimeType}。'
              '该平台可能需要 JS 签名、Cookie 或未提供 HLS。';
        });
      }
    }
  }

  Future<void> _changeLine(int index) async {
    if (index < 0 || index >= _lines.length) return;
    final current = ++_token;
    setState(() {
      _loading = true;
      _error = null;
      _line = index;
    });
    await _tryLines(_lines, _headers, current, preferred: index);
  }

  Future<void> _tryLines(
    List<String> urls,
    Map<String, String> headers,
    int current, {
    required int preferred,
  }) async {
    final order = [
      preferred,
      ...List.generate(urls.length, (i) => i).where((i) => i != preferred),
    ];
    for (final index in order) {
      if (!mounted || current != _token) return;
      if (await _tryStream(urls[index], headers, current)) {
        if (mounted && current == _token) {
          setState(() {
            _line = index;
            _loading = false;
            _error = null;
          });
        }
        return;
      }
    }
    if (mounted && current == _token) {
      setState(() {
        _loading = false;
        _error = '所有 HLS 线路均无法播放。可能是鉴权、源站限制、'
            '不兼容的编码或播放器失败。';
      });
    }
  }

  Future<bool> _tryStream(
    String url,
    Map<String, String> headers,
    int current,
  ) async {
    TvosPlaybackSession? nextSession;
    try {
      nextSession = await _playback.open(
        url,
        headers: headers,
        timeout: const Duration(seconds: 20),
      );
      final next = nextSession.controller;
      if (!mounted || current != _token) {
        await nextSession.dispose();
        return false;
      }
      await next.setVolume(_muted ? 0 : 1);
      await next.play();
      if (!mounted || current != _token) {
        await nextSession.dispose();
        return false;
      }
      final previous = _controller;
      final previousSession = _session;
      if (previous != null) previous.removeListener(_onVideoUpdate);
      setState(() {
        _controller = next;
        _session = nextSession;
        _playing = true;
      });
      next.addListener(_onVideoUpdate);
      if (previousSession != null) {
        unawaited(previousSession.dispose());
      } else if (previous != null) {
        unawaited(previous.dispose());
      }
      return true;
    } catch (_) {
      if (nextSession != null) {
        try {
          await nextSession.dispose();
        } catch (_) {}
      }
      return false;
    }
  }

  void _onVideoUpdate() {
    final video = _controller;
    if (video == null || !mounted) return;
    if (video.value.hasError) {
      if (_error == null) setState(() => _error = '播放器发生错误，请尝试其他线路或重新加载。');
    }
    if (_playing != video.value.isPlaying) {
      setState(() => _playing = video.value.isPlaying);
    }
  }

  Future<void> _startDanmaku(ResolvedRoom resolved) async {
    await _stopDanmaku();
    if (!RoomLibrary.instance.danmakuEnabled || !mounted) return;
    final args = resolved.detail.danmakuData;
    if (args == null) {
      setState(() => _danmakuStatus = '此房间没有可用弹幕连接参数');
      return;
    }
    final danmaku = resolved.site.getDanmaku();
    _danmaku = danmaku;
    danmaku.onMessage = (message) {
      if (!mounted ||
          !RoomLibrary.instance.danmakuEnabled ||
          message.type != LiveMessageType.chat ||
          message.message.isEmpty) {
        return;
      }
      final id = ++_commentId;
      setState(() {
        _events.add(DanmakuEvent(id, message, id % 8));
        _arrival[id] = DateTime.now();
        while (_events.length > 36) {
          final first = _events.removeAt(0);
          _arrival.remove(first.id);
        }
      });
    };
    danmaku.onReady = () {
      if (mounted) setState(() => _danmakuStatus = null);
    };
    danmaku.onClose = (reason) {
      if (mounted) setState(() => _danmakuStatus = '弹幕连接中断，可尝试重新打开直播间');
    };
    _cleanup = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final before = _events.length;
      final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
      _events.removeWhere(
        (event) => (_arrival[event.id] ?? cutoff).isBefore(cutoff),
      );
      _arrival.removeWhere((id, timestamp) => timestamp.isBefore(cutoff));
      if (_events.length != before) setState(() {});
    });
    try {
      await danmaku.start(args);
    } catch (_) {
      if (mounted) setState(() => _danmakuStatus = '弹幕连接失败');
    }
  }

  Future<void> _stopDanmaku() async {
    _cleanup?.cancel();
    _cleanup = null;
    final old = _danmaku;
    _danmaku = null;
    if (old != null) {
      old.onMessage = null;
      old.onReady = null;
      old.onClose = null;
      try {
        await old.stop();
      } catch (_) {}
    }
  }

  void _togglePlay() {
    final v = _controller;
    if (v == null) return;
    unawaited(v.value.isPlaying ? v.pause() : v.play());
  }

  void _toggleMute() {
    final v = _controller;
    setState(() => _muted = !_muted);
    if (v != null) unawaited(v.setVolume(_muted ? 0 : 1));
  }

  Future<void> _toggleFavorite() async {
    final room = _room;
    if (room == null) return;
    await RoomLibrary.instance.toggleFavorite(room.reference);
    if (mounted) setState(() {});
  }

  Future<void> _toggleDanmaku() async {
    final enabled = !RoomLibrary.instance.danmakuEnabled;
    await RoomLibrary.instance.setDanmaku(enabled);
    if (enabled) {
      final room = _room;
      if (room != null) unawaited(_startDanmaku(room));
    } else {
      await _stopDanmaku();
      if (mounted) {
        setState(() {
          _events.clear();
          _arrival.clear();
        });
      }
    }
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.select && !_showControls) {
      setState(() => _showControls = true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _token++;
    unawaited(_stopDanmaku());
    final video = _controller;
    if (video != null) {
      video.removeListener(_onVideoUpdate);
    }
    final session = _session;
    if (session != null) {
      unawaited(session.dispose());
    } else if (video != null) {
      unawaited(video.dispose());
    }
    unawaited(_playback.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller;
    final room = _room;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: v != null && v.value.isInitialized
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: v.value.aspectRatio > 0
                                ? v.value.aspectRatio
                                : 16 / 9,
                            child: VideoPlayer(v),
                          ),
                        )
                      : Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : const Icon(Icons.live_tv_outlined, size: 88),
                        ),
                ),
              ),
              if (RoomLibrary.instance.danmakuEnabled)
                Positioned.fill(child: DanmakuOverlay(events: _events)),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 18,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      TvButton(
                        label: '返回',
                        icon: Icons.arrow_back,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          room?.detail.title ??
                              (widget.reference?.title ?? 'HLS 直接播放'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (room != null)
                        TvButton(
                          label: RoomLibrary.instance.isFavorite(room.reference)
                              ? '已收藏'
                              : '收藏',
                          icon: Icons.star_outline,
                          onPressed: _toggleFavorite,
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Positioned(
                  top: 120,
                  left: 32,
                  right: 32,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xD9773300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!, style: const TextStyle(fontSize: 20)),
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(30, 40, 30, 22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_showControls) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              TvButton(
                                label: _playing ? '暂停' : '播放',
                                icon: _playing ? Icons.pause : Icons.play_arrow,
                                onPressed: v == null ? null : _togglePlay,
                              ),
                              const SizedBox(width: 12),
                              TvButton(
                                label: _muted ? '取消静音' : '静音',
                                icon:
                                    _muted ? Icons.volume_off : Icons.volume_up,
                                onPressed: _toggleMute,
                              ),
                              const SizedBox(width: 12),
                              if (room != null) ...[
                                PopupMenuButton<LivePlayQuality>(
                                  enabled: !_loading,
                                  tooltip: '选择画质',
                                  onSelected: (quality) =>
                                      unawaited(_selectQuality(quality)),
                                  itemBuilder: (_) => [
                                    for (final q in room.qualities)
                                      PopupMenuItem(
                                        value: q,
                                        child: Text(q.quality),
                                      ),
                                  ],
                                  child: _MenuLabel(
                                    '画质 ${_quality?.quality ?? '加载中'} ▾',
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              if (_lines.length > 1) ...[
                                PopupMenuButton<int>(
                                  enabled: !_loading,
                                  tooltip: '选择线路',
                                  onSelected: (line) =>
                                      unawaited(_changeLine(line)),
                                  itemBuilder: (_) => [
                                    for (var i = 0; i < _lines.length; i++)
                                      PopupMenuItem(
                                        value: i,
                                        child: Text('线路 ${i + 1}'),
                                      ),
                                  ],
                                  child: _MenuLabel('线路 ${_line + 1} ▾'),
                                ),
                                const SizedBox(width: 12),
                              ],
                              if (room != null) ...[
                                TvButton(
                                  label: RoomLibrary.instance.danmakuEnabled
                                      ? '关闭弹幕'
                                      : '开启弹幕',
                                  icon: Icons.chat_bubble_outline,
                                  onPressed: _toggleDanmaku,
                                ),
                                const SizedBox(width: 12),
                                TvButton(
                                  label: '重新连接',
                                  icon: Icons.refresh,
                                  onPressed: () => unawaited(_loadRoom()),
                                ),
                                const SizedBox(width: 12),
                                TvButton(
                                  label: '隐藏工具栏',
                                  icon: Icons.visibility_off,
                                  onPressed: () =>
                                      setState(() => _showControls = false),
                                ),
                              ] else
                                TvButton(
                                  label: '重新播放',
                                  icon: Icons.refresh,
                                  onPressed: () =>
                                      unawaited(_loadDirect(widget.directUrl!)),
                                ),
                            ],
                          ),
                        ),
                        if (_danmakuStatus != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _danmakuStatus!,
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Siri Remote：方向键切换焦点，确认键操作，返回键退出',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withAlpha(120),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF253148),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white54),
        ),
        child: Text(text, style: const TextStyle(fontSize: 21)),
      );
}
