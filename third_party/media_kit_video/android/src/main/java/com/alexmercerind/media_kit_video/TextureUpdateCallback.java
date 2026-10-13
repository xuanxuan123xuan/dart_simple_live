package com.alexmercerind.media_kit_video;

import java.util.Map;

public interface TextureUpdateCallback {
    void onTextureUpdate(long id, long wid, int width, int height);

    default void onDiagnostic(String event, Map<String, Object> fields) {}
}
