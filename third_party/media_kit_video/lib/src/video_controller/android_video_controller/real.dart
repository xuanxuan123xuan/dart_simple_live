/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/surface_binding.dart';

/// {@template android_video_controller}
///
/// AndroidVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native JNI & C/C++ used on Android.
///
/// {@endtemplate}
class AndroidVideoController extends PlatformVideoController {
  /// Whether [AndroidVideoController] is supported on the current platform or not.
  static bool get supported => Platform.isAndroid;

  /// Pointer address to the global object reference of `android.view.Surface` i.e. `(intptr_t)(*android.view.Surface)`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);

  /// Shared lock for surface bindings and video lifecycle operations.
  final lock = Lock();

  final int _handle;

  late final AndroidSurfaceBinding _surfaceBinding;

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    // ORDER IS IMPORTANT.
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  /// Hook to attach --wid & --vo properties before video output is initialized.
  Future<void> onLoadHook() async {
    // This setup is important to take away control of android.view.Surface from libmpv, when the currently playing gets switched.
    // Not doing so will cause MediaCodec usage inside libavcodec to incorrectly fail with error (because this android.view.Surface would be used twice):
    // "native_window_api_connect returned an error: Invalid argument (-22)" & next less-efficient hwdec will be used redundantly.
    return _surfaceBinding.onLoad(
      isRectValid: () =>
          (rect.value?.width ?? 0.0) > 1.0 && (rect.value?.height ?? 0.0) > 1.0,
    );
  }

  /// Hook to detach --wid & --vo properties before video output is disposed.
  Future<void> onUnloadHook() async {
    return _surfaceBinding.onUnload();
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;

  /// {@macro android_video_controller}
  AndroidVideoController._(super.player, super.configuration,
      {required int handle})
      : _handle = handle {
    _surfaceBinding = AndroidSurfaceBinding(
      lock: lock,
      writeProperty: setProperty,
      vo: configuration.vo!,
      compatibilityMode: configuration.vo == 'mediacodec_embed',
      onDiagnostic: _emitBindingDiagnostic,
    );
    platform.onLoadHooks.add(onLoadHook);
    platform.onUnloadHooks.add(onUnloadHook);
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => _surfaceBinding.runExclusive(() async {
        if ([0, null].contains(event.dw) || [0, null].contains(event.dh)) {
          return;
        }

        final int width;
        final int height;
        if (event.rotate == 0 || event.rotate == 180) {
          width = event.dw ?? 0;
          height = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          width = event.dh ?? 0;
          height = event.dw ?? 0;
        }

        _emitDiagnostic(
          'video_params',
          stage: 'video_parameters_available',
          fields: {
            'width': width,
            'height': height,
            'rotate': event.rotate,
            'valid': true,
            'reason': 'video_params_available',
            'source': 'video_params',
            'renderConfirmed': 'unknown',
            'level': 'info',
          },
        );

        await _channel.invokeMethod(
          'VideoOutputManager.SetSurfaceSize',
          {
            'handle': _handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
          },
        );

        rect.value = Rect.fromLTWH(
          0.0,
          0.0,
          width.toDouble(),
          height.toDouble(),
        );

        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      }),
    );
  }

  static const Set<String> _diagnosticFieldAllowlist = {
    'textureId',
    'surfaceIdentity',
    'bindRevision',
    'oldWid',
    'wid',
    'width',
    'height',
    'rotate',
    'valid',
    'reason',
    'level',
    'error',
    'source',
    'renderConfirmed',
  };
  static final RegExp _diagnosticTokenPattern =
      RegExp(r'^[A-Za-z0-9_.$-]{1,128}$');
  static final RegExp _diagnosticEventPattern =
      RegExp(r'^[A-Za-z0-9_.-]{1,64}$');

  void _emitBindingDiagnostic(String event, Map<String, Object?> fields) {
    final Object? rawStage = fields['stage'];
    _emitDiagnostic(
      event,
      stage: rawStage is String ? rawStage : 'surface_binding',
      fields: fields,
    );
  }

  /// Emits a small allowlisted record and isolates callback failures.
  void _emitDiagnostic(
    String event, {
    required String stage,
    Map<String, Object?> fields = const {},
  }) {
    final callback = configuration.onDiagnostic;
    if (callback == null) return;

    final safeFields = <String, Object?>{};
    for (final entry in fields.entries) {
      if (!_diagnosticFieldAllowlist.contains(entry.key)) continue;
      final value = entry.value;
      if (value is bool || value is int) {
        safeFields[entry.key] = value;
      } else if (value is double && value.isFinite) {
        safeFields[entry.key] = value;
      } else if (value is String && _isDiagnosticToken(value)) {
        safeFields[entry.key] = value;
      }
    }

    safeFields.addAll({
      'handle': _handle,
      'vo': _safeConfigurationValue(configuration.vo),
      'hwdec': _safeConfigurationValue(configuration.hwdec),
      'stage': _safeConfigurationValue(stage),
    });

    final safeEvent =
        _diagnosticEventPattern.hasMatch(event) ? event : 'unknown_event';
    try {
      callback(safeEvent, Map<String, Object?>.unmodifiable(safeFields));
    } catch (_) {
      // Diagnostics must not affect playback or native surface operations.
    }
  }

  static bool _isDiagnosticToken(String value) =>
      _diagnosticTokenPattern.hasMatch(value);

  static String _safeConfigurationValue(String? value) =>
      value != null && _isDiagnosticToken(value) ? value : 'custom';

  static int? _diagnosticHandle(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// {@macro android_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    Future<String> getDefaultHwdec() async {
      // Enforce software rendering in emulators.
      bool hw = configuration.enableHardwareAcceleration;
      final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
      if (isEmulator) {
        hw = false;
        debugPrint('media_kit: Emulator detected.');
        debugPrint('media_kit: Enforcing S/W rendering.');
      }
      return hw ? 'auto-safe' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'gpu',
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // In case no video-decoders are found, this means media_kit_libs_***_audio is being used.
    // Thus, --vid=no is required to prevent libmpv from trying to decode video (otherwise bad things may happen).
    //
    // Search for common H264 decoder to check if video support is available.
    final decoders = await queryDecoders(handle);
    if (!decoders.contains('h264')) {
      throw UnsupportedError(
        '[VideoController] is not available.'
        ' '
        'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
      );
    }

    // Creation:
    final controller = AndroidVideoController._(
      player,
      configuration,
      handle: handle,
    );

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;

    // Wait until first texture ID is received.
    // We are not waiting on the native-side itself because it will block the UI thread.
    final completer = Completer<void>();
    void listener() {
      final value = controller.id.value;
      if (value != null) {
        debugPrint('AndroidVideoController: Texture ID: $value');
        completer.complete();
      }
    }

    controller.id.addListener(listener);

    await _channel.invokeMethod(
      'VideoOutputManager.Create',
      {
        'handle': handle.toString(),
        'diagnostics': configuration.onDiagnostic != null,
      },
    );

    await completer.future;
    controller.id.removeListener(listener);

    await controller._surfaceBinding.initialize(
      {
        // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
        'vo': 'null',
        'hwdec': configuration.hwdec!,
        'vid': 'auto',
        'opengl-es': 'yes',
        'force-window': 'yes',
        'gpu-context': 'android',
        'sub-use-margins': 'no',
        'sub-font-provider': 'none',
        'sub-scale-with-window': 'yes',
        'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
      },
    );
    debugPrint(
      '[AndroidVideoController] Initialized and surface bound: wid=${controller.wid.value}, hwdec=${configuration.hwdec}',
    );

    // Return the [PlatformVideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({
    int? width,
    int? height,
  }) {
    throw UnsupportedError(
      '[AndroidVideoController.setSize] is not available on Android',
    );
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    await videoParamsSubscription?.cancel();
    await _surfaceBinding.close(() async {
      platform.onLoadHooks.remove(onLoadHook);
      platform.onUnloadHooks.remove(onUnloadHook);
      super.dispose();
      wid.dispose();
    });
    try {
      await _channel.invokeMethod(
        'VideoOutputManager.Dispose',
        {
          'handle': _handle.toString(),
        },
      );
    } finally {
      _controllers.remove(_handle);
    }
  }

  /// Currently created [AndroidVideoController]s.
  static final _controllers = HashMap<int, AndroidVideoController>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel =
      const MethodChannel('com.alexmercerind/media_kit_video')
        ..setMethodCallHandler(
          (MethodCall call) async {
            try {
              debugPrint(call.method.toString());
              if (call.method != 'VideoOutput.Diagnostic') {
                debugPrint(call.arguments.toString());
              }
              switch (call.method) {
                case 'VideoOutput.Resize':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    final Rect rect = Rect.fromLTWH(
                      call.arguments['rect']['left'] * 1.0,
                      call.arguments['rect']['top'] * 1.0,
                      call.arguments['rect']['width'] * 1.0,
                      call.arguments['rect']['height'] * 1.0,
                    );
                    final int id = call.arguments['id'];
                    final int wid = call.arguments['wid'];
                    debugPrint(
                        '[AndroidVideoController] VideoOutput.Resize: handle=$handle, id=$id, wid=$wid, rect=$rect');
                    final controller = _controllers[handle];
                    if (controller != null) {
                      await controller._surfaceBinding.handleResize(
                        wid: wid,
                        width: rect.width.toInt(),
                        height: rect.height.toInt(),
                        textureId: id,
                        updateNotifiers: () {
                          controller.rect.value = rect;
                          controller.id.value = id;
                          // Only on Android:
                          controller.wid.value = wid;
                        },
                      );
                    }
                    break;
                  }
                case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    debugPrint(handle.toString());
                    final controller = _controllers[handle];
                    if (controller != null) {
                      await controller._surfaceBinding.runExclusive(() async {
                        controller._emitDiagnostic(
                          'first_frame_notification',
                          stage: 'native_wait_until_first_frame_rendered',
                          fields: {
                            'valid': true,
                            'reason': 'native_frame_notification',
                            'source': 'native_wait_until_first_frame_rendered',
                            'renderConfirmed': 'unknown',
                            'level': 'info',
                          },
                        );
                        // Notify about the first frame being rendered.
                        final completer =
                            controller.waitUntilFirstFrameRenderedCompleter;
                        if (!completer.isCompleted) {
                          completer.complete();
                        }
                      });
                    }
                    break;
                  }
                case 'VideoOutput.Diagnostic':
                  {
                    final Object? arguments = call.arguments;
                    if (arguments is! Map) break;
                    final handle = _diagnosticHandle(arguments['handle']);
                    final Object? rawEvent = arguments['event'];
                    final Object? rawFields = arguments['fields'];
                    if (handle == null || rawEvent is! String) break;
                    final controller = _controllers[handle];
                    if (controller == null) break;

                    final fields = <String, Object?>{};
                    if (rawFields is Map) {
                      for (final entry in rawFields.entries) {
                        if (entry.key is String) {
                          fields[entry.key as String] = entry.value;
                        }
                      }
                    }
                    // Read-only diagnostics must remain routable while the
                    // surface binding closes and native disposal completes.
                    controller._emitDiagnostic(
                      rawEvent,
                      stage: 'native',
                      fields: fields,
                    );
                    break;
                  }
                default:
                  {
                    break;
                  }
              }
            } catch (exception, stacktrace) {
              debugPrint(exception.toString());
              debugPrint(stacktrace.toString());
            }
          },
        );
}
