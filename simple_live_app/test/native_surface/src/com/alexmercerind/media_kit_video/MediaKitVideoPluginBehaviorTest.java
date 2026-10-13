package com.alexmercerind.media_kit_video;

import android.view.Surface;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.view.TextureRegistry;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;

public final class MediaKitVideoPluginBehaviorTest {
    private static int assertions;

    private MediaKitVideoPluginBehaviorTest() {}

    public static void main(String[] args) {
        testDiagnosticsAreOptInAndResizeWireFormatIsStable();
        testDiagnosticForwardingAndSurfaceEvents();
        System.out.println("PASS: MediaKitVideoPlugin behavior checks (" + assertions + " assertions)");
    }

    private static void testDiagnosticsAreOptInAndResizeWireFormatIsStable() {
        for (Object diagnostics : new Object[] {Boolean.FALSE, "true", null}) {
            final Surface surface = new Surface("diagnostics-disabled");
            final FakeProducer producer = new FakeProducer(7, surface);
            final MediaKitVideoPlugin plugin = attach(producer);
            final MethodChannel channel = MethodChannel.lastCreated;
            final Map<String, Object> arguments = new HashMap<>();
            arguments.put("handle", "12");
            if (diagnostics != null) {
                arguments.put("diagnostics", diagnostics);
            }
            final RecordingResult result = invoke(plugin, "VideoOutputManager.Create", arguments);

            check(result.success, "Create succeeds when diagnostics are not enabled");
            check(invocations(channel, "VideoOutput.Diagnostic").isEmpty(),
                    "only Boolean.TRUE enables diagnostic channel messages");
            final MethodChannel.Invocation resize = firstInvocation(channel, "VideoOutput.Resize");
            check(resize != null, "Resize is still sent when diagnostics are disabled");
            final Map<String, Object> resizeArguments = map(resize.arguments);
            check(resizeArguments.keySet().equals(new HashSet<>(Arrays.asList(
                            "handle", "id", "wid", "rect"))),
                    "Resize top-level wire fields stay unchanged");
            check(resizeArguments.get("handle").equals(12L)
                            && resizeArguments.get("id").equals(7L)
                            && ((Number) resizeArguments.get("wid")).longValue() != 0,
                    "Resize keeps its handle, texture ID, and active wid");
            final Map<String, Object> rect = map(resizeArguments.get("rect"));
            check(rect.keySet().equals(new HashSet<>(Arrays.asList(
                            "left", "top", "width", "height"))),
                    "Resize rect wire fields stay unchanged");
            check(rect.get("left").equals(0) && rect.get("top").equals(0)
                            && rect.get("width").equals(1) && rect.get("height").equals(1),
                    "Resize rect retains its existing values");

            dispose(plugin, "12");
            runAllDelayedTasks();
        }
    }

    private static void testDiagnosticForwardingAndSurfaceEvents() {
        final Surface surface = new Surface("diagnostics-enabled");
        final FakeProducer producer = new FakeProducer(0, surface);
        final MediaKitVideoPlugin plugin = attach(producer);
        final MethodChannel channel = MethodChannel.lastCreated;
        final Map<String, Object> arguments = new HashMap<>();
        arguments.put("handle", "99");
        arguments.put("diagnostics", Boolean.TRUE);
        invoke(plugin, "VideoOutputManager.Create", arguments);

        final MethodChannel.Invocation initialDiagnostic = diagnosticFor(channel, "surface_publish");
        check(initialDiagnostic != null, "enabled Create forwards native diagnostics");
        final Map<String, Object> forwarded = map(initialDiagnostic.arguments);
        check(forwarded.keySet().equals(new HashSet<>(Arrays.asList(
                        "handle", "event", "fields"))),
                "diagnostic method arguments use the required envelope");
        check(forwarded.get("handle").equals(99L)
                        && forwarded.get("event").equals("surface_publish"),
                "diagnostic envelope preserves handle and event");
        final Map<String, Object> fields = map(forwarded.get("fields"));
        check(fields.get("textureId").equals(0L), "enabled diagnostics preserve legal texture ID 0");
        check(fields.get("reason").equals("initial_publish"),
                "forwarded diagnostic preserves the rebind reason");

        invoke(plugin, "VideoOutputManager.SetSurfaceSize", args("handle", "99", "width", "1920", "height", "1080"));
        final MethodChannel.Invocation resizedDiagnostic = lastDiagnostic(channel, "surface_publish");
        final Map<String, Object> resizedFields = map(map(resizedDiagnostic.arguments).get("fields"));
        check(resizedFields.get("width").equals(1920)
                        && resizedFields.get("height").equals(1080),
                "plugin forwards resized dimensions");
        final MethodChannel.Invocation resize = lastInvocation(channel, "VideoOutput.Resize");
        final Map<String, Object> resizeRect = map(map(resize.arguments).get("rect"));
        check(resizeRect.get("width").equals(1920) && resizeRect.get("height").equals(1080),
                "Resize message remains the regular texture update");

        surface.setValid(false);
        producer.callback.onSurfaceAvailable();
        final MethodChannel.Invocation errorDiagnostic = lastDiagnostic(channel, "surface_error");
        final Map<String, Object> errorFields = map(map(errorDiagnostic.arguments).get("fields"));
        check(errorFields.get("wid").equals(0L)
                        && errorFields.get("reason").equals("invalid_surface"),
                "plugin forwards explicit wid=0 invalid Surface diagnostics");
        final MethodChannel.Invocation disconnect = lastInvocation(channel, "VideoOutput.Resize");
        check(map(disconnect.arguments).get("wid").equals(0L),
                "invalid Surface still reaches the existing Resize channel");

        surface.setValid(true);
        producer.callback.onSurfaceAvailable();
        final long activeWid = ((Number) map(lastInvocation(channel, "VideoOutput.Resize").arguments)
                .get("wid")).longValue();
        producer.callback.onSurfaceCleanup();
        final MethodChannel.Invocation cleanup = lastDiagnostic(channel, "surface_cleanup");
        final Map<String, Object> cleanupFields = map(map(cleanup.arguments).get("fields"));
        check(cleanupFields.get("oldWid").equals(activeWid)
                        && cleanupFields.get("wid").equals(0L),
                "cleanup forwards its active ref and wid=0");

        dispose(plugin, "99");
        check(lastDiagnostic(channel, "dispose") != null,
                "dispose diagnostic is forwarded");
        runAllDelayedTasks();
    }

    private static MediaKitVideoPlugin attach(FakeProducer producer) {
        final TextureRegistry textureRegistry = () -> producer;
        final FlutterPlugin.FlutterPluginBinding binding = new FlutterPlugin.FlutterPluginBinding(
                new BinaryMessenger() {},
                textureRegistry);
        final MediaKitVideoPlugin plugin = new MediaKitVideoPlugin();
        plugin.onAttachedToEngine(binding);
        return plugin;
    }

    private static RecordingResult invoke(MediaKitVideoPlugin plugin, String method, Map<String, Object> arguments) {
        final RecordingResult result = new RecordingResult();
        plugin.onMethodCall(new MethodCall(method, arguments), result);
        return result;
    }

    private static void dispose(MediaKitVideoPlugin plugin, String handle) {
        invoke(plugin, "VideoOutputManager.Dispose", args("handle", handle));
    }

    private static Map<String, Object> args(String... keyValues) {
        final Map<String, Object> values = new HashMap<>();
        for (int i = 0; i < keyValues.length; i += 2) {
            values.put(keyValues[i], keyValues[i + 1]);
        }
        return values;
    }

    private static List<MethodChannel.Invocation> invocations(MethodChannel channel, String method) {
        final List<MethodChannel.Invocation> result = new ArrayList<>();
        for (MethodChannel.Invocation invocation : channel.invocations) {
            if (invocation.method.equals(method)) {
                result.add(invocation);
            }
        }
        return result;
    }

    private static MethodChannel.Invocation firstInvocation(MethodChannel channel, String method) {
        final List<MethodChannel.Invocation> matches = invocations(channel, method);
        return matches.isEmpty() ? null : matches.get(0);
    }

    private static MethodChannel.Invocation lastInvocation(MethodChannel channel, String method) {
        final List<MethodChannel.Invocation> matches = invocations(channel, method);
        return matches.isEmpty() ? null : matches.get(matches.size() - 1);
    }

    private static MethodChannel.Invocation diagnosticFor(MethodChannel channel, String event) {
        for (MethodChannel.Invocation invocation : invocations(channel, "VideoOutput.Diagnostic")) {
            if (map(invocation.arguments).get("event").equals(event)) {
                return invocation;
            }
        }
        return null;
    }

    private static MethodChannel.Invocation lastDiagnostic(MethodChannel channel, String event) {
        final List<MethodChannel.Invocation> matches = invocations(channel, "VideoOutput.Diagnostic");
        for (int i = matches.size() - 1; i >= 0; i--) {
            if (map(matches.get(i).arguments).get("event").equals(event)) {
                return matches.get(i);
            }
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> map(Object value) {
        return (Map<String, Object>) value;
    }

    private static void runAllDelayedTasks() {
        while (android.os.Handler.pendingCount() > 0) {
            android.os.Handler.takeNext().runnable.run();
        }
    }

    private static void check(boolean condition, String message) {
        assertions++;
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static final class RecordingResult implements Result {
        boolean success;

        @Override
        public void success(Object result) {
            success = true;
        }

        @Override
        public void notImplemented() {
            throw new AssertionError("Unexpected notImplemented result");
        }
    }

    private static final class FakeProducer implements TextureRegistry.SurfaceProducer {
        final long textureId;
        Surface surface;
        int width;
        int height;
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
            return surface;
        }

        @Override
        public void setSize(int width, int height) {
            this.width = width;
            this.height = height;
        }

        @Override
        public void setCallback(Callback callback) {
            this.callback = callback;
        }

        @Override
        public void release() {
            if (callback != null) {
                callback.onSurfaceCleanup();
            }
        }
    }
}
