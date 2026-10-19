import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Audio-only presentation for a live room. Playback state and actions are
/// supplied by the room so this widget stays independent of its controller.
class LiveListeningPanel extends StatelessWidget {
  const LiveListeningPanel({
    super.key,
    required this.avatarUrl,
    required this.userName,
    required this.title,
    required this.isListening,
    required this.isChanging,
    required this.canToggleMode,
    required this.isPlaying,
    required this.isBuffering,
    required this.isFetching,
    required this.isOffline,
    required this.errorMessage,
    required this.volume,
    required this.onTogglePlayback,
    required this.onVolumeChanged,
    required this.onReturnToVideo,
    required this.showFullscreenExit,
    required this.onExitFullscreen,
  });

  final String avatarUrl;
  final String userName;
  final String title;
  final bool isListening;
  final bool isChanging;
  final bool canToggleMode;
  final bool isPlaying;
  final bool isBuffering;
  final bool isFetching;
  final bool isOffline;
  final String? errorMessage;
  final double volume;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onReturnToVideo;
  final bool showFullscreenExit;
  final VoidCallback onExitFullscreen;

  String get _status {
    final error = errorMessage?.trim();
    if (error != null && error.isNotEmpty) {
      return '播放异常：$error';
    }
    if (isOffline) {
      return '主播暂未开播';
    }
    if (isFetching && isBuffering) {
      return '正在获取播放地址 · 正在缓冲';
    }
    if (isFetching) {
      return '正在获取播放地址';
    }
    if (isBuffering) {
      return '正在缓冲';
    }
    if (isChanging) {
      return isListening ? '正在切换到视频…' : '正在切换到听直播…';
    }
    return isPlaying ? '正在播放' : '已暂停';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 360 || constraints.maxWidth < 520;
        return SizedBox.expand(
          child: ColoredBox(
            color: const Color(0xFF0B0D12),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math
                            .max(0.0, constraints.maxHeight - 24)
                            .toDouble(),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: math
                              .min(
                                math.max(0.0, constraints.maxWidth - 32),
                                640.0,
                              )
                              .toDouble(),
                          child: compact
                              ? constraints.maxWidth < 300
                                  ? _buildNarrowContent(context)
                                  : _buildCompactContent(context)
                              : _buildExpandedContent(context),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showFullscreenExit)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: IconButton(
                        key: const ValueKey('listening-exit-fullscreen'),
                        tooltip: '退出全屏',
                        onPressed: onExitFullscreen,
                        icon: const Icon(
                          Icons.fullscreen_exit,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildAvatar(48),
            const SizedBox(width: 12),
            Expanded(child: _buildRoomText(context)),
          ],
        ),
        const SizedBox(height: 8),
        _buildActions(context, compact: true),
      ],
    );
  }

  Widget _buildNarrowContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildAvatar(40),
            const SizedBox(width: 10),
            Expanded(child: _buildRoomText(context)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _buildPlayPauseButton(compact: true),
            const Icon(Icons.volume_down, color: Colors.white70, size: 18),
            Expanded(child: _buildVolumeSlider()),
          ],
        ),
        if (isListening)
          Align(
            alignment: Alignment.centerRight,
            child: _buildReturnToVideoButton(),
          ),
      ],
    );
  }

  Widget _buildExpandedContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildAvatar(80),
        const SizedBox(height: 14),
        _buildRoomText(context, centered: true),
        const SizedBox(height: 20),
        _buildActions(context, compact: false),
      ],
    );
  }

  Widget _buildAvatar(double size) {
    final imageUrl = avatarUrl.trim();
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: imageUrl.isEmpty
            ? _buildAvatarFallback()
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildAvatarFallback(),
              ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return const ColoredBox(
      color: Color(0xFF30343B),
      child: Icon(Icons.person, color: Colors.white70, size: 30),
    );
  }

  Widget _buildRoomText(BuildContext context, {bool centered = false}) {
    final name = userName.trim();
    final roomTitle = title.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (name.isNotEmpty)
          Text(
            name,
            key: const ValueKey('listening-user-name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        if (roomTitle.isNotEmpty)
          Text(
            roomTitle,
            key: const ValueKey('listening-room-title'),
            maxLines: centered ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
        const SizedBox(height: 4),
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            if (isListening)
              const Text(
                '听播中',
                key: ValueKey('listening-active-label'),
                style: TextStyle(
                  color: Color(0xFF9ED6FF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            _buildStatusIndicator(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                _status,
                key: const ValueKey('listening-playback-status'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  color: _hasError ? const Color(0xFFFFB4AB) : Colors.white70,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool get _hasError => errorMessage?.trim().isNotEmpty ?? false;

  Widget _buildStatusIndicator() {
    if (isChanging || isBuffering || isFetching) {
      return const SizedBox(
        key: ValueKey('listening-buffering-indicator'),
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: Colors.white70,
        ),
      );
    }
    if (_hasError) {
      return const Icon(
        Icons.error_outline,
        size: 14,
        color: Color(0xFFFFB4AB),
      );
    }
    if (isOffline) {
      return const Icon(
        Icons.radio_button_unchecked,
        size: 12,
        color: Colors.white60,
      );
    }
    return Icon(
      isPlaying ? Icons.graphic_eq : Icons.pause_circle_outline,
      size: 14,
      color: Colors.white70,
    );
  }

  Widget _buildActions(BuildContext context, {required bool compact}) {
    if (!compact) {
      return Row(
        children: [
          _buildPlayPauseButton(compact: false),
          if (isListening) _buildReturnToVideoButton(),
          const SizedBox(width: 8),
          const Icon(Icons.volume_down, color: Colors.white70, size: 20),
          Expanded(child: _buildVolumeSlider()),
          const Icon(Icons.volume_up, color: Colors.white70, size: 20),
        ],
      );
    }

    return Row(
      children: [
        _buildPlayPauseButton(compact: true),
        const Icon(Icons.volume_down, color: Colors.white70, size: 18),
        Expanded(child: _buildVolumeSlider()),
        if (isListening) _buildReturnToVideoButton(),
      ],
    );
  }

  Widget _buildPlayPauseButton({required bool compact}) {
    return IconButton(
      key: const ValueKey('listening-play-pause'),
      tooltip: isPlaying ? '暂停' : '播放',
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      constraints:
          compact ? const BoxConstraints.tightFor(width: 42, height: 42) : null,
      padding: compact ? EdgeInsets.zero : null,
      onPressed: isChanging ? null : onTogglePlayback,
      icon: Icon(
        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
        color: Colors.white,
        size: compact ? 30 : 34,
      ),
    );
  }

  Widget _buildVolumeSlider() {
    return Slider(
      key: const ValueKey('listening-volume-slider'),
      min: 0,
      max: 1,
      value: volume.clamp(0.0, 1.0).toDouble(),
      onChanged: onVolumeChanged,
    );
  }

  Widget _buildReturnToVideoButton() {
    return TextButton.icon(
      key: const ValueKey('listening-return-to-video'),
      onPressed: isChanging || !canToggleMode ? null : onReturnToVideo,
      icon: const Icon(Icons.videocam_outlined, size: 18),
      label: const Text('返回视频'),
      style: TextButton.styleFrom(foregroundColor: Colors.white),
    );
  }
}
