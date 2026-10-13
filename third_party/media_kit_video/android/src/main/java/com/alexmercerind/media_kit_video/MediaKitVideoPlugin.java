/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * MediaKitVideoPlugin
 */
public class MediaKitVideoPlugin implements FlutterPlugin, MethodCallHandler {
    private MethodChannel channel;
    private VideoOutputManager videoOutputManager;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "com.alexmercerind/media_kit_video");
        channel.setMethodCallHandler(this);

        videoOutputManager = new VideoOutputManager(flutterPluginBinding.getTextureRegistry());

    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "VideoOutputManager.Create": {
                final long handle = Long.parseLong(call.argument("handle"));
                final boolean diagnostics = Boolean.TRUE.equals(call.argument("diagnostics"));
                videoOutputManager.create(handle, new TextureUpdateCallback() {
                    @Override
                    public void onTextureUpdate(long id, long wid, int width, int height) {
                        final HashMap<String, Object> rect = new HashMap<>();
                        rect.put("left", 0);
                        rect.put("top", 0);
                        rect.put("width", width);
                        rect.put("height", height);

                        final HashMap<String, Object> arguments = new HashMap<>();
                        arguments.put("handle", handle);
                        arguments.put("id", id);
                        arguments.put("wid", wid);
                        arguments.put("rect", rect);
                        channel.invokeMethod("VideoOutput.Resize", arguments);
                    }

                    @Override
                    public void onDiagnostic(String event, Map<String, Object> fields) {
                        if (!diagnostics) {
                            return;
                        }
                        final HashMap<String, Object> arguments = new HashMap<>();
                        arguments.put("handle", handle);
                        arguments.put("event", event);
                        arguments.put("fields", fields);
                        channel.invokeMethod("VideoOutput.Diagnostic", arguments);
                    }
                });
                result.success(null);
                break;
            }
            case "VideoOutputManager.SetSurfaceSize": {
                final long handle = Long.parseLong(call.argument("handle"));
                final int width = Integer.parseInt(call.argument("width"));
                final int height = Integer.parseInt(call.argument("height"));
                videoOutputManager.setSurfaceSize(handle, width, height);
                result.success(null);
                break;
            }
            case "VideoOutputManager.Dispose": {
                final long handle = Long.parseLong(call.argument("handle"));
                videoOutputManager.dispose(handle);
                result.success(null);
                break;
            }
            case "Utils.IsEmulator": {
                result.success(Utils.isEmulator());
                break;
            }
            default: {
                result.notImplemented();
                break;
            }
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }
}
