package com.lenovo.tb321fu.attest;

import android.content.Context;
import android.graphics.drawable.Drawable;
import android.widget.LinearLayout;

/**
 * A card in a SettingsLib expressive group. The group decides the corners from the card's
 * position: single = 20dp all round; first = 20dp top / 4dp bottom; middle = 4dp; last = 4dp top /
 * 20dp bottom. Background is surfaceBright, with a ripple when the card is clickable.
 */
class Shaped extends LinearLayout {
    final Pal pal;
    private float[] corners = {Ui.CORNER_LARGE, Ui.CORNER_LARGE, Ui.CORNER_LARGE, Ui.CORNER_LARGE};

    Shaped(Context c, Pal pal) {
        super(c);
        this.pal = pal;
        applyShape(corners[0], corners[1], corners[2], corners[3]);
    }

    void applyShape(float tl, float tr, float br, float bl) {
        corners = new float[]{tl, tr, br, bl};
        Drawable bg = Ui.rounded(getContext(), pal.surfaceBright, tl, tr, br, bl);
        setBackground(isClickable() ? Ui.ripple(pal, bg) : bg);
        setClipToOutline(true);
    }

    @Override
    public void setOnClickListener(OnClickListener l) {
        super.setOnClickListener(l);
        applyShape(corners[0], corners[1], corners[2], corners[3]);
    }
}
