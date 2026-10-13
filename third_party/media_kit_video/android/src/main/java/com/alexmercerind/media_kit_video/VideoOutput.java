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

import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.Locale;
import java.util.Objects;

import io.flutter.view.TextureRegistry;

public class VideoOutput implements TextureRegistry.SurfaceProducer.Callback {
    private static final String TAG = "VideoOutput";
    private static final long SURFACE_RELEASE_DELAY_MS = 5000;
    private static final Method newGlobalObjectRef;
    private static final Method deleteGlobalObjectRef;
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
            clearPublishedSurface();
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
            try {
                if (force || surfaceProducer.getWidth() != width || surfaceProducer.getHeight() != height) {
                    surfaceProducer.setSize(width, height);
                }
            } catch (Throwable e) {
                Log.e(TAG, "setSurfaceSize", e);
                disconnectFromProducer(width, height);
                return;
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
            clearPublishedSurface();
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
            disconnectSurface(surfaceId, width, height);
            return;
        }
        try {
            width = surfaceProducer.getWidth();
            height = surfaceProducer.getHeight();
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.getSize", e);
            disconnectSurface(surfaceId, width, height);
            return;
        }

        final Surface currentSurface;
        try {
            currentSurface = surfaceProducer.getSurface();
            if (currentSurface == null || !currentSurface.isValid()) {
                disconnectSurface(surfaceId, width, height);
                return;
            }
        } catch (Throwable e) {
            Log.e(TAG, "surfaceProducer.getSurface", e);
            disconnectSurface(surfaceId, width, height);
            return;
        }

        if (wid != 0
                && id == surfaceId
                && publishedSurface == currentSurface
                && publishedWidth == width
                && publishedHeight == height) {
            return;
        }

        // Texture ID 0 is valid. Only the JNI reference indicates whether the
        // Surface can be handed to libmpv.
        final long surfaceWid = newGlobalObjectRef(currentSurface);
        if (surfaceWid == 0) {
            disconnectSurface(surfaceId, width, height);
            return;
        }

        final long oldWid = wid;
        id = surfaceId;
        wid = surfaceWid;
        publishedSurface = currentSurface;
        publishedWidth = width;
        publishedHeight = height;
        hasPublishedUpdate = true;
        if (oldWid != 0 && oldWid != surfaceWid) {
            releaseGlobalObjectRefLater(oldWid);
        }
        notifyTextureUpdate(id, wid, width, height);
    }

    private void disconnectFromProducer(int fallbackWidth, int fallbackHeight) {
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
        disconnectSurface(surfaceId, width, height);
    }

    private void disconnectSurface(long surfaceId, int width, int height) {
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
        if (oldWid != 0) {
            releaseGlobalObjectRefLater(oldWid);
        }
        if (changed) {
            notifyTextureUpdate(surfaceId, 0, width, height);
        }
    }

    private void clearPublishedSurface() {
        final long oldId = id;
        final long oldWid = wid;
        final int oldWidth = publishedWidth;
        final int oldHeight = publishedHeight;

        id = 0;
        wid = 0;
        publishedSurface = null;
        publishedWidth = 0;
        publishedHeight = 0;
        hasPublishedUpdate = false;
        if (oldWid != 0) {
            releaseGlobalObjectRefLater(oldWid);
            notifyTextureUpdate(oldId, 0, oldWidth, oldHeight);
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
        Log.i(TAG, String.format(Locale.ENGLISH, "newGlobalRef: object = %s", object));
        try {
            return (long) Objects.requireNonNull(newGlobalObjectRef.invoke(null, object));
        } catch (Throwable e) {
            Log.e(TAG, "newGlobalRef", e);
            return 0;
        }
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
}
