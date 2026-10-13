package com.alexmercerind.mediakitandroidhelper;

import android.view.Surface;

import java.util.ArrayList;
import java.util.List;

public final class MediaKitAndroidHelper {
    public static final class GlobalReference {
        public final long id;
        public final Object object;

        private GlobalReference(long id, Object object) {
            this.id = id;
            this.object = object;
        }
    }

    public static final List<GlobalReference> created = new ArrayList<>();
    public static final List<Long> deleted = new ArrayList<>();
    public static long nextId = 100;
    public static boolean returnZeroNext;

    private MediaKitAndroidHelper() {}

    public static long newGlobalObjectRef(Object object) {
        if (returnZeroNext) {
            returnZeroNext = false;
            return 0;
        }
        final long id = nextId++;
        created.add(new GlobalReference(id, object));
        return id;
    }

    public static void deleteGlobalObjectRef(long id) {
        deleted.add(id);
    }

    public static void reset() {
        created.clear();
        deleted.clear();
        returnZeroNext = false;
    }
}
