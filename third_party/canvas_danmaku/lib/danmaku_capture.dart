import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

typedef DanmakuCaptureFrameCallback = FutureOr<void> Function(
  DanmakuCaptureFrame frame,
);

/// Optional recording hook for the renderer. Capture is disabled by default.
///
/// Set [enabled] to true to receive a snapshot immediately and then at most
/// once per [frameInterval]. Frames contain compact item placements and only
/// the PNG sprites that have not been delivered by an earlier frame.
class DanmakuCaptureController extends ChangeNotifier {
  DanmakuCaptureController({
    required this.onFrame,
    this.frameInterval = const Duration(milliseconds: 16),
    this.mediaPosition,
    this.maxQueuedFrames = 120,
    this.onError,
  })  : assert(frameInterval > Duration.zero),
        assert(maxQueuedFrames > 0);

  final DanmakuCaptureFrameCallback onFrame;
  final Duration frameInterval;
  final Duration Function()? mediaPosition;
  final int maxQueuedFrames;
  final void Function(Object error, StackTrace stackTrace)? onError;

  bool _enabled = false;
  int? _lastCaptureTick;
  int _queuedFrames = 0;
  int _nextSpriteId = 0;
  DanmakuCaptureFrame? _latestFrame;
  Future<void> _deliveryTail = Future<void>.value();

  final Map<String, _CachedSprite> _spriteCache = {};

  bool get enabled => _enabled;
  DanmakuCaptureFrame? get latestFrame => _latestFrame;

  /// Waits until every accepted snapshot has reached [onFrame].
  Future<void> flush() => _deliveryTail;

  /// Reuses cached sprite encodes while delivering them again in a new
  /// recording session. Call after disabling capture and flushing the prior
  /// session.
  Future<void> reset() async {
    if (_enabled) {
      throw StateError('Disable danmaku capture before resetting a session.');
    }
    await flush();
    for (final sprite in _spriteCache.values) {
      sprite.delivered = false;
    }
    _lastCaptureTick = null;
    _latestFrame = null;
  }

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _lastCaptureTick = null;
    notifyListeners();
  }

  /// Called by the renderer after the item painters have updated their
  /// positions. Returns false when capture is disabled, throttled, or the
  /// bounded delivery queue has filled. Snapshot callbacks are delivered in
  /// order even if an earlier PNG encode is slow.
  bool capture({
    required int rendererTickMilliseconds,
    required Size viewportSize,
    double opacity = 1,
    required List<DanmakuCaptureSource> sources,
  }) {
    if (!_enabled) return false;
    final lastCaptureTick = _lastCaptureTick;
    if (lastCaptureTick != null &&
        rendererTickMilliseconds >= lastCaptureTick &&
        rendererTickMilliseconds - lastCaptureTick <
            frameInterval.inMilliseconds) {
      return false;
    }
    if (_queuedFrames >= maxQueuedFrames) {
      _enabled = false;
      _reportError(
        StateError(
          'Danmaku capture exceeded its $maxQueuedFrames-frame delivery queue.',
        ),
        StackTrace.current,
      );
      return false;
    }

    _lastCaptureTick = rendererTickMilliseconds;
    late final _CapturedFrame snapshot;
    try {
      snapshot = _prepareFrame(
        rendererTickMilliseconds: rendererTickMilliseconds,
        viewportSize: viewportSize,
        opacity: opacity,
        sources: sources,
      );
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      return false;
    }
    _queuedFrames++;
    final delivery = _deliveryTail.then(
      (_) => _deliverFrame(snapshot),
    );
    _deliveryTail = delivery;
    unawaited(delivery);
    return true;
  }

  _CapturedFrame _prepareFrame({
    required int rendererTickMilliseconds,
    required Size viewportSize,
    required double opacity,
    required List<DanmakuCaptureSource> sources,
  }) {
    final capturedAt = DateTime.now();
    final position = mediaPosition?.call();
    final placements = <DanmakuCapturePlacement>[];
    final activeKeys = <String>{};
    final referencedSprites = <_CachedSprite>{};

    for (final source in sources) {
      activeKeys.add(source.visualKey);
      var sprite = _spriteCache[source.visualKey];
      if (sprite == null) {
        sprite = _CachedSprite(
          id: 'danmaku-sprite-${++_nextSpriteId}',
          pngBytes: source.renderPng(),
        );
        _spriteCache[source.visualKey] = sprite;
      }
      referencedSprites.add(sprite);
      placements.add(
        DanmakuCapturePlacement(
          spriteId: sprite.id,
          x: source.x,
          y: source.y,
          width: source.width,
          height: source.height,
          opacity: source.opacity,
          transform: source.transform,
          transformOriginX: source.transformOriginX,
          transformOriginY: source.transformOriginY,
        ),
      );
    }

    _spriteCache.removeWhere((key, _) => !activeKeys.contains(key));
    return _CapturedFrame(
      rendererTickMilliseconds: rendererTickMilliseconds,
      capturedAt: capturedAt,
      mediaPosition: position,
      viewportSize: viewportSize,
      opacity: opacity,
      placements: List.unmodifiable(placements),
      referencedSprites: Set.unmodifiable(referencedSprites),
    );
  }

  Future<void> _deliverFrame(_CapturedFrame snapshot) async {
    try {
      final assets = <DanmakuCaptureSprite>[];
      for (final cached in snapshot.referencedSprites.where(
        (sprite) => !sprite.delivered,
      )) {
        assets.add(
          DanmakuCaptureSprite(
            id: cached.id,
            pngBytes: await cached.pngBytes,
          ),
        );
      }
      final frame = DanmakuCaptureFrame(
        rendererTickMilliseconds: snapshot.rendererTickMilliseconds,
        capturedAt: snapshot.capturedAt,
        mediaPosition: snapshot.mediaPosition,
        viewportSize: snapshot.viewportSize,
        opacity: snapshot.opacity,
        placements: snapshot.placements,
        sprites: List.unmodifiable(assets),
      );
      await onFrame(frame);
      for (final cached in snapshot.referencedSprites) {
        cached.delivered = true;
      }
      _latestFrame = frame;
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    } finally {
      _queuedFrames--;
    }
  }

  void _reportError(Object error, StackTrace stackTrace) {
    try {
      onError?.call(error, stackTrace);
    } catch (_) {
      // An error handler must not break ordered delivery of later frames.
    }
  }
}

/// Renderer-side description of one item to include in a captured frame.
///
/// [renderPng] is called only when [visualKey] has not been captured before
/// during the current active period of that item.
class DanmakuCaptureSource {
  const DanmakuCaptureSource({
    required this.visualKey,
    required this.renderPng,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.opacity = 1,
    this.transform,
    this.transformOriginX = 0,
    this.transformOriginY = 0,
  });

  final String visualKey;
  final Future<Uint8List> Function() renderPng;
  final double x;
  final double y;
  final double width;
  final double height;
  final double opacity;

  /// Optional 4x4 column-major transform, matching Canvas.transform.
  final List<double>? transform;

  /// The image pixel coordinate that corresponds to the transform origin.
  final double transformOriginX;
  final double transformOriginY;
}

/// PNG sprite asset emitted by a [DanmakuCaptureController].
class DanmakuCaptureSprite {
  const DanmakuCaptureSprite({required this.id, required this.pngBytes});

  final String id;
  final Uint8List pngBytes;
}

/// A sprite placement for one renderer frame.
class DanmakuCapturePlacement {
  const DanmakuCapturePlacement({
    required this.spriteId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.opacity,
    this.transform,
    this.transformOriginX = 0,
    this.transformOriginY = 0,
  });

  final String spriteId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double opacity;
  final List<double>? transform;
  final double transformOriginX;
  final double transformOriginY;
}

/// One compact snapshot of the visible danmaku layer.
class DanmakuCaptureFrame {
  const DanmakuCaptureFrame({
    required this.rendererTickMilliseconds,
    required this.capturedAt,
    this.mediaPosition,
    required this.viewportSize,
    this.opacity = 1,
    required this.placements,
    required this.sprites,
  });

  /// Milliseconds from this danmaku renderer's stopwatch.
  final int rendererTickMilliseconds;

  /// Wall-clock time at which the renderer snapshot was taken.
  final DateTime capturedAt;

  /// The caller's playback position sampled synchronously at paint time.
  final Duration? mediaPosition;

  final Size viewportSize;
  final double opacity;
  final List<DanmakuCapturePlacement> placements;

  /// Only the sprite PNGs first referenced in this frame.
  final List<DanmakuCaptureSprite> sprites;
}

/// Paints a captured frame for offline replay using the PNG sprites already
/// registered by their IDs. The viewport clip matches [DanmakuScreen].
class DanmakuCaptureReplay {
  static void paintFrame(
    ui.Canvas canvas,
    DanmakuCaptureFrame frame,
    Map<String, ui.Image> sprites,
  ) {
    canvas.save();
    canvas.clipRect(Offset.zero & frame.viewportSize);
    final frameOpacity = frame.opacity.clamp(0.0, 1.0);
    canvas.saveLayer(
      Offset.zero & frame.viewportSize,
      ui.Paint()
        ..color = Color.fromARGB((frameOpacity * 255).round(), 255, 255, 255),
    );
    for (final placement in frame.placements) {
      final image = sprites[placement.spriteId];
      if (image == null) continue;

      final opacity = placement.opacity.clamp(0.0, 1.0);
      final paint = ui.Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..color = Color.fromARGB((opacity * 255).round(), 255, 255, 255);
      final sourceRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final destinationRect = Rect.fromLTWH(
        0,
        0,
        placement.width,
        placement.height,
      );

      canvas.save();
      final transform = placement.transform;
      if (transform != null) {
        canvas.translate(
          placement.x + placement.transformOriginX,
          placement.y + placement.transformOriginY,
        );
        canvas.transform(Float64List.fromList(transform));
        canvas.drawImageRect(
          image,
          sourceRect,
          destinationRect.shift(
            Offset(-placement.transformOriginX, -placement.transformOriginY),
          ),
          paint,
        );
      } else {
        canvas.drawImageRect(
          image,
          sourceRect,
          destinationRect.shift(Offset(placement.x, placement.y)),
          paint,
        );
      }
      canvas.restore();
    }
    canvas.restore();
    canvas.restore();
  }
}

class _CachedSprite {
  _CachedSprite({required this.id, required this.pngBytes});

  final String id;
  final Future<Uint8List> pngBytes;
  bool delivered = false;
}

class _CapturedFrame {
  const _CapturedFrame({
    required this.rendererTickMilliseconds,
    required this.capturedAt,
    required this.mediaPosition,
    required this.viewportSize,
    required this.opacity,
    required this.placements,
    required this.referencedSprites,
  });

  final int rendererTickMilliseconds;
  final DateTime capturedAt;
  final Duration? mediaPosition;
  final Size viewportSize;
  final double opacity;
  final List<DanmakuCapturePlacement> placements;
  final Set<_CachedSprite> referencedSprites;
}
