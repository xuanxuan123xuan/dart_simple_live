import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/live_listening_panel.dart';

LiveListeningPanel _panel({
  bool isListening = true,
  bool isChanging = false,
  bool isPlaying = true,
  bool isBuffering = false,
  bool isFetching = false,
  bool isOffline = false,
  String? errorMessage,
  bool showFullscreenExit = false,
  VoidCallback? onTogglePlayback,
  ValueChanged<double>? onVolumeChanged,
  VoidCallback? onReturnToVideo,
  VoidCallback? onExitFullscreen,
}) {
  return LiveListeningPanel(
    avatarUrl: '',
    userName: '主播名称',
    title: '一个较长的直播间标题，用于检查窄布局',
    isListening: isListening,
    isChanging: isChanging,
    canToggleMode: true,
    isPlaying: isPlaying,
    isBuffering: isBuffering,
    isFetching: isFetching,
    isOffline: isOffline,
    errorMessage: errorMessage,
    volume: 0.5,
    onTogglePlayback: onTogglePlayback ?? () {},
    onVolumeChanged: onVolumeChanged ?? (_) {},
    onReturnToVideo: onReturnToVideo ?? () {},
    showFullscreenExit: showFullscreenExit,
    onExitFullscreen: onExitFullscreen ?? () {},
  );
}

Widget _host(Size size, Widget child, {double textScale = 1}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('compact panel fits in a small player and exposes live status',
      (tester) async {
    for (final size in [const Size(320, 180), const Size(240, 135)]) {
      await tester.pumpWidget(
        _host(size, _panel(isBuffering: true), textScale: 2),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('听播中'), findsOneWidget);
      expect(find.text('正在缓冲'), findsOneWidget);
      expect(find.text('返回视频'), findsOneWidget);
    }
  });

  testWidgets('playback, volume, return, and fullscreen controls call back',
      (tester) async {
    var playbackToggles = 0;
    var volume = -1.0;
    var returnsToVideo = 0;
    var exitsFullscreen = 0;
    await tester.pumpWidget(
      _host(
        const Size(800, 500),
        _panel(
          showFullscreenExit: true,
          onTogglePlayback: () => playbackToggles++,
          onVolumeChanged: (value) => volume = value,
          onReturnToVideo: () => returnsToVideo++,
          onExitFullscreen: () => exitsFullscreen++,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('listening-play-pause')));
    await tester.tap(find.byKey(const ValueKey('listening-return-to-video')));
    await tester.tap(find.byKey(const ValueKey('listening-exit-fullscreen')));
    tester
        .widget<Slider>(find.byKey(const ValueKey('listening-volume-slider')))
        .onChanged!(0.75);

    expect(playbackToggles, 1);
    expect(returnsToVideo, 1);
    expect(exitsFullscreen, 1);
    expect(volume, 0.75);
    expect(find.text('听播中'), findsOneWidget);
  });

  testWidgets('offline and playback errors remain visible', (tester) async {
    await tester.pumpWidget(
      _host(const Size(800, 500), _panel(isOffline: true)),
    );
    expect(find.text('主播暂未开播'), findsOneWidget);

    await tester.pumpWidget(
      _host(const Size(800, 500), _panel(errorMessage: '网络连接中断')),
    );
    expect(find.text('播放异常：网络连接中断'), findsOneWidget);

    await tester.pumpWidget(
      _host(const Size(800, 500), _panel(isFetching: true)),
    );
    expect(find.text('正在获取播放地址'), findsOneWidget);
  });
}
