package com.lenovo.tb321fu.battery;

import android.content.Context;

final class Backends {
    private static Backend demo;
    private static Backend real;

    private Backends() {
    }

    /**
     * Demo mode serves fixed data recorded from a real TB321FU, so the UI can be checked
     * without the system patch:
     *   adb shell am start -n com.lenovo.tb321fu.battery/.MainActivity --ez demo true
     */
    static synchronized Backend get(Context ctx, boolean demoMode) {
        if (demoMode) {
            if (demo == null) demo = new DemoBackend();
            return demo;
        }
        if (real == null) real = new HeraldBackend(ctx.getApplicationContext());
        return real;
    }
}
