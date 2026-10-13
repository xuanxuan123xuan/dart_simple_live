package io.flutter.plugin.common;

import java.util.ArrayList;
import java.util.List;

public final class MethodChannel {
    public interface MethodCallHandler {
        void onMethodCall(MethodCall call, Result result);
    }

    public interface Result {
        void success(Object result);

        void notImplemented();
    }

    public static final class Invocation {
        public final String method;
        public final Object arguments;

        private Invocation(String method, Object arguments) {
            this.method = method;
            this.arguments = arguments;
        }
    }

    public static MethodChannel lastCreated;

    public final String name;
    public final List<Invocation> invocations = new ArrayList<>();
    public MethodCallHandler handler;

    public MethodChannel(BinaryMessenger messenger, String name) {
        this.name = name;
        lastCreated = this;
    }

    public void setMethodCallHandler(MethodCallHandler handler) {
        this.handler = handler;
    }

    public void invokeMethod(String method, Object arguments) {
        invocations.add(new Invocation(method, arguments));
    }
}
