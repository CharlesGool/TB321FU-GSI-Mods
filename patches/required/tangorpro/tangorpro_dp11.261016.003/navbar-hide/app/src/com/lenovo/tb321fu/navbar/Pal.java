package com.lenovo.tb321fu.navbar;

import android.content.Context;
import android.content.res.Configuration;

/**
 * The Material 3 dynamic colors Settings uses (SettingsLib "materialColor*"), taken straight from
 * the framework's system_*_light / system_*_dark so the app follows the wallpaper theme exactly
 * like Settings does.
 */
final class Pal {
    final boolean night;
    final int surfaceContainer;        // window background
    final int surfaceBright;           // preference item background
    final int surfaceContainerHigh;    // dialogs
    final int surfaceContainerHighest; // back button, switch track (off)
    final int primary;
    final int onPrimary;
    final int primaryContainer;
    final int onPrimaryContainer;
    final int secondaryContainer;
    final int onSurface;
    final int onSurfaceVariant;
    final int outline;
    final int outlineVariant;
    final int error;
    final int tertiary;

    Pal(Context c) {
        night = (c.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
        surfaceContainer = col(c, android.R.color.system_surface_container_light, android.R.color.system_surface_container_dark);
        surfaceBright = col(c, android.R.color.system_surface_bright_light, android.R.color.system_surface_bright_dark);
        surfaceContainerHigh = col(c, android.R.color.system_surface_container_high_light, android.R.color.system_surface_container_high_dark);
        surfaceContainerHighest = col(c, android.R.color.system_surface_container_highest_light, android.R.color.system_surface_container_highest_dark);
        primary = col(c, android.R.color.system_primary_light, android.R.color.system_primary_dark);
        onPrimary = col(c, android.R.color.system_on_primary_light, android.R.color.system_on_primary_dark);
        primaryContainer = col(c, android.R.color.system_primary_container_light, android.R.color.system_primary_container_dark);
        onPrimaryContainer = col(c, android.R.color.system_on_primary_container_light, android.R.color.system_on_primary_container_dark);
        secondaryContainer = col(c, android.R.color.system_secondary_container_light, android.R.color.system_secondary_container_dark);
        onSurface = col(c, android.R.color.system_on_surface_light, android.R.color.system_on_surface_dark);
        onSurfaceVariant = col(c, android.R.color.system_on_surface_variant_light, android.R.color.system_on_surface_variant_dark);
        outline = col(c, android.R.color.system_outline_light, android.R.color.system_outline_dark);
        outlineVariant = col(c, android.R.color.system_outline_variant_light, android.R.color.system_outline_variant_dark);
        error = col(c, android.R.color.system_error_light, android.R.color.system_error_dark);
        tertiary = col(c, android.R.color.system_tertiary_light, android.R.color.system_tertiary_dark);
    }

    private int col(Context c, int light, int dark) {
        return c.getColor(night ? dark : light);
    }

    static int alpha(int color, float a) {
        return (Math.round(a * 255) << 24) | (color & 0x00FFFFFF);
    }
}
