package com.lenovo.tb321fu.attest;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.animation.PathInterpolator;
import android.widget.Switch;

/**
 * Material 3 switch with thumb icons, as in Android 16 Settings:
 * track 52x32dp; on = primary track, onPrimary thumb (24dp) with a check in onPrimaryContainer;
 * off = surfaceContainerHighest track with a 2dp outline, outline thumb (24dp) with a cross.
 * Disabled: 38% opacity.
 *
 * The view does not toggle itself; the owner decides (some changes need confirmation or a
 * backend round trip) and calls setChecked().
 */
final class M3Switch extends View {
    private final Pal pal;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF rect = new RectF();
    private final Drawable check;
    private final Drawable close;
    private boolean checked;
    private float pos; // 0 = off, 1 = on
    private ValueAnimator anim;

    M3Switch(Context c, Pal pal) {
        super(c);
        this.pal = pal;
        check = c.getDrawable(R.drawable.ic_switch_check).mutate();
        close = c.getDrawable(R.drawable.ic_switch_close).mutate();
        setMinimumWidth(Ui.dp(c, 52));
        setMinimumHeight(Ui.dp(c, 32));
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    @Override
    protected void onMeasure(int w, int h) {
        setMeasuredDimension(Ui.dp(getContext(), 52), Ui.dp(getContext(), 32));
    }

    boolean isChecked() {
        return checked;
    }

    void setChecked(boolean on, boolean animate) {
        if (on == checked && anim == null) {
            if (!animate) {
                pos = on ? 1 : 0;
                invalidate();
            }
            return;
        }
        checked = on;
        if (anim != null) anim.cancel();
        anim = null;
        if (!animate || !isAttachedToWindow()) {
            pos = on ? 1 : 0;
            invalidate();
            return;
        }
        anim = ValueAnimator.ofFloat(pos, on ? 1 : 0);
        anim.setDuration(250);
        anim.setInterpolator(new PathInterpolator(0.2f, 0f, 0f, 1f));
        anim.addUpdateListener(a -> {
            pos = (float) a.getAnimatedValue();
            invalidate();
        });
        anim.addListener(new android.animation.AnimatorListenerAdapter() {
            @Override
            public void onAnimationEnd(android.animation.Animator a) {
                anim = null;
            }
        });
        anim.start();
    }

    @Override
    public void setEnabled(boolean enabled) {
        super.setEnabled(enabled);
        invalidate();
    }

    @Override
    protected void onDraw(Canvas cv) {
        Context c = getContext();
        float w = getWidth(), h = getHeight();
        float r = h / 2f;
        float stroke = Ui.dpf(c, 2);
        int alpha = isEnabled() ? 255 : 97; // 38%

        // Track
        int trackOff = pal.surfaceContainerHighest;
        int trackOn = pal.primary;
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(blend(trackOff, trackOn, pos));
        paint.setAlpha(isEnabled() ? 255 : 31); // track disabled 12%
        rect.set(0, 0, w, h);
        cv.drawRoundRect(rect, r, r, paint);
        if (pos < 1f) {
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(stroke);
            paint.setColor(pal.outline);
            paint.setAlpha(Math.round((1f - pos) * (isEnabled() ? 255 : 31)));
            rect.set(stroke / 2, stroke / 2, w - stroke / 2, h - stroke / 2);
            cv.drawRoundRect(rect, r - stroke / 2, r - stroke / 2, paint);
        }

        // Thumb: 24dp with icon; centered 4dp from the track edge.
        float tr = Ui.dpf(c, 12);
        float cxOff = r;
        float cxOn = w - r;
        float cx = cxOff + (cxOn - cxOff) * pos;
        float cy = h / 2f;
        paint.setStyle(Paint.Style.FILL);
        int thumbOff = pal.outline;
        int thumbOn = pal.onPrimary;
        paint.setColor(blend(thumbOff, thumbOn, pos));
        paint.setAlpha(alpha);
        cv.drawCircle(cx, cy, tr, paint);

        // Icon 16dp
        int is = Ui.dp(c, 16);
        int l = Math.round(cx - is / 2f), t = Math.round(cy - is / 2f);
        Drawable icon = pos >= 0.5f ? check : close;
        icon.setTint(pos >= 0.5f ? pal.onPrimaryContainer : pal.surfaceContainerHighest);
        icon.setBounds(l, t, l + is, t + is);
        icon.setAlpha(Math.round(alpha * Math.abs(pos - 0.5f) * 2f));
        icon.draw(cv);
    }

    @Override
    public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info) {
        super.onInitializeAccessibilityNodeInfo(info);
        info.setClassName(Switch.class.getName());
        info.setCheckable(true);
        info.setChecked(checked);
    }

    static int blend(int a, int b, float t) {
        int ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
        int br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
        return 0xFF000000
                | (Math.round(ar + (br - ar) * t) << 16)
                | (Math.round(ag + (bg - ag) * t) << 8)
                | Math.round(ab + (bb - ab) * t);
    }
}
