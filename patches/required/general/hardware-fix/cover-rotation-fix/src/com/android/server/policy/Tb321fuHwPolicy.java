/*
 * TB321FU (Lenovo Legion Tab Y700 gen3) hardware glue for a Pixel GSI, runs inside system_server.
 *
 * Replaces two things ZUI did in its services.jar that a GSI does not do:
 *
 * 1. Smart cover (hall sensor)
 *    ZUI: com.zui.server.policy.ZuiPhoneWindowManager registers the QTI vendor sensor
 *    type 33171002 (qti.sensor.hall_effect, "bu52053nvx Hall Effect Sensor", wakeup variant)
 *    and calls PhoneWindowManager.notifyLidSwitchChanged(now, values[0] == 1).
 *    values[0] == 1 means "lid open". AOSP then applies Settings.Global "lid_behavior"
 *    (0 none, 1 sleep, 2 lock) on close and wakes the device (WAKE_REASON_LID) on open.
 *    There is no SW_LID input device on this kernel, so nothing else ever reports the lid.
 *
 * 2. Touch panel edge rejection direction
 *    ZUI: EdgeInhibitionInputPolicy calls ITouchscreen.setEdgeInhibition(Surface rotation 0..3)
 *    on every rotation change; the Lenovo touchscreen HAL writes it to /proc/panel_direction.
 *    system_server is a hal_lenovotouchscreen_client in the stock vendor sepolicy, so it can
 *    call the HAL directly (transaction 10, verified on device 2026-11-09).
 *
 * Only public SDK APIs are referenced at compile time; hidden ones are reached by reflection,
 * so this compiles against a plain android.jar (API 35+).
 *
 * Hook: one call at the end of PhoneWindowManager.systemReady():
 *     Tb321fuHwPolicy.init(mContext, this);
 *
 * Settings (all Settings.Global, adb shell settings put global <key> <value>):
 *     lid_behavior            AOSP key. 0 none, 1 sleep (forced once on first boot, see
 *                             tb321fu_lid_behavior_init), 2 lock.
 *     tb321fu_cover_enabled   1 (default) report the hall sensor as lid, 0 always report "open".
 *     tb321fu_edge_rotation   1 (default) sync rotation to the touch panel, 0 leave it alone.
 */
package com.android.server.policy;

import android.content.ContentResolver;
import android.content.Context;
import android.database.ContentObserver;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Parcel;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;
import android.view.Display;

import java.lang.reflect.Method;

public final class Tb321fuHwPolicy {
    private static final String TAG = "Tb321fuHwPolicy";

    private static final int TYPE_HALL = 33171002;            // qti.sensor.hall_effect
    private static final String TS_SERVICE = "vendor.lenovo.hardware.touchscreen.ITouchscreen/default";
    private static final String TS_DESCRIPTOR = "vendor.lenovo.hardware.touchscreen.ITouchscreen";
    private static final int TX_SET_EDGE_INHIBITION = 10;     // ITouchscreen V2: setEdgeInhibition(int) -> boolean

    private static final String KEY_LID_BEHAVIOR = "lid_behavior";
    private static final String KEY_LID_INIT = "tb321fu_lid_behavior_init";
    private static final String KEY_COVER = "tb321fu_cover_enabled";
    private static final String KEY_EDGE = "tb321fu_edge_rotation";
    private static final int LID_BEHAVIOR_SLEEP = 1;

    private static Tb321fuHwPolicy sInstance;

    private final Context mContext;
    private final Object mPolicy;                 // com.android.server.policy.PhoneWindowManager
    private final Handler mHandler;
    private final ContentResolver mResolver;

    private Method mNotifyLid;                    // notifyLidSwitchChanged(long, boolean)
    private int mRawLid = -1;                     // last hall value: 1 open, 0 closed, -1 unknown
    private int mReportedLid = -1;                // what we last told PhoneWindowManager
    private int mPanelRotation = -1;              // what we last wrote to the touch panel
    private IBinder mTouchscreen;

    /** Called from PhoneWindowManager.systemReady(). Never throws. */
    public static void init(Context context, Object phoneWindowManager) {
        try {
            if (sInstance != null) return;
            if (!"TB321FU".equals(getProp("ro.product.vendor.device"))) {
                Log.i(TAG, "not TB321FU, disabled");
                return;
            }
            sInstance = new Tb321fuHwPolicy(context, phoneWindowManager);
            sInstance.mHandler.post(sInstance::start);
        } catch (Throwable t) {
            Log.e(TAG, "init failed", t);
        }
    }

    private Tb321fuHwPolicy(Context context, Object policy) {
        mContext = context;
        mPolicy = policy;
        mResolver = context.getContentResolver();
        HandlerThread t = new HandlerThread(TAG);
        t.start();
        mHandler = new Handler(t.getLooper());
    }

    private void start() {
        try {
            // Pixel/AOSP already ship lid_behavior=0 (LID_BEHAVIOR_NONE), so "only if unset" never
            // fires. Force 1 exactly once (marker key), then respect whatever the user sets later.
            if (Settings.Global.getInt(mResolver, KEY_LID_INIT, 0) == 0) {
                Settings.Global.putInt(mResolver, KEY_LID_BEHAVIOR, LID_BEHAVIOR_SLEEP);
                Settings.Global.putInt(mResolver, KEY_LID_INIT, 1);
                Log.i(TAG, "lid_behavior first boot -> 1 (sleep on close)");
            }
        } catch (Throwable t) {
            Log.w(TAG, "lid_behavior default failed", t);
        }
        ContentObserver obs = new ContentObserver(mHandler) {
            @Override
            public void onChange(boolean selfChange) {
                applyLid();
                applyRotation(true);
            }
        };
        mResolver.registerContentObserver(Settings.Global.getUriFor(KEY_COVER), false, obs);
        mResolver.registerContentObserver(Settings.Global.getUriFor(KEY_EDGE), false, obs);
        startHall();
        startRotation();
    }

    // ---------------------------------------------------------------- cover / hall sensor

    private void startHall() {
        try {
            mNotifyLid = mPolicy.getClass().getMethod("notifyLidSwitchChanged", long.class, boolean.class);
        } catch (Throwable t) {
            Log.e(TAG, "PhoneWindowManager.notifyLidSwitchChanged not found, cover disabled", t);
            return;
        }
        SensorManager sm = mContext.getSystemService(SensorManager.class);
        Sensor hall = sm == null ? null : sm.getDefaultSensor(TYPE_HALL, true);
        if (hall == null) {
            Log.w(TAG, "hall sensor " + TYPE_HALL + " not found, cover disabled");
            return;
        }
        boolean ok = sm.registerListener(new SensorEventListener() {
            @Override
            public void onSensorChanged(SensorEvent event) {
                mRawLid = ((int) event.values[0]) == 1 ? 1 : 0;
                Log.i(TAG, "hall value " + event.values[0] + " -> lid " + (mRawLid == 1 ? "open" : "closed"));
                applyLid();
            }

            @Override
            public void onAccuracyChanged(Sensor sensor, int accuracy) {
            }
        }, hall, SensorManager.SENSOR_DELAY_NORMAL, mHandler);
        Log.i(TAG, "hall sensor " + hall.getName() + " registered=" + ok);
    }

    private void applyLid() {
        if (mNotifyLid == null || mRawLid < 0) return;
        boolean enabled = Settings.Global.getInt(mResolver, KEY_COVER, 1) != 0;
        int lid = enabled ? mRawLid : 1;
        if (lid == mReportedLid) return;
        mReportedLid = lid;
        try {
            mNotifyLid.invoke(mPolicy, SystemClock.uptimeMillis(), lid == 1);
        } catch (Throwable t) {
            Log.e(TAG, "notifyLidSwitchChanged failed", t);
        }
    }

    // ---------------------------------------------------------------- rotation -> touch panel

    private void startRotation() {
        DisplayManager dm = mContext.getSystemService(DisplayManager.class);
        if (dm == null) return;
        dm.registerDisplayListener(new DisplayManager.DisplayListener() {
            @Override
            public void onDisplayAdded(int displayId) {
            }

            @Override
            public void onDisplayRemoved(int displayId) {
            }

            @Override
            public void onDisplayChanged(int displayId) {
                if (displayId == Display.DEFAULT_DISPLAY) applyRotation(false);
            }
        }, mHandler);
        applyRotation(true);
    }

    private void applyRotation(boolean force) {
        if (Settings.Global.getInt(mResolver, KEY_EDGE, 1) == 0) return;
        DisplayManager dm = mContext.getSystemService(DisplayManager.class);
        Display d = dm == null ? null : dm.getDisplay(Display.DEFAULT_DISPLAY);
        if (d == null) return;
        int rot = d.getRotation();                     // Surface.ROTATION_0..270 == 0..3, same as ZUI
        if (!force && rot == mPanelRotation) return;
        if (setEdgeInhibition(rot)) mPanelRotation = rot;
    }

    private boolean setEdgeInhibition(int rotation) {
        for (int attempt = 0; attempt < 2; attempt++) {
            IBinder b = mTouchscreen;
            if (b == null || !b.isBinderAlive()) {
                b = mTouchscreen = getService(TS_SERVICE);
            }
            if (b == null) {
                Log.w(TAG, "touchscreen HAL not available");
                return false;
            }
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                data.writeInterfaceToken(TS_DESCRIPTOR);
                data.writeInt(rotation);
                if (!b.transact(TX_SET_EDGE_INHIBITION, data, reply, 0)) {
                    Log.w(TAG, "setEdgeInhibition unimplemented");
                    return false;
                }
                reply.readException();
                boolean ok = reply.readInt() != 0;
                Log.i(TAG, "setEdgeInhibition(" + rotation + ") -> " + ok);
                return ok;
            } catch (Throwable t) {
                Log.w(TAG, "setEdgeInhibition failed, attempt " + attempt, t);
                mTouchscreen = null;
            } finally {
                reply.recycle();
                data.recycle();
            }
        }
        return false;
    }

    // ---------------------------------------------------------------- hidden API via reflection

    private static String getProp(String key) {
        try {
            Class<?> c = Class.forName("android.os.SystemProperties");
            return (String) c.getMethod("get", String.class).invoke(null, key);
        } catch (Throwable t) {
            return "";
        }
    }

    private static IBinder getService(String name) {
        try {
            Class<?> c = Class.forName("android.os.ServiceManager");
            return (IBinder) c.getMethod("getService", String.class).invoke(null, name);
        } catch (Throwable t) {
            return null;
        }
    }
}
