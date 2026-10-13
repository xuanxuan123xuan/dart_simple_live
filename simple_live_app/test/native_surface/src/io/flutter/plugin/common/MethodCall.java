package io.flutter.plugin.common;

import java.util.Map;

public final class MethodCall {
    public final String method;
    public final Object arguments;

    public MethodCall(String method, Object arguments) {
        this.method = method;
        this.arguments = arguments;
    }

    @SuppressWarnings("unchecked")
    public <T> T argument(String key) {
        return (T) ((Map<String, Object>) arguments).get(key);
    }
}
