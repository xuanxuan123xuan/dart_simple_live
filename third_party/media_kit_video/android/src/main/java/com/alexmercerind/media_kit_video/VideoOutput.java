/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;

import io.flutter.view.TextureRegistry;

public class VideoOutput implements TextureRegistry.SurfaceProducer.Callback {
    private static final String TAG = "VideoOutput";
    private static final long SURFACE_RELEASE_DELAY_MS = 5000;
    private static final String DIAGNOSTIC_LEVEL_INFO = "info";
    private static final String DIAGNOSTIC_LEVEL_ERROR = "error";
    private static final Method newGlobalObjectRef;
    private static final Method deleteGlobalObjectRef;
    private static final ThreadLocal<Throwable> lastGlobalObjectRefError = new ThreadLocal<>();
    private static final Object pendingReferenceLock = new Object();
    private static final HashSet<Long> pendingGlobalObjectRefs = new HashSet<>();
    private static final Handler handler = new Handler(Looper.getMainLooper());

    static {
        try {
            // com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper is part of package:media_kit_libs_android_video & package:media_kit_libs_android_audio packages.
            // Use reflection to invoke methods of com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper.
            Class<?> mediaKitAndroidHelperClass = Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper");
            newGlobalObjectRef = mediaKitAndroidHelperClass.getDeclaredMethod("newGlobalObjectRef", Object.class);
            deleteGlobalObjectRef = mediaKitAndroidHelperClass.getDeclaredMethod("deleteGlobalObjectRef", long.class);
            newGlobalObjectRef.setAccessible(true);
            deleteGlobalObjectRef.setAccessible(true);
        } catch (Throwable e) {
            Log.i("media_kit", "package:media_kit_libs_android_video missing. Make sure you have added it to pubspec.yaml.");
            throw new RuntimeException("Failed to initialize com.alexmercerind.media_kit_video.VideoOutput.");
        }
    }

    private long id = 0;
    private long wid = 0;
    private int publishedWidth = 0;
    private int publishedHeight = 0;
    private long bindRevision;
    private Surface publishedSurface;
    private boolean hasPublishedUpdate;
    private boolean closed;

    private final TextureUpdateCallback textureUpdateCallback;
    private final TextureRegistry.SurfaceProducer surfaceProducer;
    private final Object lock = new Object();

    VideoOutput(TextureRegistry textureRegistryReference, TextureUpdateCallback textureUpdateCallback) {
        this.textureUpdateCallback = textureUpdateCallback;
        surfaceProducer = textureRegistryReference.createSurfaceProducer();
        surfaceProducer.setCallback(this);
        emitDiagnostic(
                "surface_create",
                safeTextureId(),
                null,
                bindRevision,
                0,
                0,
                0,
                0,
                false,
                "created",
                DIAGNOSTIC_LEVEL_INFO,
                null);

        // Allocate early so AndroidVideoController receives its texture ID
        // before Player.open is awaited.
        setSurfaceSize(1, 1, true);
    }

    public void dispose() {
        synchronized (lock) {
            if (closed) {
                return;
            }
            closed = true;
            final PublishedSurface old = clearPublishedSurface();
            emitDiagnostic(
                    "dispose",
                    old.id,
                    old.surface,
                    bindRevision,
                    old.wid,
                    0,
                    old.width,
                    old.height,
                    false,
                    "disposed",
                    DIAGNOSTIC_LEVEL_INFO,
                    null);
            try {
                // SurfaceProducer owns and releases its Surface.
                surfaceProducer.release();
            } catch (Throwable e) {
                Log.e(TAG, "dispose", e);
            }
        }
    }

    public void setSurfaceSize(int width, int height) {
        setSurfaceSize(width, height, false);
    }

    private void setSurfaceSize(int width, int height, boolean force) {
        synchronized (lock) {
            if (closed) {
                return;
            }
            emitDiagnostic(
                    "surface_size_requested",
                    safeTextureId(),
                    publishedSurface,
                    bindRevision,
                    wid,
                    wid,
                    width,
                    height,
                    isSurfaceValid(publishedSurface),
                    "requested",
                    DIAGNOSTIC_LEVEL_INFO,
                    null);
            final boolean needsResize;
            try {
                needsResize = force
                        || surfaceProducer.getWidth() != width
                        || surfaceProducer.getHeight() != height;
            } catch (Throwable e) {
                Log.e(TAG, "setSurfaceSize", e);
                disconnectFromProducer(width, height, "surface_size_read_failed", e);
                return;
            }
            if (needsResize) {
                try {
                    surfaceProducer.setSize(width, height);
                } catch (Throwable e) {
                    Log.e(TAG, "setSurfaceSize", e);
                    disconnectFromProducer(width, height, "set_size_failed", e);
                    return;
                }
            }

            // Always inspect the current Surface, even when its dimensions
            // have not changed: SurfaceProducer may have replaced it.
            publishSurfaceIfNeeded(width, height);
        }
    }

    @Override
    public void onSurfaceAvailable() {
        synchronized (lock) {
            if (closed) {
                return;
            }
            Log.i(TAG, "onSurfaceAvailable");
            publishSurfaceIfNeeded(publishedWidth, publishedHeight);
        }
    }

    @Override
    public void onSurfaceCleanup() {
        synchronized (lock) {
            if (closed) {
                return;
            }
            Log.i(TAG, "onSurfaceCleanup");
            final PublishedSurface old = clearPublishedSurface();
            emitDiagnostic(
                    "surface_cleanup",
                    old.id,
                    old.surface,
                    bindRevision,
                    old.wid,
                    0,
                    old.width,
                    old.height,
                    false,
                    old.wid == 0 ? "no_active_reference" : "producer_cleanup",
                    DIAGNOSTIC_LEVEL_INFO,
                    null);
        }
    }

    private void publishSurfaceIfNeeded(int fallbackWidth, int fallbackHeight) {
        long surfaceId = id;
        int width = fallbackWidth;
        int height = fallbackHeight;
        try {
            surfaceId = surfaceProducer.id();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.id", e);
            disconnectSurface(
                    surfaceId,
                    publishedSurface,
                    width,
                    height,
                    "texture_id_read_failed",
                    e);
            return;
        }
        try {
            width = surfaceProducer.getWidth();
            height = surfaceProducer.getHeight();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.getSize", e);
            disconnectSurface(
                    surfaceId,
                    publishedSurface,
                    width,
                    height,
                    "surface_size_read_failed",
                    e);
            return;
        }

        final Surface currentSurface;
        try {
            currentSurface = surfaceProducer.getSurface();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.getSurface", e);
            disconnectSurface(
                    surfaceId,
                    null,
                    width,
                    height,
                    "get_surface_failed",
                    e);
            return;
        }
        if (currentSurface == null) {
            disconnectSurface(surfaceId, width, height);
            return;
        }
        final boolean surfaceValid;
        try {
            surfaceValid = currentSurface.isValid();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.surfaceValidity", e);
            disconnectSurface(
                    surfaceId,
                    currentSurface,
                    width,
                    height,
                    "surface_validity_check_failed",
                    e);
            return;
        }
        if (!surfaceValid) {
            disconnectSurface(
                    surfaceId,
                    currentSurface,
                    width,
                    height,
                    "invalid_surface",
                    null);
            return;
        }

        if (wid != 0
                && id == surfaceId
                && publishedSurface == currentSurface
                && publishedWidth == width
                && publishedHeight == height) {
            return;
        }

        final String reason = rebindReason(surfaceId, currentSurface, width, height);
        // Texture ID 0 is valid. Only the JNI reference indicates whether the
        // Surface can be handed to libmpv.
        final long surfaceWid = newGlobalObjectRef(currentSurface);
        if (surfaceWid == 0) {
            disconnectSurface(
                    surfaceId,
                    currentSurface,
                    width,
                    height,
                    "jni_ref_zero",
                    consumeGlobalObjectRefError());
            return;
        }

        final long oldWid = wid;
        id = surfaceId;
        wid = surfaceWid;
        publishedSurface = currentSurface;
        publishedWidth = width;
        publishedHeight = height;
        bindRevision++;
        hasPublishedUpdate = true;
        if (oldWid != 0 && oldWid != surfaceWid) {
            releaseGlobalObjectRefLater(oldWid);
        }
        notifyTextureUpdate(id, wid, width, height);
        emitDiagnostic(
                "surface_publish",
                id,
                currentSurface,
                bindRevision,
                oldWid,
                wid,
                width,
                height,
                true,
                reason,
                DIAGNOSTIC_LEVEL_INFO,
                null);
    }

    private String rebindReason(long surfaceId, Surface surface, int width, int height) {
        if (!hasPublishedUpdate) {
            return "initial_publish";
        }
        if (wid == 0) {
            return "previous_reference_unavailable";
        }
        if (id != surfaceId) {
            return "texture_id_changed";
        }
        if (publishedSurface != surface) {
            return "surface_identity_changed";
        }
        if (publishedWidth != width || publishedHeight != height) {
            return "dimensions_changed";
        }
        return "surface_rebound";
    }

    private void disconnectFromProducer(
            int fallbackWidth,
            int fallbackHeight,
            String reason,
            Throwable error) {
        long surfaceId = id;
        int width = fallbackWidth;
        int height = fallbackHeight;
        try {
            surfaceId = surfaceProducer.id();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.id", e);
        }
        try {
            width = surfaceProducer.getWidth();
            height = surfaceProducer.getHeight();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.getSize", e);
        }
        disconnectSurface(surfaceId, publishedSurface, width, height, reason, error);
    }

    private void disconnectSurface(
            long surfaceId,
            Surface surface,
            int width,
            int height,
            String reason,
            Throwable error) {
        final long oldWid = wid;
        final boolean changed = !hasPublishedUpdate
                || id != surfaceId
                || oldWid != 0
                || publishedSurface != null
                || publishedWidth != width
                || publishedHeight != height;

        id = surfaceId;
        wid = 0;
        publishedSurface = null;
        publishedWidth = width;
        publishedHeight = height;
        hasPublishedUpdate = true;
        if (changed) {
            bindRevision++;
        }
        if (oldWid != 0) {
            releaseGlobalObjectRefLater(oldWid);
        }
        if (changed) {
            notifyTextureUpdate(surfaceId, 0, width, height);
        }
        emitDiagnostic(
                "surface_error",
                surfaceId,
                surface,
                bindRevision,
                oldWid,
                0,
                width,
                height,
                false,
                reason,
                DIAGNOSTIC_LEVEL_ERROR,
                error);
    }

    private void disconnectSurface(long surfaceId, int width, int height) {
        disconnectSurface(
                surfaceId,
                publishedSurface,
                width,
                height,
                "surface_unavailable",
                null);
    }

    private PublishedSurface clearPublishedSurface() {
        final long oldId = id;
        final long oldWid = wid;
        final int oldWidth = publishedWidth;
        final int oldHeight = publishedHeight;
        final Surface oldSurface = publishedSurface;

        id = 0;
        wid = 0;
        publishedSurface = null;
        publishedWidth = 0;
        publishedHeight = 0;
        hasPublishedUpdate = false;
        if (oldWid != 0) {
            bindRevision++;
            releaseGlobalObjectRefLater(oldWid);
            notifyTextureUpdate(oldId, 0, oldWidth, oldHeight);
        }
        return new PublishedSurface(oldId, oldWid, oldSurface, oldWidth, oldHeight);
    }

    private long safeTextureId() {
        try {
            return surfaceProducer.id();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.id", e);
            return id;
        }
    }

    private boolean isSurfaceValid(Surface surface) {
        if (surface == null) {
            return false;
        }
        try {
            return surface.isValid();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.surfaceValidity", e);
            return false;
        }
    }

    private void emitDiagnostic(
            String event,
            long textureId,
            Surface surface,
            long revision,
            long oldWid,
            long newWid,
            int width,
            int height,
            boolean valid,
            String reason,
            String level,
            Throwable error) {
        final Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("textureId", textureId);
        fields.put("surfaceIdentity", surface == null ? 0 : System.identityHashCode(surface));
        fields.put("bindRevision", revision);
        fields.put("oldWid", oldWid);
        fields.put("wid", newWid);
        fields.put("width", width);
        fields.put("height", height);
        fields.put("valid", valid);
        fields.put("reason", reason);
        fields.put("level", level);
        fields.put("error", error == null ? null : error.getClass().getName());
        try {
            textureUpdateCallback.onDiagnostic(event, Collections.unmodifiableMap(fields));
        } catch (Throwable e) {
            Log.e(TAG, "onDiagnostic", e);
        }
    }

    private void notifyTextureUpdate(long surfaceId, long surfaceWid, int width, int height) {
        try {
            textureUpdateCallback.onTextureUpdate(surfaceId, surfaceWid, width, height);
        } catch (Throwable e) {
            Log.e(TAG, "onTextureUpdate", e);
        }
    }

    private static long newGlobalObjectRef(Object object) {
        lastGlobalObjectRefError.remove();
        Log.i(TAG, String.format(Locale.ENGLISH, "newGlobalRef: object = %s", object));
        try {
            return (long) Objects.requireNonNull(newGlobalObjectRef.invoke(null, object));
        } catch (Throwable e) {
            final Throwable diagnosticError = e instanceof InvocationTargetException && e.getCause() != null
                    ? e.getCause()
                    : e;
            lastGlobalObjectRefError.set(diagnosticError);
            Log.e(TAG, "newGlobalRef", e);
            return 0;
        }
    }

    private static Throwable consumeGlobalObjectRefError() {
        final Throwable error = lastGlobalObjectRefError.get();
        lastGlobalObjectRefError.remove();
        return error;
    }

    private static void releaseGlobalObjectRefLater(long ref) {
        if (ref == 0) {
            return;
        }
        synchronized (pendingReferenceLock) {
            if (!pendingGlobalObjectRefs.add(ref)) {
                return;
            }
            final boolean posted = handler.postDelayed(() -> {
                synchronized (pendingReferenceLock) {
                    if (!pendingGlobalObjectRefs.remove(ref)) {
                        return;
                    }
                }
                deleteGlobalObjectRef(ref);
            }, SURFACE_RELEASE_DELAY_MS);
            if (!posted) {
                pendingGlobalObjectRefs.remove(ref);
                Log.e(TAG, "Failed to schedule Surface reference release", null);
            }
        }
    }

    private static void deleteGlobalObjectRef(long ref) {
        Log.i(TAG, String.format(Locale.ENGLISH, "deleteGlobalObjectRef: ref = %d", ref));
        try {
            deleteGlobalObjectRef.invoke(null, ref);
        } catch (Throwable e) {
            Log.e(TAG, "deleteGlobalObjectRef", e);
        }
    }

    private static final class PublishedSurface {
        final long id;
        final long wid;
        final Surface surface;
        final int width;
        final int height;

        PublishedSurface(long id, long wid, Surface surface, int width, int height) {
            this.id = id;
            this.wid = wid;
            this.surface = surface;
            this.width = width;
            this.height = height;
        }
    }
}
