package android.os;

import java.util.ArrayList;
import java.util.List;

public final class Handler {
    public static final class DelayedTask {
        public final Runnable runnable;
        public final long delayMillis;

        private DelayedTask(Runnable runnable, long delayMillis) {
            this.runnable = runnable;
            this.delayMillis = delayMillis;
        }
    }

    private static final List<DelayedTask> tasks = new ArrayList<>();

    public Handler(Looper looper) {}

    public boolean postDelayed(Runnable runnable, long delayMillis) {
        tasks.add(new DelayedTask(runnable, delayMillis));
        return true;
    }

    public static int pendingCount() {
        return tasks.size();
    }

    public static DelayedTask takeNext() {
        return tasks.remove(0);
    }

    public static void clear() {
        tasks.clear();
    }
}
