package com.alexmercerind.media_kit_video;

import android.os.Handler;
import android.view.Surface;

import com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper;

import io.flutter.view.TextureRegistry;

import java.util.ArrayList;
import java.util.List;

public final class VideoOutputBehaviorTest {
    private static int assertions;

    private VideoOutputBehaviorTest() {}

    public static void main(String[] args) {
        testTextureIdsAndDimensionChanges();
        testSameSizeSurfaceReplacementAndDuplicateNotifications();
        testCleanupThenRebuild();
        testInvalidSurfaceAndZeroReferenceRecovery();
        testProducerFailuresRecover();
        testDisposeIsIdempotentAndIgnoresCallbacks();
        System.out.println("PASS: VideoOutput behavior checks (" + assertions + " assertions)");
    }

    private static void testTextureIdsAndDimensionChanges() {
        for (long textureId : new long[] {0, 7}) {
            resetFakes();
            final Surface surface = new Surface("resize-" + textureId);
            final Fixture fixture = new Fixture(textureId, surface);
            check(fixture.producer.width == 1 && fixture.producer.height == 1,
                    "constructor requests initial 1x1 size");
            check(fixture.callback.updates.size() == 1, "initial surface is published");
            final Update initial = fixture.callback.last();
            check(initial.id == textureId, "texture ID " + textureId + " is preserved");
            check(initial.wid != 0, "initial JNI reference is valid");

            fixture.output.setSurfaceSize(1920, 1080);
            final Update resized = fixture.callback.last();
            check(fixture.producer.width == 1920 && fixture.producer.height == 1080,
                    "producer receives 1920x1080 size");
            check(resized.id == textureId && resized.wid != initial.wid,
                    "size change creates and publishes a new JNI reference");
            check(resized.width == 1920 && resized.height == 1080,
                    "resized dimensions are published");
            check(MediaKitAndroidHelper.created.get(1).object == surface,
                    "same Surface object is referenced after resize");
            check(Handler.pendingCount() == 1, "old reference is queued once");
            final Handler.DelayedTask oldReference = Handler.takeNext();
            check(oldReference.delayMillis == 5000, "old reference waits 5000ms");
            oldReference.runnable.run();
            oldReference.runnable.run();
            check(MediaKitAndroidHelper.deleted.size() == 1
                            && MediaKitAndroidHelper.deleted.get(0) == initial.wid,
                    "old reference is released once even if its task runs twice");

            fixture.output.dispose();
            runAllDelayedTasks();
        }
    }

    private static void testSameSizeSurfaceReplacementAndDuplicateNotifications() {
        resetFakes();
        final Surface firstSurface = new Surface("same-size-first");
        final Fixture fixture = new Fixture(7, firstSurface);
        final int initialUpdates = fixture.callback.updates.size();
        final int initialReferences = MediaKitAndroidHelper.created.size();
        final int initialSurfaceReads = fixture.producer.surfaceReads;

        fixture.output.setSurfaceSize(1, 1);
        fixture.output.onSurfaceAvailable();
        fixture.output.onSurfaceAvailable();
        check(fixture.callback.updates.size() == initialUpdates,
                "same Surface, size, and valid reference are deduplicated");
        check(MediaKitAndroidHelper.created.size() == initialReferences,
                "duplicate notifications do not create JNI references");

        final Surface replacement = new Surface("same-size-replacement");
        fixture.producer.surface = replacement;
        fixture.callback.throwNext = true;
        fixture.output.setSurfaceSize(1, 1);
        final Update afterReplacement = fixture.callback.last();
        check(fixture.producer.surfaceReads > initialSurfaceReads,
                "same-size request checks the current Surface");
        check(fixture.callback.updates.size() == initialUpdates + 1,
                "replacement Surface is published despite unchanged dimensions");
        check(afterReplacement.wid != fixture.callback.updates.get(0).wid,
                "replacement Surface gets a new JNI reference");
        check(MediaKitAndroidHelper.created.get(1).object == replacement,
                "new JNI reference points at replacement Surface");
        fixture.output.onSurfaceAvailable();
        check(fixture.callback.updates.size() == initialUpdates + 1
                        && MediaKitAndroidHelper.created.size() == initialReferences + 1,
                "callback failure leaves published state deduplicated");

        fixture.output.dispose();
        runAllDelayedTasks();
    }

    private static void testCleanupThenRebuild() {
        resetFakes();
        final Fixture fixture = new Fixture(0, new Surface("cleanup-rebuild"));
        final long firstReference = fixture.callback.last().wid;
        fixture.output.onSurfaceCleanup();
        check(fixture.callback.last().wid == 0, "cleanup publishes a safe disconnect");
        check(Handler.pendingCount() == 1, "cleanup queues the old reference once");
        final int updatesAfterCleanup = fixture.callback.updates.size();
        fixture.output.onSurfaceCleanup();
        check(fixture.callback.updates.size() == updatesAfterCleanup,
                "duplicate cleanup does not publish again");
        check(Handler.pendingCount() == 1, "duplicate cleanup does not queue twice");

        fixture.output.onSurfaceAvailable();
        check(fixture.callback.last().wid != 0 && fixture.callback.last().wid != firstReference,
                "available callback creates a fresh reference after cleanup");
        check(fixture.callback.updates.size() == updatesAfterCleanup + 1,
                "rebuilt surface is published once");
        runAllDelayedTasks();
        fixture.output.dispose();
        runAllDelayedTasks();
    }

    private static void testInvalidSurfaceAndZeroReferenceRecovery() {
        resetFakes();
        final Surface surface = new Surface("invalid-and-zero-ref");
        final Fixture fixture = new Fixture(7, surface);
        final long oldReference = fixture.callback.last().wid;
        surface.setValid(false);
        fixture.output.onSurfaceAvailable();
        check(fixture.callback.last().wid == 0, "invalid Surface publishes wid=0");
        final int disconnectedUpdates = fixture.callback.updates.size();
        fixture.output.onSurfaceAvailable();
        check(fixture.callback.updates.size() == disconnectedUpdates,
                "repeated invalid Surface notification is deduplicated");
        check(Handler.pendingCount() == 1, "invalid Surface retires its old ref once");

        surface.setValid(true);
        fixture.output.onSurfaceAvailable();
        check(fixture.callback.last().wid != 0, "valid Surface retries successfully");
        check(MediaKitAndroidHelper.created.size() == 2,
                "recovery creates a replacement JNI reference");
        final Handler.DelayedTask invalidSurfaceTask = Handler.takeNext();
        check(invalidSurfaceTask.delayMillis == 5000,
                "invalidated Surface reference remains delayed");
        invalidSurfaceTask.runnable.run();

        MediaKitAndroidHelper.returnZeroNext = true;
        final Surface replacement = new Surface("zero-reference");
        fixture.producer.surface = replacement;
        fixture.output.onSurfaceAvailable();
        check(fixture.callback.last().wid == 0, "JNI reference 0 publishes a disconnect");
        check(Handler.pendingCount() == 1, "failed replacement retires active reference");
        fixture.output.onSurfaceAvailable();
        check(fixture.callback.last().wid != 0, "later availability retries a zero JNI ref");
        check(MediaKitAndroidHelper.created.get(2).object == replacement,
                "retry references current replacement Surface");

        check(oldReference != 0, "test began with an active JNI reference");
        fixture.output.dispose();
        runAllDelayedTasks();
    }

    private static void testProducerFailuresRecover() {
        resetFakes();
        final Fixture fixture = new Fixture(7, new Surface("producer-failure"));
        fixture.producer.throwNextGetSurface = true;
        fixture.output.setSurfaceSize(1, 1);
        check(fixture.callback.last().wid == 0,
                "getSurface exception publishes a safe disconnect");
        final int updatesAfterReadFailure = fixture.callback.updates.size();
        fixture.output.setSurfaceSize(1, 1);
        check(fixture.callback.last().wid != 0,
                "same-size request retries after getSurface exception");
        check(fixture.callback.updates.size() == updatesAfterReadFailure + 1,
                "successful retry publishes once");

        fixture.producer.throwNextSetSize = true;
        fixture.output.setSurfaceSize(1920, 1080);
        check(fixture.callback.last().wid == 0,
                "setSize exception publishes a safe disconnect");
        final int updatesAfterSizeFailure = fixture.callback.updates.size();
        fixture.output.setSurfaceSize(1920, 1080);
        check(fixture.callback.last().wid != 0,
                "later size request retries after setSize exception");
        check(fixture.callback.updates.size() == updatesAfterSizeFailure + 1,
                "successful size retry publishes once");

        fixture.output.dispose();
        runAllDelayedTasks();
    }

    private static void testDisposeIsIdempotentAndIgnoresCallbacks() {
        resetFakes();
        final Surface surface = new Surface("dispose");
        final Fixture fixture = new Fixture(0, surface);
        final long activeReference = fixture.callback.last().wid;
        fixture.output.dispose();
        final int updatesAfterDispose = fixture.callback.updates.size();
        final int readsAfterDispose = fixture.producer.surfaceReads;
        check(fixture.callback.last().wid == 0,
                "dispose publishes a safe disconnect for the active reference");
        check(fixture.producer.releaseCount == 1, "producer is released once");
        check(surface.releaseCount() == 0, "VideoOutput leaves Surface ownership to producer");

        fixture.output.dispose();
        fixture.output.setSurfaceSize(1920, 1080);
        fixture.output.onSurfaceAvailable();
        fixture.output.onSurfaceCleanup();
        check(fixture.callback.updates.size() == updatesAfterDispose,
                "closed output ignores size and lifecycle callbacks");
        check(fixture.producer.surfaceReads == readsAfterDispose,
                "closed output does not read the Surface again");
        check(fixture.producer.releaseCount == 1, "repeated dispose does not release twice");

        check(Handler.pendingCount() == 1, "dispose queues its active ref once");
        final Handler.DelayedTask task = Handler.takeNext();
        check(task.delayMillis == 5000, "dispose delays release by 5000ms");
        task.runnable.run();
        task.runnable.run();
        check(MediaKitAndroidHelper.deleted.size() == 1
                        && MediaKitAndroidHelper.deleted.get(0) == activeReference,
                "disposed reference is deleted exactly once");
    }

    private static void resetFakes() {
        runAllDelayedTasks();
        Handler.clear();
        MediaKitAndroidHelper.reset();
    }

    private static void runAllDelayedTasks() {
        while (Handler.pendingCount() > 0) {
            Handler.takeNext().runnable.run();
        }
    }

    private static void check(boolean condition, String message) {
        assertions++;
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static final class Fixture {
        final FakeProducer producer;
        final RecordingCallback callback = new RecordingCallback();
        final VideoOutput output;

        Fixture(long textureId, Surface surface) {
            producer = new FakeProducer(textureId, surface);
            output = new VideoOutput(() -> producer, callback);
        }
    }

    private static final class FakeProducer implements TextureRegistry.SurfaceProducer {
        final long textureId;
        Surface surface;
        int width;
        int height;
        int surfaceReads;
        int releaseCount;
        boolean throwNextGetSurface;
        boolean throwNextSetSize;
        Callback callback;

        FakeProducer(long textureId, Surface surface) {
            this.textureId = textureId;
            this.surface = surface;
        }

        @Override
        public long id() {
            return textureId;
        }

        @Override
        public int getWidth() {
            return width;
        }

        @Override
        public int getHeight() {
            return height;
        }

        @Override
        public Surface getSurface() {
            surfaceReads++;
            if (throwNextGetSurface) {
                throwNextGetSurface = false;
                throw new IllegalStateException("getSurface failed");
            }
            return surface;
        }

        @Override
        public void setSize(int width, int height) {
            if (throwNextSetSize) {
                throwNextSetSize = false;
                throw new IllegalStateException("setSize failed");
            }
            this.width = width;
            this.height = height;
        }

        @Override
        public void setCallback(Callback callback) {
            this.callback = callback;
        }

        @Override
        public void release() {
            releaseCount++;
            if (callback != null) {
                callback.onSurfaceCleanup();
            }
        }
    }

    private static final class Update {
        final long id;
        final long wid;
        final int width;
        final int height;

        Update(long id, long wid, int width, int height) {
            this.id = id;
            this.wid = wid;
            this.width = width;
            this.height = height;
        }
    }

    private static final class RecordingCallback implements TextureUpdateCallback {
        final List<Update> updates = new ArrayList<>();
        boolean throwNext;

        @Override
        public void onTextureUpdate(long id, long wid, int width, int height) {
            updates.add(new Update(id, wid, width, height));
            if (throwNext) {
                throwNext = false;
                throw new IllegalStateException("callback failed");
            }
        }

        Update last() {
            return updates.get(updates.size() - 1);
        }
    }
}
