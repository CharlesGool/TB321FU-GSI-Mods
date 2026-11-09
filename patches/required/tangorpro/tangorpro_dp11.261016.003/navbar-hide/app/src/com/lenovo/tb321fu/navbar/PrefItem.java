package com.lenovo.tb321fu.navbar;

import android.content.Context;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * One preference row, laid out like SettingsLib's expressive preference:
 * minHeight 72dp, 16dp start/end padding, text block with 16dp vertical padding and 16dp end
 * padding, title TitleMedium / summary BodyMedium, widget frame at the end (min 40dp wide).
 *
 * Switch styles:
 *   SWITCH         - the whole row toggles (SwitchPreference)
 *   PRIMARY_SWITCH - the row opens details, the switch after a divider toggles (PrimarySwitchPreference)
 */
final class PrefItem extends Shaped {
    static final int NONE = 0, SWITCH = 1, PRIMARY_SWITCH = 2;

    interface ToggleListener {
        void onToggle(PrefItem item, boolean wantOn);
    }

    final TextView title;
    final TextView summary;
    final TextView value;
    M3Switch sw;
    private View switchArea;
    private int mode = NONE;
    private ToggleListener toggle;
    private boolean busy;

    PrefItem(Context c, Pal pal, CharSequence titleText) {
        super(c, pal);
        setOrientation(HORIZONTAL);
        setGravity(Gravity.CENTER_VERTICAL);
        setMinimumHeight(Ui.dp(c, 72));
        setPaddingRelative(Ui.dp(c, 16), 0, Ui.dp(c, 16), 0);

        LinearLayout texts = new LinearLayout(c);
        texts.setOrientation(VERTICAL);
        texts.setPaddingRelative(0, Ui.dp(c, 16), Ui.dp(c, 16), Ui.dp(c, 16));
        title = Ui.titleMedium(c, pal);
        title.setText(titleText);
        summary = Ui.bodyMedium(c, pal);
        summary.setVisibility(GONE);
        texts.addView(title);
        texts.addView(summary);
        addView(texts, new LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        // Right-aligned value text (used for read-only rows such as "循环次数   265 次").
        value = Ui.text(c, 16, 24, "variable-title-medium", 500, pal.onSurfaceVariant);
        value.setVisibility(GONE);
        addView(value, new LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
    }

    PrefItem summary(CharSequence s) {
        summary.setText(s);
        Ui.setVisible(summary, s != null && s.length() > 0);
        return this;
    }

    PrefItem value(CharSequence s) {
        value.setText(s);
        Ui.setVisible(value, s != null && s.length() > 0);
        return this;
    }

    PrefItem withSwitch(int mode, ToggleListener l) {
        Context c = getContext();
        this.mode = mode;
        this.toggle = l;
        sw = new M3Switch(c, pal);
        if (mode == PRIMARY_SWITCH) {
            View div = new View(c);
            div.setBackgroundColor(pal.outlineVariant);
            LayoutParams dl = new LayoutParams(Ui.dp(c, 1), Ui.dp(c, 32));
            dl.setMarginEnd(Ui.dp(c, 16));
            addView(div, dl);
            // Make the switch's touch area the full row height on its side of the divider.
            LinearLayout area = new LinearLayout(c);
            area.setGravity(Gravity.CENTER);
            area.addView(sw);
            area.setOnClickListener(v -> requestToggle());
            area.setContentDescription(title.getText());
            switchArea = area;
            addView(area, new LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT));
        } else {
            addView(sw, new LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            setOnClickListener(v -> requestToggle());
        }
        return this;
    }

    private void requestToggle() {
        if (busy || !isEnabled() || sw == null || !sw.isEnabled()) return;
        if (toggle != null) toggle.onToggle(this, !sw.isChecked());
    }

    void setChecked(boolean on, boolean animate) {
        if (sw != null) sw.setChecked(on, animate);
    }

    /** While a backend call is running the switch is frozen. */
    void setBusy(boolean b) {
        busy = b;
    }

    boolean isBusy() {
        return busy;
    }

    void setRowEnabled(boolean enabled) {
        setEnabled(enabled);
        float a = enabled ? 1f : 0.38f;
        title.setAlpha(a);
        summary.setAlpha(a);
        if (sw != null) sw.setEnabled(enabled);
        if (switchArea != null) switchArea.setEnabled(enabled);
    }

    /** For PRIMARY_SWITCH: the row stays usable (to open settings) but the switch can be disabled. */
    void setSwitchEnabled(boolean enabled) {
        if (sw != null) sw.setEnabled(enabled);
        if (switchArea != null) switchArea.setEnabled(enabled);
    }
}
