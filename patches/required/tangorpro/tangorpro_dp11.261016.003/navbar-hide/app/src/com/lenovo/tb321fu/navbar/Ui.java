package com.lenovo.tb321fu.navbar;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.util.TypedValue;
import android.view.View;
import android.widget.TextView;

import java.util.HashMap;
import java.util.Map;

/**
 * Sizes and type styles copied from SettingsLib (Android 16 expressive):
 *   TitleMedium  16sp / 24sp  variable-title-medium   (preference title)
 *   BodyMedium   14sp / 20sp  variable-body-medium    (preference summary)
 *   TitleSmall   14sp / 20sp  variable-title-small    (category title)
 *   TitleLarge.Emphasized 22sp  variable-title-large-emphasized (collapsed toolbar)
 *   DisplaySmall.Emphasized 36sp variable-display-small-emphasized (expanded toolbar)
 */
final class Ui {
    static final float CORNER_LARGE = 20f;  // settingslib_preference_corner_radius
    static final float CORNER_SMALL = 4f;   // inner corners in a group
    static final float SIDE_INSET = 16f;    // card inset from the screen edge
    static final float ITEM_GAP = 2f;       // gap between cards in a group

    private static final Map<String, Typeface> FONTS = new HashMap<>();

    private Ui() {
    }

    static int dp(Context c, float v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics()));
    }

    static float dpf(Context c, float v) {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics());
    }

    static int sp(Context c, float v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, c.getResources().getDisplayMetrics()));
    }

    /**
     * The system's variable font families (Google Sans Flex on Pixel builds). If the family is
     * missing, fall back to the default font at a comparable weight.
     */
    static Typeface font(String family, int fallbackWeight) {
        String key = family + "/" + fallbackWeight;
        Typeface t = FONTS.get(key);
        if (t != null) return t;
        Typeface f = Typeface.create(family, Typeface.NORMAL);
        if (f == null || f.equals(Typeface.DEFAULT)) {
            f = Typeface.create(Typeface.DEFAULT, fallbackWeight, false);
        }
        FONTS.put(key, f);
        return f;
    }

    static TextView text(Context c, float sizeSp, float lineSp, String family, int weight, int color) {
        TextView t = new TextView(c);
        style(t, sizeSp, lineSp, family, weight, color);
        return t;
    }

    static void style(TextView t, float sizeSp, float lineSp, String family, int weight, int color) {
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp);
        if (lineSp > 0) t.setLineHeight(sp(t.getContext(), lineSp));
        t.setTypeface(font(family, weight));
        t.setTextColor(color);
        t.setIncludeFontPadding(false);
        // Keep CJK fallback glyphs from making some lines taller than others.
        t.setFallbackLineSpacing(false);
    }

    static TextView titleMedium(Context c, Pal p) {
        TextView t = text(c, 16, 24, "variable-title-medium", 500, p.onSurface);
        t.setMaxLines(2);
        return t;
    }

    static TextView bodyMedium(Context c, Pal p) {
        TextView t = text(c, 14, 20, "variable-body-medium", 400, p.onSurfaceVariant);
        t.setMaxLines(10);
        return t;
    }

    static GradientDrawable rounded(Context c, int color, float tl, float tr, float br, float bl) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        float a = dpf(c, tl), b = dpf(c, tr), d = dpf(c, br), e = dpf(c, bl);
        g.setCornerRadii(new float[]{a, a, b, b, d, d, e, e});
        return g;
    }

    static GradientDrawable roundedAll(Context c, int color, float r) {
        return rounded(c, color, r, r, r, r);
    }

    /** Ripple in SettingsLib's ripple color (onSurface at ~10%), clipped to the content shape. */
    static Drawable ripple(Pal p, Drawable content) {
        return new RippleDrawable(ColorStateList.valueOf(Pal.alpha(p.onSurface, 0.10f)), content, null);
    }

    static void setVisible(View v, boolean visible) {
        v.setVisibility(visible ? View.VISIBLE : View.GONE);
    }
}
