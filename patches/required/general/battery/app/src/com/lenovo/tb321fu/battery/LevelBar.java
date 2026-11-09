package com.lenovo.tb321fu.battery;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;

/**
 * M3 expressive linear progress indicator: rounded indicator in primary, a 4dp gap, the rest of
 * the track in secondaryContainer, and a small stop dot at the end of the track.
 * An optional marker (e.g. the charge limit) is drawn as a short vertical tick.
 */
final class LevelBar extends View {
    private final Pal pal;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF rect = new RectF();
    private final float heightDp;
    private int value = 0;   // 0..100
    private int marker = -1; // 0..100, -1 = none
    private int indicatorColor;

    LevelBar(Context c, Pal pal, float heightDp) {
        super(c);
        this.pal = pal;
        this.heightDp = heightDp;
        indicatorColor = pal.primary;
    }

    void set(int value, int marker) {
        this.value = Math.max(0, Math.min(100, value));
        boolean relayout = (marker >= 0) != (this.marker >= 0);
        this.marker = marker;
        if (relayout) requestLayout();
        invalidate();
    }

    void setIndicatorColor(int color) {
        indicatorColor = color;
        invalidate();
    }

    @Override
    protected void onMeasure(int wSpec, int hSpec) {
        int h = Ui.dp(getContext(), heightDp + (marker >= 0 ? 8 : 0));
        setMeasuredDimension(MeasureSpec.getSize(wSpec), h);
    }

    @Override
    protected void onDraw(Canvas cv) {
        Context c = getContext();
        float w = getWidth();
        float th = Ui.dpf(c, heightDp);
        float top = (getHeight() - th) / 2f;
        float r = th / 2f;
        float gap = Ui.dpf(c, 4);
        float split = w * value / 100f;

        paint.setStyle(Paint.Style.FILL);
        // Track (right part)
        float trackStart = value > 0 ? split + gap : 0;
        if (value < 100 && trackStart < w) {
            paint.setColor(pal.secondaryContainer);
            rect.set(trackStart, top, w, top + th);
            cv.drawRoundRect(rect, r, r, paint);
            // Stop dot
            float dot = Math.min(th, Ui.dpf(c, 4)) / 2f;
            paint.setColor(indicatorColor);
            cv.drawCircle(w - r, top + th / 2f, dot, paint);
        }
        // Indicator
        if (value > 0) {
            paint.setColor(indicatorColor);
            rect.set(0, top, Math.max(th, split), top + th);
            cv.drawRoundRect(rect, r, r, paint);
        }
        // Marker
        if (marker >= 0 && marker < 100) {
            float x = w * marker / 100f;
            float mw = Ui.dpf(c, 3);
            paint.setColor(pal.onSurfaceVariant);
            rect.set(x - mw / 2, 0, x + mw / 2, getHeight());
            cv.drawRoundRect(rect, mw / 2, mw / 2, paint);
        }
    }
}
