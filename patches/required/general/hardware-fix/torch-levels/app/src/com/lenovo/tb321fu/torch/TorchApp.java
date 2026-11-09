package com.lenovo.tb321fu.torch;

import android.app.Application;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Torch strength levels for TB321FU. The vendor camera HAL advertises 4 torch levels but always
 * drives the LEDs at 2 x 75 mA, and changing the level while lit switches the second LED off.
 * This persistent, UI-less app listens to TorchCallback and, whenever the torch is turned on or
 * its level changes, asks the herald broker (root) to rewrite the PMIC flash LED nodes for that
 * level (`torch apply N`, see the torch-levels herald plugin), and sends `torch off` when the
 * torch goes off after we wrote it. Default table: levels 1-3 one LED at 50 / 100 / 200 mA,
 * level 4 both LEDs at 300 mA.
 */
public final class TorchApp extends Application {
    private static final String TAG = "TB321FU-Torch";
    /** Slider drags fire bursts of level changes; turning the torch on is a single event and goes out at once. */
    private static final long DEBOUNCE_MS = 40, TIMEOUT_MS = 6_000;

    private Handler handler;
    /**
     * Requests to herald go out one at a time on their own thread, in the order the callbacks
     * asked for them: an "off" queued after an "apply" always runs after it, so an apply that
     * was already on its way can never leave the LEDs lit after the user switched the torch off
     * (test-v2.6). The callback thread never blocks on herald.
     */
    private final ExecutorService sender = Executors.newSingleThreadExecutor();
    /** We wrote the LEDs since the torch was last off: an "off" must follow. Callback thread only. */
    private boolean written;
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
                    schedule(id, level, 0);
                } else {
                    lit.remove(id);
                    if (lit.isEmpty()) {
                        handler.removeCallbacks(send);   // drop a level change still waiting for its debounce
                        if (written) {
                            written = false;
                            // The HAL has already switched off; this only undoes a write of ours that
                            // may still be in flight (it would switch the LEDs back on).
                            sender.execute(() -> exec("torch off"));
                        }
                    }
                }
            }

            @Override
            public void onTorchStrengthLevelChanged(String id, int level) {
                if (lit.contains(id)) schedule(id, level, DEBOUNCE_MS);
            }
        }, handler);
        Log.i(TAG, "torch callback registered");
    }

    /**
     * Maps the HAL level (1..max) onto our 4 levels; unknown → the HAL's default level.
     * Turning the torch on without choosing a level reports the last level used (what the
     * Quick Settings slider shows), so that is what gets applied.
     */
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

    private void schedule(String id, int level, long delayMs) {
        pendingLevel = toOurLevel(id, level);
        handler.removeCallbacks(send);
        handler.postDelayed(send, delayMs);
    }

    /** Runs on the callback thread after the debounce. */
    private void sendNow() {
        if (lit.isEmpty()) return;
        written = true;
        final int level = pendingLevel;
        sender.execute(() -> exec("torch apply " + level));
    }

    /** Runs on the sender thread. */
    private void exec(String cmd) {
        Resp r = backend.exec(cmd, TIMEOUT_MS);
        if (!r.ok()) Log.w(TAG, cmd + ": " + r.errorText());
        else Log.i(TAG, r.first());
    }
}
