package com.lenovo.tb321fu.qsbrightness;

import android.database.ContentObserver;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.util.Log;

/**
 * Quick Settings tile "自动亮度": toggles Settings.System.SCREEN_BRIGHTNESS_MODE between manual (0)
 * and automatic (1). AOSP / Pixel SystemUI has no such tile. Follows changes made elsewhere
 * (Settings > Display) while the panel is open.
 */
public final class AutoBrightnessTile extends TileService {
    private static final String TAG = "TB321FU-QSBrightness";
    private static final Uri MODE_URI = Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS_MODE);

    private final ContentObserver observer = new ContentObserver(new Handler(Looper.getMainLooper())) {
        @Override
        public void onChange(boolean selfChange) {
            update();
        }
    };

    @Override
    public void onStartListening() {
        getContentResolver().registerContentObserver(MODE_URI, false, observer);
        update();
    }

    @Override
    public void onStopListening() {
        getContentResolver().unregisterContentObserver(observer);
    }

    @Override
    public void onClick() {
        boolean auto = isAuto();
        try {
            Settings.System.putInt(getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE,
                    auto ? Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL : Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC);
        } catch (SecurityException e) {
            Log.e(TAG, "no WRITE_SETTINGS (the app must be installed on the system partition)", e);
        }
        update();
    }

    private boolean isAuto() {
        return Settings.System.getInt(getContentResolver(), Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL) == Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC;
    }

    private void update() {
        Tile t = getQsTile();
        if (t == null) return;
        boolean auto = isAuto();
        t.setState(auto ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        t.setSubtitle(auto ? "开启" : "关闭");
        t.updateTile();
    }
}
