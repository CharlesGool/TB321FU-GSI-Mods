package com.lenovo.tb321fu.navbar;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;

import java.util.ArrayList;
import java.util.List;

/**
 * A group of cards with 2dp gaps, inset 16dp from the screen edges. Children are {@link Shaped}
 * cards, or a horizontal {@link Row} of cards (used for the two battery cells on wide screens).
 * Call {@link #updateShapes()} after changing which children are visible.
 */
final class PrefGroup extends LinearLayout {

    /** Cards side by side; to the group the row is one position. */
    static final class Row extends LinearLayout {
        Row(Context c) {
            super(c);
            setOrientation(HORIZONTAL);
        }

        void addCard(Shaped card) {
            LayoutParams lp = new LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f);
            if (getChildCount() > 0) lp.setMarginStart(Ui.dp(getContext(), Ui.ITEM_GAP));
            addView(card, lp);
        }
    }

    PrefGroup(Context c) {
        super(c);
        setOrientation(VERTICAL);
        int side = Ui.dp(c, Ui.SIDE_INSET);
        setPadding(side, 0, side, 0);
    }

    void addItem(View v) {
        addView(v, new LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
    }

    void updateShapes() {
        List<View> vis = new ArrayList<>();
        for (int i = 0; i < getChildCount(); i++) {
            View v = getChildAt(i);
            if (v.getVisibility() != GONE) vis.add(v);
        }
        int gap = Ui.dp(getContext(), Ui.ITEM_GAP);
        float L = Ui.CORNER_LARGE, S = Ui.CORNER_SMALL;
        for (int i = 0; i < vis.size(); i++) {
            View v = vis.get(i);
            boolean first = i == 0, last = i == vis.size() - 1;
            float top = first ? L : S;
            float bottom = last ? L : S;
            LayoutParams lp = (LayoutParams) v.getLayoutParams();
            int want = first ? 0 : gap;
            if (lp.topMargin != want) {
                lp.topMargin = want;
                v.setLayoutParams(lp);
            }
            if (v instanceof Shaped) {
                ((Shaped) v).applyShape(top, top, bottom, bottom);
            } else if (v instanceof Row) {
                Row row = (Row) v;
                List<Shaped> cards = new ArrayList<>();
                for (int j = 0; j < row.getChildCount(); j++) {
                    View c = row.getChildAt(j);
                    if (c.getVisibility() != GONE && c instanceof Shaped) cards.add((Shaped) c);
                }
                boolean rtl = getLayoutDirection() == LAYOUT_DIRECTION_RTL;
                for (int j = 0; j < cards.size(); j++) {
                    boolean leftEdge = rtl ? j == cards.size() - 1 : j == 0;
                    boolean rightEdge = rtl ? j == 0 : j == cards.size() - 1;
                    cards.get(j).applyShape(leftEdge ? top : S, rightEdge ? top : S,
                            rightEdge ? bottom : S, leftEdge ? bottom : S);
                }
            }
        }
    }
}
