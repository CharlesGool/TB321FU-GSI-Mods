package com.lenovo.tb321fu.qsbrightness;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;

/**
 * Long-press target of the "自动亮度" tile. SystemUI opens the tile package's activity for
 * android.service.quicksettings.action.QS_TILE_PREFERENCES (and falls back to the app-info page
 * when there is none); a tile can only point at its own package, so this invisible activity just
 * forwards to Settings > Display ("显示和触控" on Pixel) and finishes.
 */
public final class TilePrefsActivity extends Activity {
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        startActivity(new Intent(Settings.ACTION_DISPLAY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        finish();
    }
}
