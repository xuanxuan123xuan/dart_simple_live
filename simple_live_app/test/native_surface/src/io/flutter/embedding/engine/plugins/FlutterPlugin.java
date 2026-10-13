package io.flutter.embedding.engine.plugins;

import androidx.annotation.NonNull;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.view.TextureRegistry;

public interface FlutterPlugin {
    final class FlutterPluginBinding {
        private final BinaryMessenger binaryMessenger;
        private final TextureRegistry textureRegistry;

        public FlutterPluginBinding(BinaryMessenger binaryMessenger, TextureRegistry textureRegistry) {
            this.binaryMessenger = binaryMessenger;
            this.textureRegistry = textureRegistry;
        }

        public BinaryMessenger getBinaryMessenger() {
            return binaryMessenger;
        }

        public TextureRegistry getTextureRegistry() {
            return textureRegistry;
        }
    }

    void onAttachedToEngine(@NonNull FlutterPluginBinding binding);

    void onDetachedFromEngine(@NonNull FlutterPluginBinding binding);
}
