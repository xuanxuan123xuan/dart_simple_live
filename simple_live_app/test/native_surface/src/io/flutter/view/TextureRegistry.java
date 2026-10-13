package io.flutter.view;

import android.view.Surface;

public interface TextureRegistry {
    SurfaceProducer createSurfaceProducer();

    interface SurfaceProducer {
        interface Callback {
            void onSurfaceAvailable();

            void onSurfaceCleanup();
        }

        long id();

        int getWidth();

        int getHeight();

        Surface getSurface();

        void setSize(int width, int height);

        void setCallback(Callback callback);

        void release();
    }
}
