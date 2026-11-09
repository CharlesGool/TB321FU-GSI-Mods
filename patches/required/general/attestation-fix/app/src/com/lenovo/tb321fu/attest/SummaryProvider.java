package com.lenovo.tb321fu.attest;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;

/**
 * Summary line for the tile in Settings > About ("伪装为 Pixel 9 Pro · Keybox 有效").
 * Settings calls content://com.lenovo.tb321fu.battery.summary/getSummary with method "getSummary"
 * and reads "com.android.settings.summary" from the bundle. To stay fast and never block
 * Settings, this only returns the line the app cached on its last refresh.
 */
public final class SummaryProvider extends ContentProvider {
    private static final String KEY = "com.android.settings.summary";

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        if (!"getSummary".equals(method)) return null;
        String s = getContext().getSharedPreferences(MainActivity.PREFS, 0).getString(MainActivity.KEY_SUMMARY, null);
        if (s == null) s = getContext().getString(R.string.tile_summary);
        Bundle b = new Bundle();
        b.putString(KEY, s);
        return b;
    }

    @Override
    public Cursor query(Uri uri, String[] p, String s, String[] a, String o) {
        return null;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues v) {
        return null;
    }

    @Override
    public int delete(Uri uri, String s, String[] a) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues v, String s, String[] a) {
        return 0;
    }
}
