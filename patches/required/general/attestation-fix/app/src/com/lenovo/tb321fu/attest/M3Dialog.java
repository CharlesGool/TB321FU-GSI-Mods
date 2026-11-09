package com.lenovo.tb321fu.attest;

import android.app.Activity;
import android.app.Dialog;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Material 3 basic dialog drawn by hand (the app uses no libraries): 28dp corners on
 * surfaceContainerHigh, 24dp padding, headlineSmall title, bodyMedium supporting text in
 * onSurfaceVariant, and end-aligned text buttons in primary (labelLarge). Width 280-560dp.
 */
final class M3Dialog {
    interface Click {
        /** Return false to keep the dialog open (e.g. invalid input). */
        boolean onClick();
    }

    private final Activity a;
    private final Pal pal;
    private final Dialog d;
    private final LinearLayout box;
    private final LinearLayout content;
    private final LinearLayout buttons;

    M3Dialog(Activity a, Pal pal) {
        this.a = a;
        this.pal = pal;
        d = new Dialog(a);
        d.requestWindowFeature(Window.FEATURE_NO_TITLE);
        box = new LinearLayout(a);
        box.setOrientation(LinearLayout.VERTICAL);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(pal.surfaceContainerHigh);
        bg.setCornerRadius(Ui.dpf(a, 28));
        box.setBackground(bg);
        box.setPaddingRelative(0, Ui.dp(a, 24), 0, Ui.dp(a, 24));
        content = new LinearLayout(a);
        content.setOrientation(LinearLayout.VERTICAL);
        ScrollView sv = new ScrollView(a);
        sv.addView(content);
        box.addView(sv, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        buttons = new LinearLayout(a);
        buttons.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams bl = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        bl.topMargin = Ui.dp(a, 24);
        buttons.setPaddingRelative(Ui.dp(a, 24), 0, Ui.dp(a, 24), 0);
        box.addView(buttons, bl);
    }

    M3Dialog title(String t) {
        TextView v = Ui.text(a, 24, 32, "variable-headline-small", 400, pal.onSurface);
        v.setText(t);
        v.setPaddingRelative(Ui.dp(a, 24), 0, Ui.dp(a, 24), Ui.dp(a, 16));
        content.addView(v, 0);
        return this;
    }

    M3Dialog message(String m) {
        TextView v = Ui.text(a, 14, 20, "variable-body-medium", 400, pal.onSurfaceVariant);
        v.setText(m);
        v.setPaddingRelative(Ui.dp(a, 24), 0, Ui.dp(a, 24), 0);
        content.addView(v);
        return this;
    }

    /** Custom body; it gets the 24dp side padding. */
    M3Dialog view(View v) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMarginStart(Ui.dp(a, 24));
        lp.setMarginEnd(Ui.dp(a, 24));
        content.addView(v, lp);
        return this;
    }

    M3Dialog button(String label, Click c) {
        TextView b = Ui.text(a, 14, 20, "variable-label-large", 500, pal.primary);
        b.setText(label);
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(Ui.dp(a, 40));
        b.setMinWidth(Ui.dp(a, 48));
        b.setPaddingRelative(Ui.dp(a, 12), 0, Ui.dp(a, 12), 0);
        GradientDrawable shape = new GradientDrawable();
        shape.setCornerRadius(Ui.dpf(a, 20));
        shape.setColor(Color.TRANSPARENT);
        GradientDrawable mask = new GradientDrawable();
        mask.setCornerRadius(Ui.dpf(a, 20));
        mask.setColor(Color.WHITE);
        b.setBackground(new android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(Pal.alpha(pal.primary, 0.12f)), shape, mask));
        b.setOnClickListener(v -> {
            if (c == null || c.onClick()) d.dismiss();
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        if (buttons.getChildCount() > 0) lp.setMarginStart(Ui.dp(a, 8));
        buttons.addView(b, lp);
        return this;
    }

    void dismiss() {
        d.dismiss();
    }

    /** Taps outside / back do nothing (used while an action is running). */
    M3Dialog modal() {
        d.setCancelable(false);
        return this;
    }

    void show() {
        d.setContentView(box);
        Window w = d.getWindow();
        if (w != null) {
            w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            int screen = a.getResources().getConfiguration().screenWidthDp;
            int width = Math.max(280, Math.min(560, screen - 48));
            w.setLayout(Ui.dp(a, width), ViewGroup.LayoutParams.WRAP_CONTENT);
            w.setDimAmount(0.32f);
        }
        d.show();
    }
}
