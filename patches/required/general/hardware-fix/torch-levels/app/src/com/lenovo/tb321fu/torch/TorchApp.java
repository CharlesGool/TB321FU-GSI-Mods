package com.lenovo.tb321fu.torch;

import android.app.Application;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;

import java.util.HashSet;
import java.util.Set;

/**
 * Torch strength levels for TB321FU. The vendor camera HAL advertises 4 torch levels but always
 * drives the LEDs at 2 x 75 mA, and changing the level while lit switches the second LED off.
 * This persistent, UI-less app listens to TorchCallback and, whenever the torch is turned on or
 * its level changes, asks the herald broker (root) to rewrite the PMIC flash LED nodes for that
 * level (`torch apply N`, see the torch-levels herald plugin). Default table: levels 1-3 one LED
 * at 50 / 100 / 200 mA, level 4 both LEDs at 300 mA.
 */
public final class TorchApp extends Application {
    private static final String TAG = "TB321FU-Torch";
    private static final long DEBOUNCE_MS = 250, TIMEOUT_MS = 6_000;

    private Handler handler;
    private Backend backend;
    private CameraManager cm;
    private final Set<String> lit = new HashSet<>();
    private int pendingLevel;
    private final Runnable send = this::sendNow;

    @Override
    public void onCreate() {
        super.onCreate();
        HandlerThread t = new HandlerThread(TAG);
        t.start();
        handler = new Handler(t.getLooper());
        backend = new HeraldBackend(this);
        cm = getSystemService(CameraManager.class);
        if (cm == null) {
            Log.e(TAG, "no CameraManager");
            return;
        }
        cm.registerTorchCallback(new CameraManager.TorchCallback() {
            @Override
            public void onTorchModeChanged(String id, boolean enabled) {
                if (enabled) {
                    lit.add(id);
                    int level;
                    try {
                        level = cm.getTorchStrengthLevel(id);
                    } catch (Exception e) {
                        level = -1;
                    }
                    schedule(id, level);
                } else {
                    lit.remove(id);
                    if (lit.isEmpty()) handler.removeCallbacks(send);
                }
            }

            @Override
            public void onTorchStrengthLevelChanged(String id, int level) {
                if (lit.contains(id)) schedule(id, level);
            }
        }, handler);
        Log.i(TAG, "torch callback registered");
    }

    /** Maps the HAL level (1..max) onto our 4 levels; unknown → the HAL's default level. */
    private int toOurLevel(String id, int level) {
        int max = 4, def = 3;
        try {
            CameraCharacteristics c = cm.getCameraCharacteristics(id);
            Integer m = c.get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL);
            Integer d = c.get(CameraCharacteristics.FLASH_INFO_STRENGTH_DEFAULT_LEVEL);
            if (m != null && m > 0) max = m;
            if (d != null && d > 0) def = d;
        } catch (Exception e) {
            Log.w(TAG, "characteristics of camera " + id, e);
        }
        if (level < 1) level = def;
        int ours = (int) Math.ceil(level * 4.0 / max);
        return Math.max(1, Math.min(4, ours));
    }

    private void schedule(String id, int level) {
        pendingLevel = toOurLevel(id, level);
        handler.removeCallbacks(send);
        handler.postDelayed(send, DEBOUNCE_MS);   // dragging the slider fires a burst of level changes
    }

    private void sendNow() {
        if (lit.isEmpty()) return;
        Resp r = backend.exec("torch apply " + pendingLevel, TIMEOUT_MS);
        if (!r.ok()) Log.w(TAG, "torch apply " + pendingLevel + ": " + r.errorText());
        else Log.i(TAG, r.first());
    }
}
