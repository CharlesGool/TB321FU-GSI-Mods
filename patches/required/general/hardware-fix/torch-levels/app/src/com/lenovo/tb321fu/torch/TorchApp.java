package com.lenovo.tb321fu.torch;

import android.app.Application;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Torch strength levels for TB321FU. The vendor camera HAL advertises 4 torch levels but always
 * drives the LEDs at 2 x 75 mA, and changing the level while lit switches the second LED off.
 *
 * This persistent, UI-less, direct-boot-aware app keeps one "latest wanted state" and publishes
 * it atomically (write tmp, rename) to its device-protected files/torch_state:
 * {@code <seq> on <1-4>} or {@code <seq> off}. The torch-levels herald plugin watches the
 * directory with inotify, re-reads the file on every event and applies only the newest line, so
 * nothing queues up and a stale state can never run (test-v2.8: the request/reply channel took
 * 0.35-0.57 s per round trip and stale requests switched a freshly lit torch off).
 *
 * Level callbacks get lost (right after setTorchMode(true), and sometimes for a whole slider
 * drag), so while lit the level is also polled every {@link #POLL_MS}. Every turn-on gets a new
 * seq: the HAL always relights at its own 2 x 75 mA, so the level must be rewritten even if it
 * did not change. Turning on without choosing a level follows getTorchStrengthLevel() (what the
 * Quick Settings slider shows).
 */
public final class TorchApp extends Application {
    private static final String TAG = "TB321FU-Torch";
    private static final long POLL_MS = 150;

    private CameraManager cm;
    private Handler h;
    private final Set<String> lit = new HashSet<>();
    /** FLASH_INFO_STRENGTH_MAXIMUM_LEVEL per camera id (fixed; read once). */
    private final Map<String, Integer> maxLevel = new HashMap<>();
    /** Camera id of the latest change (whose level we read). Handler thread only, like the rest. */
    private String cur;
    private int level;
    private long seq;
    private File state, tmp;

    @Override
    public void onCreate() {
        super.onCreate();
        File dir = createDeviceProtectedStorageContext().getFilesDir();   // usable before first unlock
        dir.mkdirs();
        state = new File(dir, "torch_state");
        tmp = new File(dir, "torch_state.tmp");
        seq = System.currentTimeMillis();   // never repeats a line left over from an earlier process
        HandlerThread t = new HandlerThread(TAG);
        t.start();
        h = new Handler(t.getLooper());
        cm = getSystemService(CameraManager.class);
        if (cm == null) {
            Log.e(TAG, "no CameraManager");
            return;
        }
        h.post(() -> publish("start"));     // (re)start: off until the callback says otherwise
        cm.registerTorchCallback(cb, h);
        Log.i(TAG, "torch callback registered");
    }

    /** HAL level of camera {@code id} mapped onto our 1..4, or -1 if unknown. */
    private int read(String id) {
        int l;
        try {
            l = cm.getTorchStrengthLevel(id);
        } catch (Exception e) {
            return -1;
        }
        if (l < 1) return -1;
        Integer max = maxLevel.get(id);
        if (max == null) {
            max = 4;
            try {
                Integer m = cm.getCameraCharacteristics(id)
                        .get(CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL);
                if (m != null && m > 0) max = m;
            } catch (Exception e) {
                // keep 4
            }
            maxLevel.put(id, max);
        }
        return max == 4 ? l : Math.max(1, Math.min(4, (int) Math.ceil(l * 4.0 / max)));
    }

    private final CameraManager.TorchCallback cb = new CameraManager.TorchCallback() {
        @Override
        public void onTorchModeChanged(String id, boolean on) {
            if (on) {
                lit.add(id);
                cur = id;
                int l = read(id);
                level = l >= 1 ? l : 3;
                publish("on");                  // new seq on every turn-on, even at the same level
                h.removeCallbacks(poll);
                h.postDelayed(poll, POLL_MS);
            } else if (lit.remove(id) && lit.isEmpty()) {
                h.removeCallbacks(poll);
                publish("off");
            }
        }

        @Override
        public void onTorchStrengthLevelChanged(String id, int l) {
            if (!lit.contains(id)) return;
            cur = id;
            int ours = read(id);
            if (ours >= 1 && ours != level) {
                level = ours;
                publish("level");
            }
        }
    };

    private final Runnable poll = new Runnable() {
        @Override
        public void run() {
            if (lit.isEmpty() || cur == null) return;
            int l = read(cur);
            if (l >= 1 && l != level) {
                level = l;
                publish("poll");
            }
            h.postDelayed(this, POLL_MS);
        }
    };

    /** Handler thread only. */
    private void publish(String why) {
        String line = (++seq) + (lit.isEmpty() ? " off" : " on " + Math.max(1, Math.min(4, level))) + "\n";
        try {
            try (FileOutputStream o = new FileOutputStream(tmp)) {
                o.write(line.getBytes(StandardCharsets.US_ASCII));
            }
            if (!tmp.renameTo(state)) Log.w(TAG, "rename failed");
        } catch (IOException e) {
            Log.w(TAG, "write state: " + e);
        }
        Log.i(TAG, "state " + line.trim() + " (" + why + ")");
    }
}
